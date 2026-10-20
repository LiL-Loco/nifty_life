-- nifty-clothing NUI driver — wardrobe + store.
-- The NUI page hosts two UIs (wardrobe and store); each opens through
-- a different event and the NUI's `mode` field tells the JS which
-- surface to render. The JS files (wardrobe.js, store.js) each
-- listen to the same window.message stream and decide based on
-- `action` what to do.
--
-- This file is a thin adapter: it acquires focus, opens the page,
-- dispatches every NUI callback to a server event, and pipes
-- the relevant server replies back to the NUI.

local RESOURCE = GetCurrentResourceName()

-- ---------------------------------------------------------------- focus
-- NUI focus, owned entirely by this resource. Nothing about it is shared.
--
-- `SetNuiFocus` only does anything when the CALLING resource declares a
-- `ui_page`, because it acts on that resource's own CEF. This one declares one.
-- The focus broker in nifty-core could therefore never hand the keyboard over,
-- whatever it reported: it has no ui_page on purpose, so every native call it
-- issued was a silent no-op — it logged `granted`, returned true, and the player
-- got no cursor while every click punched their character through a wall.
--
-- WHAT IS GIVEN UP, STATED PLAINLY: with no shared broker nobody can ask "who
-- holds the keyboard right now?", so two surfaces that can be open at once are
-- arbitrated by whoever opened last. ox_inventory lives with the identical
-- constraint and papers over it with `Wait(100)` and a hopeful comment.
--
-- `SetNuiFocusKeepInput(false)` is not decoration: ox_target raises that flag
-- globally on every target interaction and never lowers it
-- (ox_target/client/state.lua), so without it a click on an open panel also
-- reaches the game and moves the character.
local focusHeld = false

--- Take the keyboard and show the cursor.
local function acquireFocus()
  if focusHeld then return end

  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  focusHeld = true
end

--- Hand it back. Safe to call when we never had it.
local function releaseFocus()
  if not focusHeld then return false end

  focusHeld = false
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  return true
end

-- Stopping with the keyboard held strands a captured cursor with no way out but a
-- reconnect, so the stop path has to release it. This handler cannot be inherited
-- from anywhere: every resource that can hold focus needs its own.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end

  releaseFocus()
end)

AddEventHandler('playerDropped', function()
  focusHeld = false
end)


local function sendOpen(mode, extra)
  acquireFocus()
  SendNUIMessage({ action = 'clothing:open', data = { mode = mode, extra = extra or {} } })
end

local function sendClose()
  SendNUIMessage({ action = 'clothing:close' })
  releaseFocus()
end

-- ---------------------------------------------------------------- NUI callbacks

RegisterNUICallback('closePanel', function(_, cb)
  sendClose()
  cb({ ok = true })
end)

-- Wardrobe
local function onOwnedPieces(reply)
  if reply and reply.kind and reply.slot then
    RemoveEventHandler(onOwnedPieces)
    SendNUIMessage({
      action = 'clothing:refresh',
      data    = { owned = { [reply.kind] = { [reply.slot] = reply.items or {} } } },
    })
  end
end
RegisterNUICallback('getOwnedForSlot', function(data, cb)
  if data and data.kind and data.id then
    RegisterNetEvent('nifty:client:wardrobeListForSlot', onOwnedPieces)
    TriggerServerEvent('nifty:server:wardrobeListForSlot', {
      kind = data.kind, slot = tonumber(data.id),
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('unequip', function(data, cb)
  if data and data.kind and data.id then
    TriggerServerEvent('nifty:server:clothingUnequip', {
      kind = data.kind, slot = tonumber(data.id),
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('equip', function(data, cb)
  if data and data.kind and data.id and data.pieceId then
    TriggerServerEvent('nifty:server:clothingEquip', {
      kind = data.kind, slot = tonumber(data.id), pieceId = tonumber(data.pieceId),
    })
  end
  cb({ ok = true })
end)

-- Long-lived listener so the wardrobe refreshes when an outfit
-- is renamed or deleted (the server re-broadcasts the list).
RegisterNetEvent('nifty:client:outfitList', function(list)
  SendNUIMessage({ action = 'clothing:refresh', data = { outfits = list or {} } })
end)

-- One-shot listener used by getOutfits so the JS can flip screens
-- without a re-fetch. Removed on first reply.
local function onOutfitListFetch(list)
  RemoveEventHandler(onOutfitListFetch)
  SendNUIMessage({ action = 'clothing:refresh', data = { outfits = list or {} } })
end
RegisterNUICallback('getOutfits', function(_, cb)
  RegisterNetEvent('nifty:client:outfitList', onOutfitListFetch)
  TriggerServerEvent('nifty:server:outfitList')
  cb({ ok = true })
end)

RegisterNUICallback('saveOutfit', function(data, cb)
  if data and data.name then
    TriggerServerEvent('nifty:server:outfitSave', { name = data.name })
  end
  cb({ ok = true })
end)

RegisterNUICallback('deleteOutfit', function(data, cb)
  if data and data.id then
    TriggerServerEvent('nifty:server:outfitDelete',
                       { outfitId = tostring(tonumber(data.id) or '') })
  end
  cb({ ok = true })
end)

RegisterNUICallback('renameOutfit', function(data, cb)
  if data and data.id and data.name then
    TriggerServerEvent('nifty:server:outfitRename', {
      id = tostring(tonumber(data.id) or ''), name = data.name,
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('applyOutfit', function(data, cb)
  if data and data.id then
    TriggerServerEvent('nifty:server:outfitApply',
                       { outfitId = tostring(tonumber(data.id) or '') })
  end
  cb({ ok = true })
end)

-- Store
local function onStoreList(data)
  if not data then return end
  -- Don't RemoveEventHandler: the store can re-fetch on a different
  -- slot and we don't want to lose the listener. The handler is
  -- route-aware (kind + id match).
  SendNUIMessage({
    action = 'storeList',
    data   = { kind = data.kind, id = data.slot, items = data.items or {} },
  })
end
-- The store server event has no echo keys; we always listen.
RegisterNetEvent('nifty:client:storeListForSlot', onStoreList)

RegisterNUICallback('getStoreListForSlot', function(data, cb)
  if data and data.kind and data.id then
    TriggerServerEvent('nifty:server:storeListForSlot', {
      kind = data.kind, slot_id = tonumber(data.id),
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('purchaseItem', function(data, cb)
  if data and data.kind and data.slot_id then
    TriggerServerEvent('nifty:server:clothingPurchase', {
      kind      = data.kind,
      slot_id   = tonumber(data.slot_id),
      collection = '',
      drawable  = tonumber(data.drawable) or 0,
      texture   = tonumber(data.texture) or 0,
    })
  end
  cb({ ok = true })
end)

-- One-shot listener for the purchase reply; the store.js toast
-- shows the result and the NUI is closed.
RegisterNetEvent('nifty:client:clothingPurchase', function(data)
  SendNUIMessage({ action = 'purchaseResult', data = data or {} })
end)

-- ---------------------------------------------------------------- open / close
-- Wardrobe: the slot list lives on the server, so the open handshake
-- goes through `nifty:server:wardrobeOpen` first. The reply carries
-- the slots the character actually owns and the character display
-- name; we then send the NUI 'open' message with that data so the
-- root panel can render the slot buttons without an extra round trip.
local function onWardrobeOpenReply(reply)
  RemoveEventHandler(onWardrobeOpenReply)
  sendOpen('wardrobe', reply or {})
end
AddEventHandler('nifty:client:openWardrobe', function()
  RegisterNetEvent('nifty:client:wardrobeOpenReply', onWardrobeOpenReply)
  TriggerServerEvent('nifty:server:wardrobeOpen')
end)

-- Store: triggered by cl_targets.lua when the player presses K inside
-- a store's proximity radius. The storeId is informational; the
-- server picks the price list for whichever shop the player is in.
AddEventHandler('nifty:client:openStore', function(storeId)
  sendOpen('store', { storeId = storeId })
end)

-- Chat command fallback
RegisterCommand('+niftyclotheshop', function()
  TriggerEvent('nifty:client:openStore', 'manual')
end, false)
RegisterCommand('-niftyclotheshop', function() end, false)
RegisterKeyMapping('+niftyclotheshop', 'Nifty Life - Klamottenladen', 'keyboard', 'F7')

-- Releasing focus on stop and on disconnect is handled by the focus block above,
-- which registers those handlers itself. Two copies would be two sources of truth
-- for one flag.
