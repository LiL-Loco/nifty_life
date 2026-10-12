-- nifty-clothing NUI driver — wardrobe bridge.
-- V1 only wires the wardrobe NUI up to the existing wardrobe Lua code
-- through a thin adapter. Each NUI callback fans out to one or more
-- existing server events. The legacy NativeUI surface remains in
-- cl_wardrobe.lua for the store and for legacy compatibility; the
-- wardrobe /wardrobe command now opens the NUI instead of a menu.
--
-- This file is a SKELETON: the wardrobe NUI integration is a separate
-- task. For now, the wardrobe.js file renders a placeholder root
-- panel and ESC closes it. cl_wardrobe.lua still works for the
-- /wardrobe command when the NUI is unavailable; both paths share
-- the same data state.

local RESOURCE = GetCurrentResourceName()

-- Module-level NUI state. The wardrobe NUI has at most one screen
-- visible at a time (root / slot / outfits / save), so a flat table
-- is enough. The Lua side of the wardrobe is the source of truth;
-- the NUI keeps a mirror that is rebuilt on every 'open' / 'refresh'.
local state = {
  owned = {},  -- owned[kind][slot] = { pieces = { { id, name, collection, drawable, texture } } }
}

-- ---------------------------------------------------------------- focus
local Focus = exports['nifty-core']
local focusHeld = false

local function acquireFocus()
  if focusHeld then return true end
  if not Focus or type(Focus.acquire) ~= 'function' then return false end
  local ok = Focus.acquire(RESOURCE)
  if ok then focusHeld = true end
  return ok
end

local function releaseFocus()
  if not focusHeld then return end
  if Focus and type(Focus.release) == 'function' then Focus.release(RESOURCE) end
  focusHeld = false
end

local function sendOpen(data)
  if not acquireFocus() then return end
  SendNUIMessage({ action = 'open', data = data or {} })
end

local function sendRefresh(data)
  if not focusHeld then return end
  SendNUIMessage({ action = 'refresh', data = data or {} })
end

local function sendClose()
  SendNUIMessage({ action = 'close' })
  releaseFocus()
end

-- ---------------------------------------------------------------- NUI callbacks
-- Stub handlers: each NUI gesture fans out to the equivalent server
-- event. Full state wiring comes in the wardrobe integration PR.

RegisterNUICallback('closePanel', function(_, cb)
  sendClose()
  cb({ ok = true })
end)

RegisterNUICallback('getOwnedForSlot', function(data, cb)
  if not (data and data.kind and data.id) then cb({ ok = true }) return end
  local kind = data.kind
  local slot = tonumber(data.id) or 0

  local function onReply(reply)
    if reply and reply.kind == kind and reply.slot == slot then
      RemoveEventHandler(onReply)
      state.owned[kind] = state.owned[kind] or {}
      state.owned[kind][slot] = reply.pieces or {}
      sendRefresh({ owned = state.owned })
    end
  end
  RegisterNetEvent('nifty:client:wardrobeListForSlot', onReply)
  TriggerServerEvent('nifty:server:wardrobeListForSlot', { kind = kind, slot = slot })
  cb({ ok = true })
end)

RegisterNUICallback('unequip', function(data, cb)
  if data and data.kind and data.id then
    TriggerServerEvent('nifty:server:clothingUnequip', {
      kind = data.kind, slot = tonumber(data.id) or 0,
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('equip', function(data, cb)
  if data and data.kind and data.id and data.pieceId then
    TriggerServerEvent('nifty:server:clothingEquip', {
      kind = data.kind, slot = tonumber(data.id) or 0,
      pieceId = tonumber(data.pieceId) or 0,
    })
  end
  cb({ ok = true })
end)

local function onOutfitList(list)
  RemoveEventHandler(onOutfitList)
  sendRefresh({ outfits = list or {} })
end

RegisterNUICallback('getOutfits', function(_, cb)
  RegisterNetEvent('nifty:client:outfitList', onOutfitList)
  TriggerServerEvent('nifty:server:outfitList')
  cb({ ok = true })
end)

RegisterNUICallback('applyOutfit', function(data, cb)
  if data and data.id then
    TriggerServerEvent('nifty:server:outfitApply', { id = tonumber(data.id) or 0 })
  end
  cb({ ok = true })
end)

RegisterNUICallback('saveOutfit', function(data, cb)
  if data and data.name then
    TriggerServerEvent('nifty:server:outfitSave', { name = data.name })
  end
  cb({ ok = true })
end)

-- ---------------------------------------------------------------- open / close
-- Override the /wardrobe command: open the NUI instead of a NativeUI
-- menu. The legacy NativeUI path stays for callers that ask for it
-- explicitly (e.g. tests or scripted boots).
RegisterCommand('wardrobe', function()
  -- Build initial state and push to the NUI.
  sendOpen({
    character = {},
    slots = {
      components = { 1, 2, 3, 4, 5, 7, 8, 11 },
      props      = { 0, 1, 2, 6, 7 },
    },
    componentLabels = {
      [1] = 'Gesicht', [2] = 'Haare', [3] = 'Oberteil', [4] = 'Hose',
      [5] = 'Tasche',  [7] = 'Accessoires', [8] = 'Ruestung', [11] = 'Jacke',
    },
    propLabels = {
      [0] = 'Kopfbedeckung', [1] = 'Brille', [2] = 'Ohrring',
      [6] = 'Schmuck',       [7] = 'Uhr',
    },
  })
end, false)

AddEventHandler('onResourceStop', function(res)
  if res == RESOURCE and focusHeld then releaseFocus() end
end)
AddEventHandler('playerDropped', function() releaseFocus() end)
