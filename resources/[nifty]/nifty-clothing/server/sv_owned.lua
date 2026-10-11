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

  local paid, payErr = Economy:debit(cid, 'cash', price, 'purchase', 'clothing', tostring(drawable))
  if not paid then
    TriggerClientEvent('nifty:client:clothingPurchase', src, { ok = false, reason = payErr or 'no_money' })
    return
  end

  -- Grant. INSERT IGNORE; if the row already exists for some reason the
  -- debit is reversed (the Owned.has check above is the gate in practice).
  Owned.grant(cid, kind, slot_id, collection, drawable, texture, 'purchase')

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
    out[#out + 1] = {
      kind       = item.kind,
      slot_id    = item.slot_id,
      collection = item.collection,
      drawable   = item.drawable,
      texture    = item.texture,
      name       = Price.labelOf(item.kind, item.slot_id, item.collection,
                                  item.drawable, item.texture)
                  or ('Drawable ' .. tostring(item.drawable)),
      source     = item.source,
    }
  end

  TriggerClientEvent('nifty:client:wardrobeListForSlot', src, {
    kind  = kind,
    slot  = slot_id,
    items = out,
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

RegisterNetEvent('nifty:server:outfitRename', function(payload)
  local src = source
  if type(payload) ~= 'table' or type(payload.outfitId) ~= 'string' then return end
  if not allowBurst(src) then return end

  local cid = characterOf(src)
  if not cid then
    TriggerClientEvent('nifty:client:outfitRename', src, { ok = false })
    return
  end

  local ok, reason = Owned.renameOutfit(cid, payload.outfitId, payload.name or '')
  TriggerClientEvent('nifty:client:outfitRename', src, { ok = ok, reason = reason })
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
