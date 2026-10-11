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
