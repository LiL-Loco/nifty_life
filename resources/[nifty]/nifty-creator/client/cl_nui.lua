-- nifty-creator NUI driver.
--
-- Owns: the NUI page lifecycle (acquire/release focus, push open/refresh/close),
-- the RegisterNUICallback handlers for every user gesture in the NUI, and the
-- long-running helper threads (face-bone projection, parent-portrait render,
-- camera-orbit Q/E).
--
-- Does NOT own: state. cl_creator.lua is the data engine; this file is a thin
-- adapter. Every callback here either calls a public helper from cl_creator.lua
-- (openCreator / closeCreator / setFeature / setSlot / ...), or it does the
-- native call itself (e.g. SetPedHairColor for hair colour channel change) and
-- then calls refresh() to push the new state back.

local RESOURCE = GetCurrentResourceName()

-- Forward declarations for helpers defined in cl_creator.lua. These are the
-- single source of truth for state mutations; cl_nui.lua never writes
-- `face.*` / `selection.*` directly.
local api = {
  openCreator      = function(...) return exports[RESOURCE].openCreator(...) end,
  closeCreator     = function(...) return exports[RESOURCE].closeCreator(...) end,
  isCreatorOpen    = function(...) return exports[RESOURCE].isCreatorOpen(...) end,
  setFeature       = function(...) return exports[RESOURCE].setFeature(...) end,
  setSlot          = function(...) return exports[RESOURCE].setSlot(...) end,
  setOverlay       = function(...) return exports[RESOURCE].setOverlay(...) end,
  setHairColour    = function(...) return exports[RESOURCE].setHairColour(...) end,
  setHairOverlayOpacity = function(...) return exports[RESOURCE].setHairOverlayOpacity(...) end,
  setEyeColour     = function(...) return exports[RESOURCE].setEyeColour(...) end,
  setHeadBlend     = function(...) return exports[RESOURCE].setHeadBlend(...) end,
  randomise        = function(...) return exports[RESOURCE].randomise(...) end,
  randomiseAll     = function(...) return exports[RESOURCE].randomiseAll(...) end,
  reset            = function(...) return exports[RESOURCE].reset(...) end,
  submit           = function(...) return exports[RESOURCE].submit(...) end,
  cancel           = function(...) return exports[RESOURCE].cancel(...) end,
  zoomCamera       = function(...) return exports[RESOURCE].zoomCamera(...) end,
  camYaw           = function(...) return exports[RESOURCE].camYaw(...) end,
  pickModel        = function(...) return exports[RESOURCE].pickModel(...) end,
  pickTattoo       = function(...) return exports[RESOURCE].pickTattoo(...) end,
  removeTattoo     = function(...) return exports[RESOURCE].removeTattoo(...) end,
  swapOverlayPalette = function(...) return exports[RESOURCE].swapOverlayPalette(...) end,
  showSkinCam      = function(...) return exports[RESOURCE].showSkinCam(...) end,
  getState         = function(...) return exports[RESOURCE].getState(...) end,
  captureParentPortrait = function(...) return exports[RESOURCE].captureParentPortrait(...) end,
  getTattooZones   = function(...) return exports[RESOURCE].getTattooZones(...) end,
  getTattoosByZone = function(...) return exports[RESOURCE].getTattoosByZone(...) end,
  projectFaceBones = function(...) return exports[RESOURCE].projectFaceBones(...) end,
}

-- Resolve any nil forward declarations (export not yet wired by the engine)
-- at script load. If a function is missing, log and continue; the corresponding
-- NUI callback will refuse gracefully.
for k, v in pairs(api) do
  if type(v) ~= 'function' then
    print(('[cl_nui] export "%s" is not available yet (deferred). NUI will retry on first use.'):format(k))
  end
end

local function tryCall(name, ...)
  local fn = api[name]
  if type(fn) ~= 'function' then
    print(('[cl_nui] tried to call missing export "%s"'):format(name))
    return nil
  end
  return fn(...)
end

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

-- ---------------------------------------------------------------- push helpers
local function buildPayload()
  local s = tryCall('getState')
  if type(s) ~= 'table' then return nil end
  return {
    currentModel      = s.currentModel,
    characterGender   = s.characterGender,
    scene             = s.scene,
    selection         = s.selection,
    face              = s.face,
    slots             = s.slots,
    labels            = s.labels,
    palettes          = s.palettes,
    hairOverlayState  = s.hairOverlayState,
    modelIsUndecided  = s.modelIsUndecided,
    skinCam           = s.skinCam,
  }
end

local function sendOpen()
  if not acquireFocus() then
    print(('[cl_nui] could not acquire focus (holder: %s)'):format(
      Focus and type(Focus.holder) == 'function' and tostring(Focus.holder()) or 'unknown'))
    return
  end
  local payload = buildPayload()
  if not payload then return end
  SendNUIMessage({ action = 'open', data = payload })
end

local function sendRefresh()
  if not focusHeld then return end
  local s = tryCall('getState')
  if type(s) ~= 'table' then return end
  SendNUIMessage({ action = 'refresh', data = {
    selection = s.selection,
    face      = s.face,
    skinCam   = s.skinCam,
    slots     = s.slots,
  }})
end

-- Send a partial refresh with explicit keys (used by handlers that don't
-- need a full state dump).
local function sendPartialRefresh(t)
  if not focusHeld then return end
  SendNUIMessage({ action = 'refresh', data = t })
end

local function sendClose()
  SendNUIMessage({ action = 'close' })
  releaseFocus()
end

-- ---------------------------------------------------------------- face-bone projection thread
-- While the player is in the Gesichtszuege panel, a thread ticks the
-- 24 facial bones through GetWorldPositionOfEntityBone and
-- GetScreenCoordFromWorldCoord, then sends their screen positions to
-- the NUI every frame. The NUI positions 24 gold dots over the camera
-- viewport; the player can drag a dot to nudge the matching face
-- feature, which the NUI's onMove dispatches back as a setFeature
-- call.
--
-- 24 bones / frame * 8 bytes / bone = a few hundred bytes per push.
-- FiveM's CEF can sustain that easily at 60 fps.
local faceBonesActive = false
local FACE_BONE_PUSH_MS = 1000 / 30  -- cap at 30 Hz to keep CPU in check

Citizen.CreateThread(function()
  while true do
    if faceBonesActive and focusHeld then
      local bones = tryCall('projectFaceBones')
      if type(bones) == 'table' and #bones > 0 then
        SendNUIMessage({ action = 'faceBones', data = { bones = bones } })
      end
    end
    Citizen.Wait(FACE_BONE_PUSH_MS)
  end
end)

-- ---------------------------------------------------------------- callbacks
-- `fetchNui(name, body)` from the NUI hits `https://${GetParentResourceName()}/<name>`.
-- The handler receives the same body as a Lua table.

RegisterNUICallback('closePanel', function(data, cb)
  faceBonesActive = false
  tryCall('cancel')
  cb({ ok = true })
  -- closeCreator triggers 'nifty:client:enterWorld' or sends cancelCreator;
  -- both end with closeCreator which calls sendClose via a hook below.
end)

RegisterNUICallback('setFaceBonesActive', function(data, cb)
  faceBonesActive = (data and data.active == true)
  cb({ ok = true })
end)

RegisterNUICallback('getItemNames', function(data, cb)
  if not (data and data.kind and data.id) then cb({ ok = true }) return end
  local result = tryCall('getItemNames', data.kind, tonumber(data.id) or 0)
  if type(result) == 'table' then
    SendNUIMessage({
      action = 'itemNames',
      data = { kind = data.kind, id = data.id, names = result },
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('setSlot', function(data, cb)
  if type(data) == 'table' and data.kind and data.id then
    tryCall('setSlot', data.kind, tonumber(data.id), data.slot or {})
  end
  cb({ ok = true })
end)

RegisterNUICallback('setFeature', function(data, cb)
  if type(data) == 'table' and data.id then
    tryCall('setFeature', tonumber(data.id), tonumber(data.value) or 0.0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setOverlay', function(data, cb)
  if type(data) == 'table' and data.id and type(data.overlay) == 'table' then
    tryCall('setOverlay', tonumber(data.id), data.overlay)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setHairColour', function(data, cb)
  if type(data) == 'table' and data.channel and data.index then
    tryCall('setHairColour', data.channel, tonumber(data.index) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setHairOverlayOpacity', function(data, cb)
  if type(data) == 'table' and data.opacity then
    tryCall('setHairOverlayOpacity', tonumber(data.opacity) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setEyeColour', function(data, cb)
  if type(data) == 'table' and data.index then
    tryCall('setEyeColour', tonumber(data.index) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setHeadBlend', function(data, cb)
  if type(data) == 'table' then
    tryCall('setHeadBlend', data)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('randomise', function(_, cb)
  tryCall('randomise')
  sendRefresh()
  cb({ ok = true })
end)

RegisterNUICallback('randomiseAll', function(_, cb)
  tryCall('randomiseAll')
  sendRefresh()
  cb({ ok = true })
end)

RegisterNUICallback('reset', function(_, cb)
  tryCall('reset')
  sendRefresh()
  cb({ ok = true })
end)

RegisterNUICallback('submit', function(_, cb)
  tryCall('submit')
  cb({ ok = true })
end)

RegisterNUICallback('cancel', function(_, cb)
  tryCall('cancel')
  cb({ ok = true })
end)

RegisterNUICallback('zoomIn', function(_, cb)
  tryCall('zoomCamera', 1)
  cb({ ok = true })
end)

RegisterNUICallback('zoomOut', function(_, cb)
  tryCall('zoomCamera', -1)
  cb({ ok = true })
end)

RegisterNUICallback('camYaw', function(data, cb)
  if type(data) == 'table' and data.delta then
    tryCall('camYaw', tonumber(data.delta) or 0)
  end
  cb({ ok = true })
end)

RegisterNUICallback('pickModel', function(data, cb)
  if type(data) == 'table' and data.model then
    tryCall('pickModel', data.model)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('pickTattoo', function(data, cb)
  if type(data) == 'table' and data.zoneId then
    tryCall('pickTattoo', tonumber(data.zoneId), data.collection, tonumber(data.preset) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('removeTattoo', function(data, cb)
  if type(data) == 'table' and data.zoneId then
    tryCall('removeTattoo', tonumber(data.zoneId))
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('swapOverlayPalette', function(data, cb)
  if type(data) == 'table' and data.id then
    tryCall('swapOverlayPalette', tonumber(data.id), tonumber(data.paletteIndex) or 1)
    sendRefresh()
  end
  cb({ ok = true })
end)

-- ---------------------------------------------------------------- lazy fetches
RegisterNUICallback('getTattooZones', function(_, cb)
  local zones = tryCall('getTattooZones') or {}
  SendNUIMessage({ action = 'tattooZones', data = { zones = zones } })
  cb({ ok = true })
end)

RegisterNUICallback('getTattoosByZone', function(data, cb)
  if type(data) == 'table' and data.zoneId then
    local t = tryCall('getTattoosByZone', tonumber(data.zoneId)) or {}
    SendNUIMessage({ action = 'tattoosByZone', data = { zoneId = data.zoneId, tattoos = t } })
  end
  cb({ ok = true })
end)

RegisterNUICallback('requestParentPortraits', function(_, cb)
  -- Capture both parents in a hidden clone; reply with both base64 PNGs.
  local mother = tryCall('captureParentPortrait', 'mother')
  local father = tryCall('captureParentPortrait', 'father')
  SendNUIMessage({ action = 'parentPortraits', data = {
    mother = type(mother) == 'string' and mother or '',
    father = type(father) == 'string' and father or '',
  }})
  cb({ ok = true })
end)

RegisterNUICallback('tickFaceBones', function(_, cb)
  local bones = tryCall('projectFaceBones') or {}
  SendNUIMessage({ action = 'faceBones', data = { bones = bones } })
  cb({ ok = true })
end)

-- ---------------------------------------------------------------- server hooks
-- `nifty:client:enterWorld` is the canonical "creator finished" signal.
-- The server sends it after `nifty:server:finishAppearance` succeeds, or
-- immediately on a returning player who already has a character. Either
-- way, the creator must close.
AddEventHandler('nifty:client:enterWorld', function()
  if focusHeld then sendClose() end
end)

-- `nifty:client:openCreator` is the entry point. The server fires it once
-- the player has been authorised (no character yet, or force re-create).
-- The handler opens the camera, parks the player, then sends the NUI.
AddEventHandler('nifty:client:openCreator', function(data)
  tryCall('openCreator', data or {})
  sendOpen()
end)

-- closeCreator fires this after the data engine has torn down the
-- camera and state; the NUI driver is responsible for the NUI side
-- (close the panel, release focus).
AddEventHandler('nifty:client:closeCreator', function()
  sendClose()
end)

-- `nifty:client:creatorError` keeps the creator open so the player can
-- retry. The error message is forwarded to the NUI as a toast.
AddEventHandler('nifty:client:creatorError', function(message)
  SendNUIMessage({ action = 'error', data = { message = message or '' } })
end)

-- Player dropped mid-creator: drop focus so the next client doesn't
-- inherit a captured mouse.
AddEventHandler('playerDropped', function() releaseFocus() end)
AddEventHandler('onResourceStop', function(res) if res == RESOURCE then releaseFocus() end end)
