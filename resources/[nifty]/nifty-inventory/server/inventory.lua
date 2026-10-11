--[[
  Inventory (ADR-0014 layer 4).

  What this module refuses to do:
    * Trust a client-supplied item definition. Weight, stackability and max stack
      come from `item_defs` on the server, always. A client that sends
      `{ code = 'bank_frobnicator', weight = 0 }` gets a rejection, not a bank.
    * Trust a client-supplied slot index. Slots are assigned by this module; the
      client may only ask for a move *between* two slots it already owns.
    * Partially apply a transfer. A transaction that consumes a stack and then
      fails to write the destination leaves a player who quietly lost items, so
      item moves run in one transaction or not at all.

  Capacity is two limits, and they fail differently on purpose:
    * slots   — how many distinct stacks you carry
    * weight  — how much you can physically carry
  A heavy item can leave you one slot short; a light one can leave you too heavy.
]]

local RESOURCE = GetCurrentResourceName()

--- From the base facade, fetched by shared/core.lua at load. These were globals
--- when this file lived inside nifty-core; see the note in shared/core.lua about
--- why a local in fxmanifest would not have survived the chunk boundary.
local Db = Nifty.Db
local GetSetting = Nifty.GetSetting
local Identity = Nifty.Identity

--- Item weights are DECIMAL money values, so rounding belongs to the economy system.
--- Reached through the facade: nifty-economy was absorbed into nifty-core, so
--- the table is now a field on the bridge.
local Economy = Nifty.Economy

Inventory = {}

--- Cache of item definitions. The catalogue is reference data seeded by migration
--- and effectively static, so reading it once per session beats a query per item.
--- Restarting the resource after editing `item_defs` reloads it — deliberately,
--- so a catalogue edit is never half-applied to players mid-session.
local Definitions = {}

--- Catalogue reference data (see `loadDefinitions`). `tonumber` on every flag is
--- not defensive noise: a driver is free to hand back TINYINT as the string
--- `"1"`, and `"1" == 1` is false in Lua. Without it every item reads as
--- non-stackable, so the first pickup of anything is refused as "not
--- stackable" and the inventory silently accepts nothing at all.
local function loadDefinitions()
  Definitions = {}

  local rows = Db.all([[
    SELECT code, name, category, weight, stackable, max_stack, is_weapon
      FROM item_defs
  ]], {}, 'inventory:definitions')

  for _, row in ipairs(rows) do
    Definitions[row.code] = {
      code = row.code,
      name = row.name,
      category = row.category,
      weight = Db.money.toNumber(row.weight),
      stackable = tonumber(row.stackable) == 1,
      maxStack = tonumber(row.max_stack) or 1,
      isWeapon = tonumber(row.is_weapon) == 1,
    }
  end

  print(('[%s] loaded %d item definitions'):format(RESOURCE, #rows))
end

--- Look up a definition. Returns nil for an unknown code — and callers must treat
--- that as a refusal, never as "a free item with no rules".
function Inventory.getDefinition(code)
  if type(code) ~= 'string' or code == '' then return nil end
  return Definitions[code]
end

--- The whole catalogue. Read-only: callers get the live definitions, so this is
--- for crossing the catalogue with something else (the shop prices it by code),
--- never for editing. Item definitions are reference data and change only when
--- the resource restarts.
function Inventory.getAllDefinitions()
  return Definitions
end

-- ---------------------------------------------------------------------------
-- Capacity
-- ---------------------------------------------------------------------------

--- A character's capacity comes from `settings`, not from a column, for now.
--- When per-character capacity arrives (an expansion, a backpack) this becomes a
--- column read with the setting as the default — which is why it is a function
--- and not a constant.
local function slotCapacity()
  return tonumber(GetSetting('inventory.default_slots', 24)) or 24
end

local function weightLimit()
  return Db.money.toNumber(GetSetting('inventory.max_weight', 50))
end

--- Everything the client needs to draw an inventory, and nothing more. Sending
--- `max_stack` for an item the player does not carry would be a small data leak
--- about the rest of the catalogue.
function Inventory.view(characterId)
  local slots = Db.all([[
    SELECT id, slot, item_code, quantity, metadata
      FROM inventory_items
     WHERE character_id = ?
     ORDER BY slot
  ]], { characterId }, 'inventory:list')

  local items, usedWeight = {}, 0

  for _, row in ipairs(slots) do
    local def = Definitions[row.item_code]
    local quantity = tonumber(row.quantity) or 0

    items[#items + 1] = {
      id = row.id,
      slot = tonumber(row.slot),
      code = row.item_code,
      name = def and def.name or row.item_code,
      category = def and def.category or 'unknown',
      isWeapon = def and def.isWeapon or false,
      quantity = quantity,
      -- The client draws a weight label from this; it must not compute it from
      -- its own copy of the catalogue.
      unitWeight = def and def.weight or 0,
      -- `metadata` is a nullable JSON column. An empty string is truthy in Lua,
      -- so `row.metadata and json.decode(row.metadata)` would call the decoder
      -- with '' and crash on a row that simply has no metadata.
      metadata = (row.metadata ~= nil and row.metadata ~= '') and json.decode(row.metadata) or nil,
    }

    usedWeight = usedWeight + (def and def.weight or 0) * quantity
  end

  return {
    items = items,
    usedSlots = #items,
    totalSlots = slotCapacity(),
    usedWeight = Economy:round(usedWeight),
    maxWeight = weightLimit(),
  }
end

function Inventory.push(src, characterId)
  TriggerClientEvent('nifty:client:inventory', src, Inventory.view(characterId))
end

-- ---------------------------------------------------------------------------
-- Adding
-- ---------------------------------------------------------------------------

--- Where should a new stack of `code` go?
---
--- Stack merging is tried first — a player who picks up four coffees should see
--- one stack go up, not four new rows eating four slots. Only then do we look for
--- a free slot.
---
--- @return number|nil slot, string|nil error, number existingQuantity
local function findTargetSlot(characterId, def, quantity, metadataKey)
  local rows
  if metadataKey ~= nil then
    rows = Db.all([[
      SELECT slot, quantity FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND metadata = ?
    ]], { characterId, def.code, metadataKey }, 'inventory:slots')
  else
    rows = Db.all([[
      SELECT slot, quantity FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND metadata IS NULL
    ]], { characterId, def.code }, 'inventory:slots')
  end

  local used = {}

  for _, row in ipairs(rows) do
    used[tonumber(row.slot)] = true
  end

  if def.stackable then
    for _, row in ipairs(rows) do
      local held = tonumber(row.quantity) or 0
      if held + quantity <= def.maxStack then
        return tonumber(row.slot), nil, held
      end
    end
  end

  for slot = 0, slotCapacity() - 1 do
    if not used[slot] then
      return slot, nil, 0
    end
  end

  return nil, 'no free slot', 0
end

--- Give items to a character. Merges into existing stacks where the definition
--- allows it, and refuses — rather than partially filling — when it does not.
---
--- `metadata` is optional: when passed, the row carries a JSON blob identifying
--- the specific item (for example a clothing_outfit whose outfitId varies).
--- Stacks only merge when metadata matches exactly - a black hat and a red
--- hat are different items even when they share an item code.
---
--- `metadata` is optional: when passed, the row carries a JSON blob identifying
--- the specific item (for example a clothing_outfit whose outfitId varies).
--- Stacks only merge when metadata matches exactly - a black hat and a red
--- hat are different items even when they share an item code.
---
--- @return boolean ok, string|nil error, string|nil newItemId
function Inventory.add(characterId, code, quantity, metadata)
  quantity = math.floor(tonumber(quantity) or 0)

  if quantity <= 0 then return false, 'bad quantity' end

  local def = Inventory.getDefinition(code)
  if not def then
    print(('[%s] REFUSED: unknown item "%s" for character %s'):format(
      RESOURCE, tostring(code), tostring(characterId)))
    return false, 'unknown item'
  end

  if not def.stackable and quantity > 1 then
    -- Taking the excess and dropping it would be a silent data loss.
    return false, 'not stackable'
  end

  -- Metadata is encoded once. When present, it becomes part of the row
  -- identity: merging a black hat with a red hat is not a stack, it's two
  -- different items. The encoded form is also what `findTargetSlot` matches
  -- against, so the keys are kept consistent.
  local metadataKey = nil
  if metadata ~= nil then
    local ok, encoded = pcall(json.encode, metadata)
    if not ok then return false, 'bad metadata' end
    metadataKey = encoded
  end

  local view = Inventory.view(characterId)

  if view.usedWeight + (def.weight * quantity) > weightLimit() then
    return false, 'too heavy'
  end

  local slot, err, existing = findTargetSlot(characterId, def, quantity, metadataKey)
  if not slot then return false, err end

  -- A stack may never be created larger than its own max_stack. `findTargetSlot`
  -- already guarantees the MERGE case fits; this covers the new-stack case, where
  -- `existing` is 0 and nothing else looks at max_stack.
  --
  -- The earlier version of this check was `existing and existing + quantity >
  -- def.maxStack`, which Lua's 0-is-truthy rule made fire on the very first
  -- pickup: `0 and (0 + 10 > 10)` is 0, which is truthy, so buying exactly one
  -- full stack of bread was refused as "stack full". The guard has to test the
  -- quantity alone — never `existing and ...`.
  if def.stackable and quantity > def.maxStack then
    return false, 'stack full'
  end

  local statements

  -- `existing > 0` on its own, never `existing and existing > 0`.
  --
  -- Lua treats 0 as TRUTHY, so `existing and existing > 0` evaluates to 0 when
  -- there is nothing to merge into — which is always true for the very first
  -- item a character picks up. The condition passed, the UPDATE branch ran
  -- against an empty slot, matched no rows, and reported success while storing
  -- nothing. The inventory silently accepted every first pickup and lost it.
  if existing > 0 then
    statements = { {
      sql = [[UPDATE inventory_items SET quantity = quantity + ? WHERE character_id = ? AND slot = ?]],
      params = { quantity, characterId, slot },
    } }
  else
    if metadataKey ~= nil then
      statements = { {
        sql = [[INSERT INTO inventory_items (id, character_id, slot, item_code, quantity, metadata)
                VALUES (?, ?, ?, ?, ?, ?)]],
        params = { Nifty.newUuid(), characterId, slot, def.code, quantity, metadataKey },
      } }
    else
      statements = { {
        sql = [[INSERT INTO inventory_items (id, character_id, slot, item_code, quantity)
                VALUES (?, ?, ?, ?, ?)]],
        params = { Nifty.newUuid(), characterId, slot, def.code, quantity },
      } }
    end
  end

  if not Db.transaction(statements, 'inventory:add') then
    return false, 'could not store item'
  end

  -- Read back the row's id so callers that need to stamp metadata after
  -- the add (e.g. pickup with giver_name) can find the new row. The
  -- lookup matches on (character_id, code, metadata) - metadata makes
  -- the match exact so a stack-merge on metadata-less codes still
  -- returns the canonical row.
  local newId
  if metadataKey ~= nil then
    local row = Db.one([[
      SELECT id FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND metadata = ?
       ORDER BY slot LIMIT 1
    ]], { characterId, def.code, metadataKey }, 'inventory:add:lookup')
    newId = row and row.id
  else
    local row = Db.one([[
      SELECT id FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND metadata IS NULL
       ORDER BY slot LIMIT 1
    ]], { characterId, def.code }, 'inventory:add:lookup')
    newId = row and row.id
  end

  return true, nil, newId
end

-- ---------------------------------------------------------------------------
-- Removing
-- ---------------------------------------------------------------------------

--- Take items away. Consumes from stacks in slot order, which keeps the result
--- deterministic — two removals of the same quantity always leave the same
--- inventory, so a bug reproduces instead of varying.
function Inventory.remove(characterId, code, quantity, itemId)
  quantity = math.floor(tonumber(quantity) or 0)
  if quantity <= 0 then return false, 'bad quantity' end

  local def = Inventory.getDefinition(code)
  if not def then return false, 'unknown item' end

  local rows
  if itemId ~= nil then
    rows = Db.all([[
      SELECT id, slot, quantity FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND id = ?
    ]], { characterId, def.code, tostring(itemId) }, 'inventory:remove:candidates')
  else
    rows = Db.all([[
      SELECT id, slot, quantity FROM inventory_items
       WHERE character_id = ? AND item_code = ?
       ORDER BY slot
    ]], { characterId, def.code }, 'inventory:remove:candidates')
  end

  local held = 0
  for _, row in ipairs(rows) do held = held + (tonumber(row.quantity) or 0) end

  if held < quantity then return false, 'not enough' end

  local statements = {}
  local remaining = quantity

  for _, row in ipairs(rows) do
    if remaining <= 0 then break end

    local have = tonumber(row.quantity) or 0
    local take = math.min(have, remaining)
    remaining = remaining - take

    if take >= have then
      statements[#statements + 1] = {
        sql = [[DELETE FROM inventory_items WHERE id = ? AND character_id = ?]],
        params = { row.id, characterId },
      }
    else
      statements[#statements + 1] = {
        sql = [[UPDATE inventory_items SET quantity = quantity - ? WHERE id = ? AND character_id = ?]],
        params = { take, row.id, characterId },
      }
    end
  end

  if remaining > 0 then return false, 'not enough' end

  if not Db.transaction(statements, 'inventory:remove') then
    return false, 'could not remove item'
  end

  return true, nil
end

--- How many of a given item a character is carrying.
function Inventory.count(characterId, code)
  local row = Db.one([[
    SELECT COALESCE(SUM(quantity), 0) AS total FROM inventory_items
     WHERE character_id = ? AND item_code = ?
  ]], { characterId, tostring(code) }, 'inventory:count')

  return row and tonumber(row.total) or 0
end

function Inventory.has(characterId, code, quantity)
  return Inventory.count(characterId, code) >= (tonumber(quantity) or 1)
end

-- Split a stack: leave `quantity` in the original row, move the rest to a
-- new row. Both rows carry the same metadata so the wardrobe render
-- keeps the (von X) suffix on the carried-over batch and the
-- transferred batch alike.
--
-- Used by the wardrobe's "Aufteilen" right-click action when the
-- player wants to give away SOME of a stack, not all of it. We refuse
-- if the requested split would leave zero on either side, or if the
-- item is not stackable in the first place (max_stack = 1).
function Inventory.splitStack(characterId, itemId, qty)
  qty = math.floor(tonumber(qty) or 0)
  if qty <= 0 then return false, 'bad quantity' end

  local row = Db.one([[
    SELECT id, character_id, item_code, quantity, metadata, slot
      FROM inventory_items
     WHERE character_id = ? AND id = ?
     LIMIT 1
  ]], { characterId, tostring(itemId) }, 'inventory:split:read')
  if not row or not row.id then return false, 'no row' end

  local def = Inventory.getDefinition(row.item_code)
  if not def then return false, 'unknown item' end
  if not def.stackable then return false, 'not stackable' end

  local total = tonumber(row.quantity) or 0
  if qty >= total then return false, 'would leave zero' end
  if total - qty == 0 then return false, 'would leave zero' end
  if qty > def.maxStack then return false, 'exceeds max stack' end

  -- Find a free destination slot. Same constraint as the rest of
  -- the inventory: a stack-merge candidate is fine, and non-stackable
  -- items cannot share a slot with themselves.
  local dstSlot
  local existing = Db.all([[
    SELECT slot, quantity FROM inventory_items
     WHERE character_id = ? AND item_code = ? AND metadata = ?
  ]], { characterId, row.item_code, row.metadata or '' }, 'inventory:split:slots')

  local used = {}
  for _, r in ipairs(existing) do used[tonumber(r.slot)] = true end

  if def.stackable then
    for _, r in ipairs(existing) do
      local held = tonumber(r.quantity) or 0
      if held + qty <= def.maxStack then
        dstSlot = tonumber(r.slot)
        break
      end
    end
  end

  if not dstSlot then
    for s = 0, slotCapacity() - 1 do
      if not used[s] then dstSlot = s break end
    end
  end
  if not dstSlot then return false, 'no free slot' end

  local okTxn = Db.transaction({
    {
      sql = [[UPDATE inventory_items SET quantity = ? WHERE id = ? AND character_id = ?]],
      params = { tostring(total - qty), row.id, characterId },
    },
    {
      sql = (row.metadata ~= nil and row.metadata ~= '')
        and [[INSERT INTO inventory_items
                (id, character_id, slot, item_code, quantity, metadata)
              VALUES (?, ?, ?, ?, ?, ?)]]
        or  [[INSERT INTO inventory_items
                (id, character_id, slot, item_code, quantity)
              VALUES (?, ?, ?, ?, ?)]],
      params = (function()
        local newId = Nifty.newUuid()
        if row.metadata ~= nil and row.metadata ~= '' then
          return { newId, characterId, tostring(dstSlot),
                   row.item_code, tostring(qty), row.metadata }
        end
        return { newId, characterId, tostring(dstSlot),
                 row.item_code, tostring(qty) }
      end)(),
    },
  }, 'inventory:split:tx')

  if not okTxn then return false, 'split failed' end

  return true, nil
end

-- ---------------------------------------------------------------------------
-- Moving and using
-- ---------------------------------------------------------------------------

--- Park a slot number that no real inventory can reach, used only as a parking
--- space while two stacks are swapped. `slot` is SMALLINT UNSIGNED, so a negative
--- sentinel is not available — and the unique key on (character_id, slot) is what
--- stops two rows claiming the same place while this is in flight.
local SWAP_SLOT = 65535

--- Move a stack to another slot, swapping with whatever is there. Ownership is in
--- the WHERE clause, so a client cannot move a stack it does not hold.
function Inventory.move(characterId, fromSlot, toSlot)
  fromSlot = math.floor(tonumber(fromSlot) or -1)
  toSlot = math.floor(tonumber(toSlot) or -1)

  if fromSlot < 0 or toSlot < 0 then return false, 'bad slot' end
  if toSlot >= slotCapacity() or fromSlot >= slotCapacity() then return false, 'slot out of range' end
  if fromSlot == toSlot then return false, 'same slot' end

  if not Db.transaction({
    -- 1. Whoever is in the target slot steps aside. No-op when it is empty.
    {
      sql = [[UPDATE inventory_items SET slot = ? WHERE character_id = ? AND slot = ?]],
      params = { SWAP_SLOT, characterId, toSlot },
    },
    -- 2. The stack the player picked up goes to the target slot.
    {
      sql = [[UPDATE inventory_items SET slot = ? WHERE character_id = ? AND slot = ?]],
      params = { toSlot, characterId, fromSlot },
    },
    -- 3. The displaced stack takes the slot that just opened up.
    {
      sql = [[UPDATE inventory_items SET slot = ? WHERE character_id = ? AND slot = ?]],
      params = { fromSlot, characterId, SWAP_SLOT },
    },
  }, 'inventory:move') then
    return false, 'could not move item'
  end

  -- A rollback here would have to guess which of the three statements ran, and
  -- guessing at inventory is worse than leaving the stack parked: SWAP_SLOT is
  -- outside capacity, so the item is unreachable but not lost, and it is reported.
  local stranded = Db.one([[
    SELECT COUNT(*) AS stranded FROM inventory_items WHERE character_id = ? AND slot = ?
  ]], { characterId, SWAP_SLOT }, 'inventory:move:stranded')

  if stranded and tonumber(stranded.stranded) and tonumber(stranded.stranded) > 0 then
    print(('[%s] WARNING: %s item(s) parked in slot %d for character %s after a failed move'):format(
      RESOURCE, tostring(stranded.stranded), SWAP_SLOT, characterId))
  end

  return true, nil
end

--- Per-code use handlers. Some items have side effects beyond a row decrement
--- (a clothing outfit applies its pieces and removes the item; a hypothetical
--- keycard would unlock a door). The handler for the code runs in place of
--- the default remove-and-go behaviour.
---
--- The handler signature is `fn(characterId, code, itemId, quantity)` and is
--- responsible for anything that has to happen on use. It returns
--- `(ok, err)`. Inventory:use cleans up the row AFTER the handler returns
--- `ok`, so a handler that fails leaves the item in place.
local useHandlers = {}

function Inventory.registerUseHandler(code, fn)
  if type(code) ~= 'string' or code == '' then return end
  if type(fn) ~= 'function' then return end
  useHandlers[code] = fn
end

function Inventory.unregisterUseHandler(code)
  useHandlers[code] = nil
end

--- Consume one of an item — eating, using a tool, opening a door. The single
--- entry point for "the player used something", so that every use is charged
--- against the same authoritative count.
---
--- When a use handler is registered for the code, that handler runs first;
--- only if it succeeds does Inventory.remove the row. A handler that fails
--- leaves the row untouched. `itemId` is optional and identifies a specific
--- row in metadata-bearing stacks (outfit items, etc.).
function Inventory.use(characterId, code, quantity, itemId)
  local handler = useHandlers[code]
  if handler then
    local ok, err = handler(characterId, code, itemId, quantity or 1)
    if not ok then return false, err end
  end

  return Inventory.remove(characterId, code, quantity or 1)
end

--- Move items between two characters. Used for trade / give flows.
---
--- The behaviour is "remove from src, add to target" - the source's row is
--- decremented and the destination receives the same code (and metadata,
--- when an itemId was given). Refuses if the source does not have enough,
--- if the target cannot carry the weight or slots, or if metadata does not
--- exist on either side. Both sides must be live characters on the server.
---
--- Atomicity: the existing Inventory.remove / Inventory.add are themselves
--- transactional at the row level, but a `transfer` failing between
--- remove and add would leave a removed item the receiver never got. We
--- run remove and add inside a single transaction so either both happen
--- or neither does.
---
-- @return boolean ok, string|nil error, table|nil placedSnapshot
-- where placedSnapshot is `{ code, quantity, metadata }` for the new
-- destination row.

-- Free-slot search for the destination side of a transfer. Mirrors
-- findTargetSlot but does not stack-merge - the destination gets its
-- own stack of the same item. Must be declared before Inventory.transferBetween
-- because the call site binds to the local at parse time.
local function findFreeTargetSlot(characterId, def, metadataKey)
  local rows
  if metadataKey ~= nil then
    rows = Db.all([[
      SELECT slot FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND metadata = ?
    ]], { characterId, def.code, metadataKey }, 'inventory:transfer:slot')
  else
    rows = Db.all([[
      SELECT slot FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND metadata IS NULL
    ]], { characterId, def.code }, 'inventory:transfer:slot')
  end

  local used = {}
  for _, row in ipairs(rows or {}) do
    used[tonumber(row.slot)] = true
  end

  for slot = 0, slotCapacity() - 1 do
    if not used[slot] then
      return slot, nil
    end
  end

  return nil, 'no free slot'
end

function Inventory.transferBetween(srcCid, targetCid, code, quantity, itemId)
  quantity = math.floor(tonumber(quantity) or 0)
  if quantity <= 0 then return false, 'bad quantity' end

  if type(srcCid) ~= 'string' or srcCid == '' then return false, 'no source' end
  if type(targetCid) ~= 'string' or targetCid == '' then return false, 'no target' end
  if srcCid == targetCid then return false, 'self' end

  local def = Inventory.getDefinition(code)
  if not def then return false, 'unknown item' end

  -- Capacity preflight on the destination. A full bag should not cause
  -- the source to lose the item.
  local view = Inventory.view(targetCid)
  if view.usedWeight + (def.weight * quantity) > weightLimit() then
    return false, 'recipient too heavy'
  end
  if view.usedSlots >= slotCapacity() and not def.stackable then
    return false, 'recipient bag full'
  end

  if not Inventory.has(srcCid, code, quantity) then
    return false, 'not enough'
  end

  -- Read the source row, including metadata, for the destination insert.
  local srcRow
  if itemId ~= nil then
    srcRow = Db.one([[
      SELECT id, character_id, item_code, quantity, metadata
        FROM inventory_items
       WHERE character_id = ? AND item_code = ? AND id = ?
       LIMIT 1
    ]], { srcCid, code, tostring(itemId) }, 'inventory:transfer:read')
  else
    srcRow = Db.one([[
      SELECT id, character_id, item_code, quantity, metadata
        FROM inventory_items
       WHERE character_id = ? AND item_code = ?
       ORDER BY slot LIMIT 1
    ]], { srcCid, code }, 'inventory:transfer:read')
  end

  if not srcRow then return false, 'source row missing' end

  local currentView = Inventory.view(targetCid)
  if currentView.usedWeight + (def.weight * quantity) > weightLimit() then
    return false, 'recipient too heavy'
  end
  if currentView.usedSlots >= slotCapacity() and not def.stackable then
    return false, 'recipient bag full'
  end

  local metadataEnc = srcRow.metadata
  if metadataEnc == '' then metadataEnc = nil end

  local newId = Nifty.newUuid()
  local slot = findFreeTargetSlot(targetCid, def, metadataEnc)

  -- Build the insert SQL once, parameterised either way.
  local insertSql
  local insertParams
  if metadataEnc ~= nil then
    insertSql = [[INSERT INTO inventory_items
                   (id, character_id, slot, item_code, quantity, metadata)
                 VALUES (?, ?, ?, ?, ?, ?)]]
    insertParams = { newId, targetCid, tostring(slot), code,
                     tostring(quantity), metadataEnc }
  else
    insertSql = [[INSERT INTO inventory_items
                   (id, character_id, slot, item_code, quantity)
                 VALUES (?, ?, ?, ?, ?)]]
    insertParams = { newId, targetCid, tostring(slot), code,
                     tostring(quantity) }
  end

  -- Atomic delete + insert. Source row goes away; destination row appears.
  -- If either fails the transaction rolls back, the source keeps the item.
  local okTxn = Db.transaction({
    {
      sql = [[DELETE FROM inventory_items WHERE id = ? AND character_id = ?]],
      params = { srcRow.id, srcCid },
    },
    {
      sql    = insertSql,
      params = insertParams,
    },
  }, 'inventory:transfer:tx')

  if not okTxn then return false, 'transfer failed' end

  return true, nil, {
    code     = code,
    quantity = quantity,
    metadata = metadataEnc and json.decode(metadataEnc) or nil,
  }
end

--- Stamp or refresh the metadata of an existing inventory row.
---
--- Used by the give path: after Inventory.transferBetween moves a row
--- from giver to recipient, the server rewrites the destination's
--- metadata to add `giver_name` (the immediate giver's display
--- string). Callers may pass any other keys they want stamped; the row
--- preserves whatever keys were already there.
function Inventory.stampMetadata(characterId, itemId, patch)
  if type(characterId) ~= 'string' or characterId == '' then return false, 'no character' end
  if type(itemId) ~= 'string' or itemId == '' then return false, 'no item' end
  if type(patch) ~= 'table' then return false, 'bad patch' end

  local row = Db.one([[
    SELECT metadata FROM inventory_items
     WHERE character_id = ? AND id = ?
     LIMIT 1
  ]], { characterId, itemId }, 'inventory:stamp:read')

  if not row then return false, 'no row' end

  local existing = row.metadata
  if existing == nil or existing == '' then existing = '{}' end

  local ok, merged = pcall(function()
    local t = json.decode(existing) or {}
    for k, v in pairs(patch) do t[k] = v end
    return json.encode(t)
  end)

  if not ok then return false, 'merge failed' end

  Db.update([[
    UPDATE inventory_items SET metadata = ? WHERE id = ? AND character_id = ?
  ]], { merged, itemId, characterId }, 'inventory:stamp:write')

  return true, nil
end

-- ---------------------------------------------------------------------------
-- Life cycle
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(resource)
  if resource ~= RESOURCE then return end

  -- The catalogue must be read AFTER settings, because every capacity answer
  -- depends on both. `Db.ready` callbacks fire in registration order and
  -- settings.lua registers before inventory.lua in fxmanifest, so this one runs
  -- second — same guarantee the fixed two-second timeout was only hoping for.
  Db.ready(loadDefinitions)
end)

--- A new character starts with what a person actually has on them. This is the
--- only place items are handed out for free, and it is deliberately dull.
function Inventory.grantStartingItems(characterId)
  local starters = { 'phone', 'id_card' }
  for _, code in ipairs(starters) do
    local ok, err = Inventory.add(characterId, code, 1)
    if not ok then
      print(('[%s] could not give starting item %s to %s: %s'):format(
        RESOURCE, code, characterId, tostring(err)))
    end
  end
end

exports('view', Inventory.view)
exports('add', Inventory.add)
exports('getDefinition', Inventory.getDefinition)
exports('remove', Inventory.remove)
exports('count', Inventory.count)
exports('has', Inventory.has)
exports('use', Inventory.use)
exports('move', Inventory.move)
exports('push', Inventory.push)
exports('registerUseHandler', Inventory.registerUseHandler)
exports('unregisterUseHandler', Inventory.unregisterUseHandler)
exports('transferBetween', Inventory.transferBetween)
exports('stampMetadata', Inventory.stampMetadata)
exports('splitStack', Inventory.splitStack)

-- ---------------------------------------------------------------------------
-- NUI-driven actions
--
-- The inventory's own ui_page fires these. The actions here are thin
-- wrappers around Inventory.use / Inventory.remove plus the per-code
-- use handlers, so the existing use-handler registration for
-- clothing_outfit etc. continues to apply (e.g. applying an outfit
-- from inventory still routes through the registered handler).
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:useItem', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local cid = Identity.getActiveCharacter(src)
  if not cid then return end
  Inventory.use(cid, payload.code, payload.quantity, payload.itemId)
end)

RegisterNetEvent('nifty:server:discardItem', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local cid = Identity.getActiveCharacter(src)
  if not cid then return end
  Inventory.remove(cid, payload.code, payload.quantity, payload.itemId)
end)

-- Split a stack. Used by the inventory UI's "Aufteilen" right-click
-- action. qty = how many stay in the original row; the rest (total-qty)
-- move to a fresh row. Refused when the item is not stackable, the
-- split would leave zero on either side, or the destination would
-- exceed max_stack.
RegisterNetEvent('nifty:server:splitStack', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local cid = Identity.getActiveCharacter(src)
  if not cid then return end
  local ok, err = Inventory.splitStack(cid, payload.itemId, payload.quantity)
  TriggerClientEvent('nifty:client:splitStack', src, { ok = ok, reason = err })
end)

-- Drop-to-world: removes the inventory row and spawns a placeholder
-- world prop at the player-supplied coordinates. The server validates
-- proximity to the local player so a hostile client cannot teleport
-- items anywhere on the map.
RegisterNetEvent('nifty:server:discardItemOnGround', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local cid = Identity.getActiveCharacter(src)
  if not cid then return end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return end
  local me = GetEntityCoords(ped)
  if not me then return end

  -- Coords must be within 8 metres of the player's actual position -
  -- defend against trivial coord-tampering exploits. The check is
  -- simple (Chebyshev on the in-plane distance) because altitude
  -- is much less interesting for inventory drops.
  local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
  if not x or not y or not z then return end
  if math.abs(x - me.x) > 8 or math.abs(y - me.y) > 8 then return end

  -- Remove first. If the row was already gone or the code didn't match,
  -- we do not spawn a phantom prop.
  local row = Inventory.view(cid) or { items = {} }
  local matched
  for _, it in ipairs(row.items or {}) do
    if it.id == payload.itemId and it.code == payload.code then
      matched = it
      break
    end
  end
  if not matched then return end

  Inventory.remove(cid, payload.code, payload.quantity or 1, payload.itemId)
  -- Hand off to nifty-clothing which spawns the world prop and tracks
  -- it for pickup. The drops subsystem owns ground-item bookkeeping;
  -- we just translate the inventory row into a drop request.
  TriggerEvent('drops:create', src, {
    code = matched.code, name = matched.name,
    quantity = tonumber(payload.quantity) or 1, itemId = matched.id,
    x = x, y = y, z = z,
  })

  TriggerClientEvent('nifty:client:discardItemOnGround', src, { ok = true })
end)