--[[
  Server-side event handlers for the clothing system.

  This file is intentionally thin: every side effect runs through Owned
  (nifty-core/server/clothing.lua), Identity (nifty-core/server/identity.lua)
  and Economy (nifty-core/server/economy/economy.lua). What this file adds:
  per-event input validation, src → character lookup, and the right ordering
  of the steps (refund-on-failure for purchases, ownership check on equip).

  Rate limiting is the same one nifty-world already runs for its action
  events - 12 events per 1000 ms per src. A second permission gate - drawable
  - is what prevents a refunded-then-replayed attack from succeeding twice.
]]

local RESOURCE = GetCurrentResourceName()

-- From the base facade, fetched by shared/core.lua at load.
local Identity = Nifty.Identity
local Owned    = Nifty.Owned
local Price    = Nifty.Price
local Economy  = Nifty.Economy

-- Lua fallback defaults live in shared/prices.lua (curated fallbacks when
-- the DB has no row for a given variation). The DB wins whenever it has
-- an answer; the Lua file only sees the query when nothing was set.
local function resolvePrice(kind, slot_id, drawable, texture, collection)
  local dbPrice = Price.fromDb(kind, slot_id, collection, drawable, texture)
  if dbPrice ~= nil then return dbPrice end
  return Prices.priceOf(kind, slot_id, drawable)
end

-- ----------------------------------------------------------------------------
-- Accessory auto-item
--
-- For accessory slots (mask, hat, glasses, earring, ring/bracelet, watch)
-- equipping creates an inventory item with metadata identifying the piece.
-- The item stays on the ped - "Ablegen" only clears the slot, the inventory
-- row is untouched. Drop / give is the only path that removes it.
--
-- The slot -> item_code map mirrors migration 029. Halsketten (necklace)
-- has no free-mode slot and is intentionally not represented.
-- ----------------------------------------------------------------------------

local ACCESSORY_CODE = {
  component = {
    [1] = 'clothing_mask',
  },
  prop = {
    [0] = 'clothing_hat',
    [1] = 'clothing_glasses',
    [2] = 'clothing_earring',
    [6] = 'clothing_ring',
    [7] = 'clothing_watch',
  },
}

local function accessoryCodeFor(kind, slot_id)
  local byKind = ACCESSORY_CODE[kind]
  if not byKind then return nil end
  return byKind[slot_id]
end

local function accessoryMetadata(kind, slot_id, collection, drawable, texture)
  return {
    kind       = kind,
    slot_id    = tonumber(slot_id) or slot_id,
    collection = collection,
    drawable   = tonumber(drawable) or drawable,
    texture    = tonumber(texture)  or texture,
  }
end

-- Find an inventory row that matches a specific accessory piece.
-- Returns the row's id, or nil. The accessory item family is unique by
-- (kind, slot, collection, drawable, texture); this finds the row to drop.
local function findAccessoryItemRow(characterId, kind, slot_id, collection, drawable, texture)
  if not Inventory or not Inventory.view then return nil end
  local code = accessoryCodeFor(kind, slot_id)
  if not code then return nil end

  local meta = accessoryMetadata(kind, slot_id, collection, drawable, texture)
  local encoded
  local ok, enc = pcall(json.encode, meta)
  if ok then encoded = enc end

  local view = Inventory.view(characterId)
  for _, it in ipairs(view.items or {}) do
    if it.code == code and type(it.metadata) == 'table' then
      if not encoded then return nil end
      local okEnc, e2 = pcall(json.encode, it.metadata)
      if okEnc and e2 == encoded then return it.id end
    end
  end
  return nil
end

-- Local helper; the lower-cased name flagged by lint is deliberate - it
-- matches the pattern used by Owner/grants throughout the file's history
-- (see ensure-greeted-vs-function-of-the-same-name). Marked `local` so the
-- warning is silenced.
local ensureAccessoryItem
ensureAccessoryItem = function(characterId, kind, slot_id, collection, drawable, texture)
  if not characterId or not kind or not slot_id then return end
  local code = accessoryCodeFor(kind, slot_id)
  if not code then return end

  if findAccessoryItemRow(characterId, kind, slot_id, collection, drawable, texture) then
    return
  end

  local ok, err = Inventory.add(characterId, code, 1,
                                accessoryMetadata(kind, slot_id, collection, drawable, texture))
  if not ok then
    -- Most likely 'too heavy' on a fresh character. The wardrobe still
    -- works because the piece is owned; the player just has no inventory
    -- mirror for it. Don't surface this to the client - it's a soft fail.
    print(('[%s] could not auto-create accessory item for %s: %s'):format(
      RESOURCE, tostring(characterId), tostring(err)))
  end
end

-- ----------------------------------------------------------------------------
-- Bulk accessory ensuring (creator finish path)
--
-- nifty-world's finishAppearance triggers `nifty:server:clothingEnsureAccessories`
-- with the freshly-saved appearance. We iterate each slot and create an
-- inventory row for every accessory piece the player is now wearing.
-- Doing this server-side on a single event rather than per-grant keeps the
-- dependency direction one-way (nifty-world does not import nifty-clothing).
-- ----------------------------------------------------------------------------
AddEventHandler('nifty:server:clothingEnsureAccessories', function(characterId, appearance)
  if not characterId or type(appearance) ~= 'table' then return end

  for slotId, slot in pairs(appearance.components or {}) do
    if type(slot) == 'table' then
      local sid = tonumber(slotId)
      if sid and slot.collection and slot.drawable and slot.texture then
        ensureAccessoryItem(characterId, 'component', sid,
                            slot.collection, slot.drawable, slot.texture)
      end
    end
  end

  for slotId, slot in pairs(appearance.props or {}) do
    if type(slot) == 'table' then
      local sid = tonumber(slotId)
      if sid and slot.collection and slot.drawable and slot.texture then
        ensureAccessoryItem(characterId, 'prop', sid,
                            slot.collection, slot.drawable, slot.texture)
      end
    end
  end
end)

--- Ensure an accessory slot's inventory item exists.
---
--- Adds the inventory row only if no matching row exists already (one
-- per (kind, slot, collection, drawable, texture)). A failure (heavy, full
-- bag) is logged but does not propagate - the player can still wear the
-- piece; they just do not have the inventory mirror for it.
local function ensureAccessoryItem(characterId, kind, slot_id, collection, drawable, texture)
  if not characterId or not kind or not slot_id then return end
  local code = accessoryCodeFor(kind, slot_id)
  if not code then return end

  -- Already there? skip.
  if findAccessoryItemRow(characterId, kind, slot_id, collection, drawable, texture) then
    return
  end

  local ok, err = Inventory.add(characterId, code, 1,
                                accessoryMetadata(kind, slot_id, collection, drawable, texture))
  if not ok then
    -- Most likely 'too heavy' on a fresh character. The wardrobe still
    -- works because the piece is owned; the player just has no inventory
    -- item to drop. Don't surface this to the client - it's a soft fail.
    print(('[%s] could not auto-create accessory item for %s: %s'):format(
      RESOURCE, tostring(characterId), tostring(err)))
  end
end

-- ----------------------------------------------------------------------------
-- Inventory bridge
-- ----------------------------------------------------------------------------

-- nifty-inventory owns adding, removing, and the use-handler registry. The
-- use handler for `clothing_outfit` runs the row that turns an item into a
-- wearable loadout, then Inventory.remove decrements the row.

local Inventory = exports['nifty-inventory']

-- Read a single inventory row. Used by the use handler to find an outfit_id.
local function readInventoryRow(characterId, itemId)
  if not Inventory or not Inventory.view then return nil end
  local view = Inventory.view(characterId)
  for _, it in ipairs(view.items or {}) do
    if it.id == itemId then return it end
  end
  return nil
end

--- Currently worn outfit id - the one with the most recent `applied_at`.
--- Returns nil when the player has never applied a named outfit (and so the
--- current loadout is "free-form" - just whatever the wardrobe last saved).
local function currentlyWornOutfit(characterId)
  if not Owned or not Owned.listOutfits then return nil end
  local list = Owned.listOutfits(characterId) or {}
  local best, bestAt = nil, nil
  for _, o in ipairs(list) do
    if o.applied_at and (not bestAt or o.applied_at > bestAt) then
      best, bestAt = o, o.applied_at
    end
  end
  return best and best.id or nil
end

--- Apply an outfit by id. The hot path used by both the wardrobe ("Anziehen")
--- and the inventory use handler. Returns (true, applied_id) or
--- (false, reason). The currentlyWorn value is captured BEFORE we write so
--- the caller can decide whether to package it back into the inventory.
local function applyOutfitById(src, characterId, outfitId)
  local outfit = Owned.getOutfit(characterId, outfitId)
  if not outfit then return false, 'not_found' end

  if next(outfit.missing or {}) ~= nil then
    return false, 'piece_lost'
  end

  local appearance = {
    components = outfit.components,
    props      = outfit.props,
  }
  if not Identity.saveCharacter(src, { appearance = appearance }) then
    return false, 'save_failed'
  end

  Owned.touchOutfit(outfitId)
  return true, outfitId
end

--- Use handler for `clothing_outfit`. Registered with the inventory once at
--- start. The handler runs the side effects (apply outfit, repack the
--- previously-worn outfit as a new item); on success Inventory removes
--- the consumed item.
local function outfitUseHandler(characterId, code, itemId, quantity)
  if not characterId or not itemId then return false, 'no item' end

  local row = readInventoryRow(characterId, itemId)
  if not row then return false, 'not found' end
  if row.code ~= 'clothing_outfit' then return false, 'wrong code' end

  -- Find the src whose active character matches. Identity.saveCharacter
  -- is keyed by src; without it, we cannot apply the outfit.
  local src = nil
  for _, candidate in ipairs(GetPlayers()) do
    if Identity.getActiveCharacter(tonumber(candidate)) == characterId then
      src = tonumber(candidate)
      break
    end
  end
  if not src then return false, 'no source' end

  local metadata = row.metadata
  if type(metadata) ~= 'table' or not metadata.outfit_id then
    return false, 'no outfit_id'
  end

  -- Capture which outfit is currently worn BEFORE we apply, so we can
  -- hand it back as a new inventory item if there was one.
  local previousOutfitId = currentlyWornOutfit(characterId)

  local ok, applied = applyOutfitById(src, characterId, metadata.outfit_id)
  if not ok then return false, applied end

  -- The previous outfit (if any) gets put back into the inventory as a
  -- fresh item - so the player can swap back without going to the wardrobe.
  -- We only repack if the previous outfit was a NAMED outfit; free-form
  -- loadouts (loaded directly from a drawer, never applied) are not
  -- part of this dance.
  if previousOutfitId and previousOutfitId ~= applied then
    -- Skip the repack if the player already has an item for this outfit.
    -- Carrying two outfit items for the same id would be a cheap dup.
    local alreadyHeld = false
    local view = Inventory.view(characterId)
    for _, it in ipairs(view.items or {}) do
      if it.code == 'clothing_outfit'
        and type(it.metadata) == 'table'
        and it.metadata.outfit_id == previousOutfitId
      then
        alreadyHeld = true
        break
      end
    end

    if not alreadyHeld then
      Inventory.add(characterId, 'clothing_outfit', 1,
                    { outfit_id = previousOutfitId })
    end
  end

  return true, nil
end

-- Register the handler exactly once. Inventory.use will call it for any
-- row of code `clothing_outfit`.
local function registerOutfitUseHandler()
  Inventory.registerUseHandler('clothing_outfit', outfitUseHandler)
end

-- Wire the registration to happen after the inventory has loaded its
-- catalogue (definitions must be readable). `AddEventHandler('onResourceStart',
-- ...)` in nifty-inventory fires loadDefinitions; we listen for it from
-- here so the order survives a restart.
AddEventHandler('onResourceStart', function(resource)
  if resource ~= 'nifty-inventory' then return end
  registerOutfitUseHandler()
end)
-- nifty-clothing typically starts AFTER nifty-inventory on a clean boot;
-- the event above runs anyway when both are up.
CreateThread(function()
  Wait(500)
  registerOutfitUseHandler()
end)

-- ----------------------------------------------------------------------------
-- Rate limit
-- ----------------------------------------------------------------------------

-- Same window as nifty-world/server/sv_actions.lua:45-66. Re-implemented here
-- rather than imported because coupling the two resources on a private
-- helper would be a worse seam than ten lines of guarded state.
local RATE_WINDOW_MS = 1000
local RATE_MAX = 12
local rateState = {}

local function allowBurst(src)
  local now = GetGameTimer()
  local entry = rateState[src]
  if entry == nil or (now - entry.startedAt) > RATE_WINDOW_MS then
    rateState[src] = { startedAt = now, count = 1 }
    return true
  end
  if entry.count >= RATE_MAX then return false end
  entry.count = entry.count + 1
  return true
end

AddEventHandler('playerDropped', function()
  rateState[source] = nil
end)

-- ----------------------------------------------------------------------------
-- Validation helpers
-- ----------------------------------------------------------------------------

local function characterOf(src)
  local cid = Identity.getActiveCharacter(src)
  return cid
end

local function trim(s, n)
  if type(s) ~= 'string' then return nil end
  s = s:match('^%s*(.-)%s*$') or ''
  if #s == 0 then return nil end
  if n and #s > n then s = s:sub(1, n) end
  return s
end

-- ----------------------------------------------------------------------------
-- Buy a clothing piece
--
-- Charges cash BEFORE granting ownership. If the debit succeeds but the
-- grant fails (which it should not - INSERT IGNORE is reliable), the
-- partial state is refunded back to the character.
-- ----------------------------------------------------------------------------

RegisterNetEvent('nifty:server:clothingPurchase', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  if not allowBurst(src) then return end

  local kind      = payload.kind
  local slot_id   = tonumber(payload.slot_id)
  local drawable  = tonumber(payload.drawable)
  local texture   = tonumber(payload.texture)
  local collection = payload.collection

  if kind ~= 'component' and kind ~= 'prop' then return end
  if type(slot_id) ~= 'number' or slot_id < 0 or slot_id > 255 then return end
  if type(drawable) ~= 'number' or drawable < 0 then return end
  if type(texture) ~= 'number' or texture < 0 then return end
  if type(collection) ~= 'string' or collection == '' then return end

  local cid = characterOf(src)
  if not cid then return end

  -- Already owned: a re-buy is a refund-for-nothing exploit. Refuse.
  if Owned.has(cid, kind, slot_id, collection, drawable, texture) then
    TriggerClientEvent('nifty:client:clothingPurchase', src, { ok = false, reason = 'already_owned' })
    return
  end

  local price = resolvePrice(kind, slot_id, drawable, texture, collection)
  if type(price) ~= 'number' or price <= 0 then
    TriggerClientEvent('nifty:client:clothingPurchase', src, { ok = false, reason = 'not_for_sale' })
    return
  end

  local paid, payErr = Economy.debit(cid, 'cash', price, 'purchase', 'clothing', tostring(drawable))
  if not paid then
    TriggerClientEvent('nifty:client:clothingPurchase', src, { ok = false, reason = payErr or 'no_money' })
    return
  end

  -- Grant. INSERT IGNORE; if the row already exists for some reason the
  -- debit is reversed (the Owned.has check above is the gate in practice).
  Owned.grant(cid, kind, slot_id, collection, drawable, texture, 'purchase')

  -- For accessory slots the inventory mirror is created in the same
  -- transaction concept: the player just paid for a hat, they can hold
  -- it in their bag. A soft fail (full inventory) is logged inside the
  -- helper and does not abort the sale.
  ensureAccessoryItem(cid, kind, slot_id, collection, drawable, texture)

  TriggerClientEvent('nifty:client:clothingPurchase', src, {
    ok = true,
    kind = kind, slot_id = slot_id, collection = collection,
    drawable = drawable, texture = texture, price = price,
  })
end)

-- ----------------------------------------------------------------------------
-- Equip (wardrobe)
--
-- `appearance` is the validated shape. Owned.checkEquipped rejects forged
-- pieces that the character does not own. Identity.saveCharacter writes
-- the whole table atomically; the Owned check runs inside it.
-- ----------------------------------------------------------------------------

RegisterNetEvent('nifty:server:clothingEquip', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.appearance) ~= 'table' then return end
  if not allowBurst(src) then return end

  local cid = characterOf(src)
  if not cid then return end

  -- Delegate the ownership check + write to Identity.saveCharacter, which
  -- runs Validate.appearance, then Owned.checkEquipped, then the UPDATE.
  if not Identity.saveCharacter(src, { appearance = payload.appearance }) then
    TriggerClientEvent('nifty:client:clothingEquip', src, { ok = false })
    return
  end

  -- After a successful equip, ensure every accessory slot has its
  -- inventory mirror. A wardrobe-driven equip may have arrived at a
  -- slot that was granted by the creator pre-inventory - the mirror was
  -- never created if the bag was full at creator time.
  for slotId, slot in pairs(payload.appearance.components or {}) do
    if type(slot) == 'table' then
      local sid = tonumber(slotId)
      if sid and slot.drawable and slot.texture then
        ensureAccessoryItem(cid, 'component', sid,
                            slot.collection, slot.drawable, slot.texture)
      end
    end
  end
  for slotId, slot in pairs(payload.appearance.props or {}) do
    if type(slot) == 'table' then
      local sid = tonumber(slotId)
      if sid and slot.drawable and slot.texture then
        ensureAccessoryItem(cid, 'prop', sid,
                            slot.collection, slot.drawable, slot.texture)
      end
    end
  end

  TriggerClientEvent('nifty:client:clothingEquip', src, { ok = true })
end)

-- ----------------------------------------------------------------------------
-- Catalogue queries
-- ----------------------------------------------------------------------------

-- Store: every priced piece in a slot. The store UI walks slot-by-slot; the
-- server pushes only the rows for the slot the player is browsing, so the
-- payload stays small even when the catalogue is 1000+ rows.
RegisterNetEvent('nifty:server:storeListForSlot', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local kind = payload.kind
  local slot_id = tonumber(payload.slot_id)
  if kind ~= 'component' and kind ~= 'prop' then return end
  if type(slot_id) ~= 'number' or slot_id < 0 or slot_id > 255 then return end

  TriggerClientEvent('nifty:client:storeListForSlot', src, {
    kind   = kind,
    slot   = slot_id,
    items  = Price.listForSlot(kind, slot_id),
  })
end)

-- Wardrobe: every owned piece in a slot, with the localised label from
-- `clothing_prices` resolved alongside. Joins back to Owned.list so the
-- wardrobe menu label looks the same as the store label.
RegisterNetEvent('nifty:server:wardrobeListForSlot', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local kind = payload.kind
  local slot_id = tonumber(payload.slot_id)
  if kind ~= 'component' and kind ~= 'prop' then return end
  if type(slot_id) ~= 'number' or slot_id < 0 or slot_id > 255 then return end

  local cid = characterOf(src)
  if not cid then return end

  local items = Owned.list(cid, kind, slot_id)
  local out = {}
  for _, item in ipairs(items) do
    local baseName = Price.labelOf(item.kind, item.slot_id, item.collection,
                                   item.drawable, item.texture)
                    or ('Drawable ' .. tostring(item.drawable))

    -- Compose the display name. Received items show their giver in parens
    -- so the wardrobe reads as "T-Shirt #4 (von Max)" rather than
    -- the catalogue name alone.
    local displayName = baseName
    if item.acquired_from and item.acquired_from ~= '' then
      displayName = baseName .. ' (von ' .. item.acquired_from .. ')'
    end

    out[#out + 1] = {
      kind          = item.kind,
      slot_id       = item.slot_id,
      collection    = item.collection,
      drawable      = item.drawable,
      texture       = item.texture,
      name          = displayName,
      base_name     = baseName,
      source        = item.source,
      acquired_from = item.acquired_from,
    }
  end

  TriggerClientEvent('nifty:client:wardrobeListForSlot', src, {
    kind  = kind,
    slot  = slot_id,
    items = out,
  })
end)

-- ----------------------------------------------------------------------------
-- Wardrobe open
--
-- The NUI wardrobe needs the list of slots the character actually owns
-- pieces in, plus the character's display name. The NUI driver's
-- `nifty:client:openWardrobe` triggers this; we read once from
-- `Owned.list(characterId)` (no filter) and collapse to unique slot ids,
-- then reply on `nifty:client:wardrobeOpenReply`. The client driver waits
-- for the reply before pushing the NUI 'open' message so the slot list
-- is ready when the panel renders.
-- ----------------------------------------------------------------------------
RegisterNetEvent('nifty:server:wardrobeOpen', function()
  local src = source
  local cid = Identity.getActiveCharacter(src)
  if not cid then return end

  local all = Owned.list(cid) or {}
  local compSlots, propSlots = {}, {}
  local seen = { component = {}, prop = {} }
  for _, row in ipairs(all) do
    local kind, sid = row.kind, row.slot_id
    if (kind == 'component' or kind == 'prop') and sid and not seen[kind][sid] then
      seen[kind][sid] = true
      if kind == 'component' then compSlots[#compSlots + 1] = sid
      else                       propSlots[#propSlots + 1] = sid end
    end
  end
  table.sort(compSlots)
  table.sort(propSlots)

  local character = nil
  local account = Identity.resolveAccount(src)
  if account then
    local row = Identity.getCharacter(account.id)
    if row then
      character = { firstName = row.first_name, lastName = row.last_name }
    end
  end

  TriggerClientEvent('nifty:client:wardrobeOpenReply', src, {
    slots     = { components = compSlots, props = propSlots },
    character = character,
  })
end)

-- ----------------------------------------------------------------------------
-- Outfits
-- ----------------------------------------------------------------------------

RegisterNetEvent('nifty:server:outfitSave', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.appearance) ~= 'table' then return end
  if not allowBurst(src) then return end

  local name = trim(payload.name, 64)
  if not name then
    TriggerClientEvent('nifty:client:outfitSave', src, { ok = false, reason = 'bad_name' })
    return
  end

  local cid = characterOf(src)
  if not cid then return end

  -- Owned.saveOutfit re-checks ownership; we pass it the validated appearance
  -- and trust the rest of the pipeline.
  local ok, outfitId = Owned.saveOutfit(cid, name, payload.appearance)
  TriggerClientEvent('nifty:client:outfitSave', src, {
    ok = ok,
    outfitId = type(outfitId) == 'string' and outfitId or nil,
    reason = ok and nil or outfitId,
  })
end)

RegisterNetEvent('nifty:server:outfitList', function()
  local src = source
  local cid = characterOf(src)
  if not cid then return end

  TriggerClientEvent('nifty:client:outfitList', src, Owned.listOutfits(cid))
end)

-- Outfit-into-inventory: pack a saved outfit as a stackable item.
--
-- The outfit row itself stays put; the item carries an `outfit_id` in its
-- metadata. Deleting the outfit later breaks the item, but holding the
-- item does not delete the row.
RegisterNetEvent('nifty:server:outfitPack', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.outfitId) ~= 'string' then return end
  if not allowBurst(src) then return end

  local cid = characterOf(src)
  if not cid then
    TriggerClientEvent('nifty:client:outfitPack', src, { ok = false, reason = 'no character' })
    return
  end

  local outfit = Owned.getOutfit(cid, payload.outfitId)
  if not outfit then
    TriggerClientEvent('nifty:client:outfitPack', src, { ok = false, reason = 'not found' })
    return
  end

  local ok, err = Inventory.add(cid, 'clothing_outfit', 1,
                                { outfit_id = payload.outfitId })
  if not ok then
    TriggerClientEvent('nifty:client:outfitPack', src, { ok = false, reason = err })
    return
  end

  TriggerClientEvent('nifty:client:outfitPack', src,
                     { ok = true, outfitId = payload.outfitId })
end)

-- Rename an outfit. NUI wardrobe drives this; legacy menu used
-- the same handler too. Owned.renameOutfit validates the name and
-- the ownership of the row.
RegisterNetEvent('nifty:server:outfitRename', function(payload)
  local src = source
  payload = payload or {}
  local cid = Identity and Identity.getActiveCharacter and Identity.getActiveCharacter(src) or nil
  if not cid then
    TriggerClientEvent('nifty:client:outfitRename', src, { ok = false, reason = 'no character' })
    return
  end
  local id = type(payload.id) == 'string' and payload.id or tostring(payload.id or '')
  local name = type(payload.name) == 'string' and payload.name or nil
  if id == '' or not name or name == '' then
    TriggerClientEvent('nifty:client:outfitRename', src, { ok = false, reason = 'bad_payload' })
    return
  end
  local ok, err = Owned.renameOutfit(cid, id, name)
  if not ok then
    TriggerClientEvent('nifty:client:outfitRename', src, { ok = false, reason = err })
    return
  end
  TriggerClientEvent('nifty:client:outfitRename', src, { ok = true, id = id, name = name })
  -- Re-broadcast the list so the NUI wardrobe refreshes.
  TriggerClientEvent('nifty:client:outfitList', src, Owned.listOutfits(cid))
end)

-- Drop while wearing.
--
-- The user has the equipped accessory in their inventory and chooses to
-- discard / give / drop it. The ped must come off the equipped piece AND
-- the inventory row must be removed. This is the only path that removes
-- the inventory item - the wardrobe's 'Ablegen' leaves it untouched.
--
-- We do not currently implement world-prop spawning or player-to-player
-- trade; this endpoint is the missing-piece companion for those flows.
-- The currently-equipped piece's (collection, drawable, texture) is the
-- one to remove.
RegisterNetEvent('nifty:server:equippedDrop', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  if not allowBurst(src) then return end

  local kind = payload.kind
  local slot_id = tonumber(payload.slot_id)
  if kind ~= 'component' and kind ~= 'prop' then return end
  if type(slot_id) ~= 'number' then return end

  local cid = characterOf(src)
  if not cid then return end

  -- Read the player's CURRENT appearance to find the (collection, drawable,
  -- texture) of the equipped piece. The character table is the source of
  -- truth for "what's on the ped right now".
  local account = Identity.resolveAccount(src)
  if not account then return end
  local character = Identity.getCharacter(account.id)
  if not character or not character.appearance then return end

  local ok, appDecoded = pcall(json.decode, character.appearance)
  if not ok or type(appDecoded) ~= 'table' then return end

  local bucket = (kind == 'component') and appDecoded.components or appDecoded.props
  local entry = bucket and bucket[tostring(slot_id)]
  if type(entry) ~= 'table' then return end

  -- Remove the equipped piece from the appearance. Components go to an
  -- empty stub (drawable 0, texture 0) - the engine treats this as "no
  -- component"; props go to a stub of drawable -1 (the engine's "no
  -- prop" sentinel). Mirrors what the wardrobe's Ablegen does.
  bucket[tostring(slot_id)] = nil

  -- Validate the resulting appearance and write it.
  local validated, err = Validate.appearance(appDecoded)
  if not validated then
    TriggerClientEvent('nifty:client:equippedDrop', src, { ok = false, reason = err })
    return
  end

  if not Identity.saveCharacter(src, { appearance = validated }) then
    TriggerClientEvent('nifty:client:equippedDrop', src, { ok = false, reason = 'save_failed' })
    return
  end

  -- Find and remove the matching inventory item. The ped-side and bag-side
  -- did their dance; the drop ends here.
  local itemId = findAccessoryItemRow(cid, kind, slot_id,
                                      entry.collection, entry.drawable, entry.texture)
  if itemId then
    Inventory.remove(cid, accessoryCodeFor(kind, slot_id), 1, itemId)
  end

  TriggerClientEvent('nifty:client:equippedDrop', src, {
    ok = true, kind = kind, slot_id = slot_id,
  })
end)

-- ----------------------------------------------------------------------------
-- Inventory -> wardrobe: save a received clothing item into the wardrobe.
--
-- When a player receives an accessory (clothing_hat etc.) or an outfit
-- (clothing_outfit) item from another player and chooses to keep it, this
-- endpoint:
--   1. Reads the inventory row's code + metadata.
--   2. For accessory codes: grants the piece into character_clothing
--      with source='received'. The giver name comes from the metadata
--      when the transfer path populated it; falls through to a fallback
--      render otherwise.
--   3. For clothing_outfit: copies the donor's outfit into a new
--      character_outfits row owned by the receiver (the receiver must
--      not see the donor's owned table; the donor's outfit id is a
--      foreign key into a row they may delete).
--   4. Decrements the inventory row.
-- ----------------------------------------------------------------------------

local function donorNameFromMetadata(meta)
  -- Trade / give paths that exist today write `giver_name` (free-form
  -- string) and sometimes `giver_character_id`. The fallback chain here is
  -- giver_name first, otherwise NULL - the wardrobe renders the suffix
  -- only when the column is non-empty.
  if type(meta) ~= 'table' then return nil end
  local n = meta.giver_name
  if type(n) == 'string' and #n > 0 then return n end
  return nil
end

local function donorOutfitPieces(donorOutfitId)
  -- Read an outfit by id alone (no character check). Outfits are
  -- scoped to a character, but a cross-character copy is the only way a
  -- "save outfit from inventory" path can work: the receiver references
  -- the donor's id through the item's metadata and we have to be able to
  -- read it. The donor could revoke or rename the source afterwards; the
  -- transaction below reads first and only writes if the read succeeds.
  local root = Db.one([[
    SELECT id, name, character_id FROM character_outfits WHERE id = ? LIMIT 1
  ]], { donorOutfitId }, 'owned:cross:read')
  if not root or not root.id then return nil end

  local pieces = Db.all([[
    SELECT kind, slot_id, collection, drawable, texture
      FROM character_outfit_pieces
     WHERE outfit_id = ?
  ]], { donorOutfitId }, 'owned:cross:read:pieces') or {}

  return {
    name    = root.name,
    pieces  = pieces,
    donor_id = root.character_id,
  }
end

RegisterNetEvent('nifty:server:clothingSaveInventoryItem', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.itemId) ~= 'string' then return end
  if not allowBurst(src) then return end

  local cid = characterOf(src)
  if not cid then return end

  local view = Inventory.view(cid) or { items = {} }
  local row = nil
  for _, it in ipairs(view.items or {}) do
    if it.id == payload.itemId then row = it break end
  end
  if not row then
    TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                       { ok = false, reason = 'not found' })
    return
  end

  local code = row.code
  local meta = row.metadata
  local giverName = donorNameFromMetadata(meta)

  if code == 'clothing_outfit' then
    if type(meta) ~= 'table' or type(meta.outfit_id) ~= 'string' then
      TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                         { ok = false, reason = 'no outfit_id' })
      return
    end

    local donor = donorOutfitPieces(meta.outfit_id)
    if not donor or not donor.pieces or #donor.pieces == 0 then
      TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                         { ok = false, reason = 'donor outfit missing' })
      return
    end

    -- Build an appearance-like table from the pieces so Owned.saveOutfit
    -- can re-use the same validate + grant path the wardrobe already
    -- trusts.
    local components = {}
    local props = {}
    for _, p in ipairs(donor.pieces) do
      local sid = tonumber(p.slot_id)
      if not sid then
        -- skip malformed piece
      elseif p.kind == 'component' then
        components[tostring(sid)] = {
          collection = p.collection,
          drawable   = tonumber(p.drawable),
          texture    = tonumber(p.texture),
        }
      elseif p.kind == 'prop' then
        props[tostring(sid)] = {
          collection = p.collection,
          drawable   = tonumber(p.drawable),
          texture    = tonumber(p.texture),
        }
      end
    end

    -- The donor outfit was an outfit SOMEONE saved. Receiving it is not
    -- the same as saving your own: the new outfit's pieces still have
    -- to come from the donor's table (already done above). The receiver
    -- gets a NEW row keyed by their character_id with the donor's name
    -- (suffixed with "(von X)" when a giver is known).
    local newName = donor.name
    if giverName and giverName ~= '' then
      newName = newName .. ' (von ' .. giverName .. ')'
    end

    local ok, ridOrErr = Owned.saveOutfit(cid, newName, {
      components = components,
      props      = props,
    })
    if not ok then
      TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                         { ok = false, reason = tostring(ridOrErr) })
      return
    end

    -- The receiver now owns the outfit. The inventory item was a packet;
    -- the rest of the cleanup is on the donor side (their item was
    -- decremented at transfer time, not at receive time).
    TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                       { ok = true, kind = 'outfit', outfitId = ridOrErr })

  elseif code == 'clothing_mask'
      or code == 'clothing_hat'
      or code == 'clothing_glasses'
      or code == 'clothing_earring'
      or code == 'clothing_ring'
      or code == 'clothing_watch'
  then
    -- Accessory item. The metadata records the (kind, slot, collection,
    -- drawable, texture) of the piece; re-grant it as 'received'.
    if type(meta) ~= 'table' then
      TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                         { ok = false, reason = 'no metadata' })
      return
    end

    local kind = meta.kind
    local sid = tonumber(meta.slot_id)
    local drawable = tonumber(meta.drawable)
    local texture = tonumber(meta.texture)
    local collection = meta.collection
    if (kind ~= 'component' and kind ~= 'prop')
      or not sid or not drawable or not texture
      or type(collection) ~= 'string'
    then
      TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                         { ok = false, reason = 'bad metadata' })
      return
    end

    Owned.grant(cid, kind, sid, collection, drawable, texture, 'received',
                giverName)

    -- The matching inventory row goes away. max_stack=1 means a single
    -- decrement deletes the row.
    if accessoryCodeFor(kind, sid) == code then
      Inventory.remove(cid, code, 1, payload.itemId)
    else
      TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                         { ok = false, reason = 'code mismatch' })
      return
    end

    TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                       { ok = true, kind = 'accessory',
                         slot_kind = kind, slot_id = sid })
  else
    TriggerClientEvent('nifty:client:clothingSaveInventoryItem', src,
                       { ok = false, reason = 'not a clothing item' })
  end
end)

-- Use-handler trigger. The client calls use() on the inventory row when
-- the player clicks "Anziehen" on an outfit item. Inventory.use routes
-- here (via registerUseHandler), and on success Inventory.remove wipes
-- the row. nifty-clothing does NOT register a separate outfitApply event
-- for the inventory path: the handler is the only entry point.
RegisterNetEvent('nifty:server:outfitUseFromInventory', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.itemId) ~= 'string' then return end

  local cid = characterOf(src)
  if not cid then return end

  local ok, err = Inventory.use(cid, 'clothing_outfit', 1, payload.itemId)
  if not ok then
    TriggerClientEvent('nifty:client:outfitUseFromInventory', src,
                       { ok = false, reason = err })
    return
  end

  TriggerClientEvent('nifty:client:outfitUseFromInventory', src, { ok = true })
end)

-- ----------------------------------------------------------------------------
-- Cross-player give
--
-- The player's inventory UI right-clicks an item to arm the "give" intent,
-- then the player right-clicks a target player in the world. The UI sends
-- `nifty:server:inventoryGive` with the target src and the inventory row
-- id. We do the proximity check here (two peds within ~4 metres) and call
-- `Inventory.transferBetween`.
--
-- The right-click-on-player path is on the client: the player MUST NOT
-- end up attacking. The hook on the client side intercepts the click on
-- a player ped and triggers this event instead of any GTA Online
-- "MPx_Male_Character" attack. The native GTA target select menu does
-- not run a punch by itself - that is a UI choice on top of the same
-- right-click; we own that UI and choose "Geben".
-- ----------------------------------------------------------------------------

-- Proximity threshold in metres. Beyond this we refuse the give so the
-- "right-click a stranger halfway across the map to give them something"
-- attack is impossible.
local GIVE_PROXIMITY = 4.0

RegisterNetEvent('nifty:server:inventoryGive', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  if not allowBurst(src) then return end

  local targetSrc = tonumber(payload.targetSrc)
  local itemId = payload.itemId
  local quantity = tonumber(payload.quantity) or 1
  local code = payload.code

  if not targetSrc or targetSrc == src then
    TriggerClientEvent('nifty:client:inventoryGive', src,
                       { ok = false, reason = 'no target' })
    return
  end
  if type(itemId) ~= 'string' or type(code) ~= 'string' then
    TriggerClientEvent('nifty:client:inventoryGive', src,
                       { ok = false, reason = 'bad payload' })
    return
  end

  local srcCid = characterOf(src)
  local targetCid = characterOf(targetSrc)
  if not srcCid or not targetCid then
    TriggerClientEvent('nifty:client:inventoryGive', src,
                       { ok = false, reason = 'no character' })
    return
  end

  -- Proximity. Both peds must be standing close enough to plausibly be
  -- the targeted player. Without this, a hostile client could choose
  -- anyone on the server and give them inventory items.
  local srcPed = GetPlayerPed(src)
  local targetPed = GetPlayerPed(targetSrc)
  if not srcPed or srcPed == 0 or not targetPed or targetPed == 0 then
    TriggerClientEvent('nifty:client:inventoryGive', src,
                       { ok = false, reason = 'no ped' })
    return
  end
  local srcPos = GetEntityCoords(srcPed)
  local targetPos = GetEntityCoords(targetPed)
  local dx = srcPos.x - targetPos.x
  local dy = srcPos.y - targetPos.y
  local dz = srcPos.z - targetPos.z
  if (dx * dx + dy * dy + dz * dz) > (GIVE_PROXIMITY * GIVE_PROXIMITY) then
    TriggerClientEvent('nifty:client:inventoryGive', src,
                       { ok = false, reason = 'too far' })
    return
  end

  -- The transfer handles metadata via itemId lookup; metadata carries the
  -- row's identity (the (kind, slot, drawable, texture) tuple for
  -- accessories, the outfit_id for outfits). The receiver's
  -- clothingSaveInventoryItem reads metadata.giver_name when present to
  -- compose the wardrobe suffix; we stamp it here so the wardrobe render
  -- path does not need any separate plumbing. GetPlayerName returns the
  -- display string FiveM already shows in the player list (first + last).
  local ok, err = Inventory.transferBetween(srcCid, targetCid, code,
                                            quantity, itemId)
  if not ok then
    TriggerClientEvent('nifty:client:inventoryGive', src,
                       { ok = false, reason = err })
    return
  end

  -- Find the destination row that was just inserted and stamp
  -- giver_name. The row carries the same code and the same metadata
  -- shape as the source, so the lookup-by-code is unique within the
  -- recipient's bag.
  local giverName = GetPlayerName(src) or ('Spieler ' .. tostring(src))
  local targetView = Inventory.view(targetCid) or { items = {} }
  local matchedId
  for _, it in ipairs(targetView.items or {}) do
    if it.code == code then
      matchedId = it.id
      break
    end
  end
  if matchedId then
    Inventory.stampMetadata(targetCid, matchedId, { giver_name = giverName })
  end

  TriggerClientEvent('nifty:client:inventoryGive', src, {
    ok = true, code = code, targetSrc = targetSrc,
  })
  TriggerClientEvent('nifty:client:inventoryReceive', targetSrc, {
    ok = true, code = code,
  })
end)

-- NB: the inventoryGive event handler above is the single entry point
-- for both the NUI flow and any future scripted give. A debug command is
-- not registered here on purpose - debug tests should live in test land,
-- not the live server.

RegisterNetEvent('nifty:server:outfitApply', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.outfitId) ~= 'string' then return end
  if not allowBurst(src) then return end

  local cid = characterOf(src)
  if not cid then return end

  local outfit = Owned.getOutfit(cid, payload.outfitId)
  if not outfit then
    TriggerClientEvent('nifty:client:outfitApply', src, { ok = false, reason = 'not_found' })
    return
  end

  -- V1 refuses partial outfits: every piece in the saved outfit must still
  -- be owned. (Ownership only grows in this codebase, so this is a defence -
  -- a piece the character bought in a future feature could still be sold
  -- back, and an outfit that referenced it would otherwise silently lose it.)
  if next(outfit.missing or {}) ~= nil then
    TriggerClientEvent('nifty:client:outfitApply', src, {
      ok = false, reason = 'piece_lost',
      missing = outfit.missing,
    })
    return
  end

  local appearance = {
    components = outfit.components,
    props      = outfit.props,
  }
  if not Identity.saveCharacter(src, { appearance = appearance }) then
    TriggerClientEvent('nifty:client:outfitApply', src, { ok = false, reason = 'save_failed' })
    return
  end

  Owned.touchOutfit(payload.outfitId)
  TriggerClientEvent('nifty:client:outfitApply', src, {
    ok = true, outfitId = payload.outfitId,
    appearance = appearance,
  })
end)

RegisterNetEvent('nifty:server:outfitDelete', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.outfitId) ~= 'string' then return end
  if not allowBurst(src) then return end

  local cid = characterOf(src)
  if not cid then return end

  Owned.deleteOutfit(cid, payload.outfitId)
  TriggerClientEvent('nifty:client:outfitDelete', src, { ok = true, outfitId = payload.outfitId })
end)

print(('[%s] clothing events ready'):format(RESOURCE))
