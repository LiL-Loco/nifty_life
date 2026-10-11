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

--- Item weights are DECIMAL money values, so rounding belongs to the economy system.
--- Reached by export, not through the facade: the facade carries data access,
--- not behaviour.
local Economy = exports['nifty-economy']

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
local function findTargetSlot(characterId, def, quantity)
  local rows = Db.all([[
    SELECT slot, quantity FROM inventory_items WHERE character_id = ?
  ]], { characterId }, 'inventory:slots')

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
--- @return boolean ok, string|nil error
function Inventory.add(characterId, code, quantity)
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

  local view = Inventory.view(characterId)

  if view.usedWeight + (def.weight * quantity) > weightLimit() then
    return false, 'too heavy'
  end

  local slot, err, existing = findTargetSlot(characterId, def, quantity)
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
    statements = { {
      sql = [[INSERT INTO inventory_items (id, character_id, slot, item_code, quantity)
              VALUES (?, ?, ?, ?, ?)]],
      params = { Nifty.newUuid(), characterId, slot, def.code, quantity },
    } }
  end

  if not Db.transaction(statements, 'inventory:add') then
    return false, 'could not store item'
  end

  return true, nil
end

-- ---------------------------------------------------------------------------
-- Removing
-- ---------------------------------------------------------------------------

--- Take items away. Consumes from stacks in slot order, which keeps the result
--- deterministic — two removals of the same quantity always leave the same
--- inventory, so a bug reproduces instead of varying.
function Inventory.remove(characterId, code, quantity)
  quantity = math.floor(tonumber(quantity) or 0)
  if quantity <= 0 then return false, 'bad quantity' end

  local def = Inventory.getDefinition(code)
  if not def then return false, 'unknown item' end

  local rows = Db.all([[
    SELECT id, slot, quantity FROM inventory_items
     WHERE character_id = ? AND item_code = ?
     ORDER BY slot
  ]], { characterId, def.code }, 'inventory:remove:candidates')

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

--- Consume one of an item — eating, using a tool, opening a door. The single
--- entry point for "the player used something", so that every use is charged
--- against the same authoritative count.
function Inventory.use(characterId, code, quantity)
  local ok, err = Inventory.remove(characterId, code, quantity or 1)
  return ok, err
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
exports('remove', Inventory.remove)
exports('count', Inventory.count)
exports('has', Inventory.has)
exports('use', Inventory.use)
exports('move', Inventory.move)
exports('push', Inventory.push)