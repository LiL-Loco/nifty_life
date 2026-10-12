--[[
  Spawn-location picker. The 2026-10-12 NUI migration replaced the
  NativeUI menu with a vanilla-JS NUI (ui/spawn.html). The camera
  flight, the location list, the current-pick state, and the
  onConfirm callback all live in this file; the NUI just renders
  buttons and posts back pick / confirm.

  The contract is unchanged:
    exports.openSpawnPicker(locations, onConfirm)
      locations: array of { key, label, x, y, z, heading }
      onConfirm(x, y, z, heading): called with the chosen coords
        AFTER the NUI is closed and the cameras are torn down. nil
        means "abgebrochen".
]]

local RESOURCE = GetCurrentResourceName()

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

-- ---------------------------------------------------------------- module state
local locations   = nil
local onConfirmCb = nil
local currentPick = nil
local resolved    = false  -- true when the player confirmed, false on cancel
local cam, cam2

local function sendOpen()
  if not acquireFocus() then return end
  local list = {}
  for _, loc in ipairs(locations or {}) do
    list[#list + 1] = {
      key = loc.key, label = loc.label,
      x = loc.x, y = loc.y, z = loc.z, heading = loc.heading,
    }
  end
  SendNUIMessage({
    action = 'open',
    data   = { locations = list, currentKey = currentPick and currentPick.key or nil },
  })
end

local function sendClose()
  SendNUIMessage({ action = 'close' })
  releaseFocus()
end

-- ---------------------------------------------------------------- camera
local function flyTo(loc)
  if cam then DestroyCam(cam, true) end
  if cam2 then DestroyCam(cam2, true) end

  cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
    loc.x, loc.y, loc.z + Spawn.CAM_HIGH_Z,
    -85.0, 0.0, 0.0,
    Spawn.CAM_FAR_FOV, false, 0)
  SetCamActive(cam, true)
  RenderScriptCams(true, false, 1, true, true)

  SetTimeout(Spawn.CAM_SETTLE_MS, function()
    cam2 = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
      loc.x, loc.y, loc.z + Spawn.CAM_NEAR_Z,
      -20.0, 0.0, loc.heading,
      Spawn.CAM_NEAR_FOV, false, 0)
    PointCamAtCoord(cam2, loc.x, loc.y, loc.z)
    SetCamActiveWithInterp(cam2, cam, Spawn.CAM_INTERP_MS, true, true)
  end)
end

local function destroyCams()
  RenderScriptCams(false, true, 0, true, true)
  if cam then SetCamActive(cam, false); DestroyCam(cam, true); cam = nil end
  if cam2 then SetCamActive(cam2, false); DestroyCam(cam2, true); cam2 = nil end
end

-- ---------------------------------------------------------------- NUI callbacks
RegisterNUICallback('pickSpawn', function(data, cb)
  if not data or not data.key or not locations then cb({ ok = true }) return end
  for _, loc in ipairs(locations) do
    if loc.key == data.key then
      currentPick = loc
      flyTo(loc)
      -- Push the new current key so the NUI shows the active state.
      SendNUIMessage({ action = 'update', data = { currentKey = loc.key } })
      break
    end
  end
  cb({ ok = true })
end)

RegisterNUICallback('confirmSpawn', function(data, cb)
  resolved = data and data.confirmed == true
  sendClose()
  destroyCams()
  local cb0 = onConfirmCb
  local pick = currentPick
  onConfirmCb = nil
  locations = nil
  currentPick = nil
  if cb0 then
    if resolved and pick then
      cb0(pick.x, pick.y, pick.z, pick.heading or 0.0)
    else
      cb0(nil)
    end
  end
  resolved = false
  cb({ ok = true })
end)

-- ---------------------------------------------------------------- export
exports('openSpawnPicker', function(passedLocations, cb)
  if type(passedLocations) ~= 'table' or #passedLocations == 0 then
    print(('[%s] openSpawnPicker: no locations provided'):format(RESOURCE))
    return false
  end
  if type(cb) ~= 'function' then
    print(('[%s] openSpawnPicker: callback is not a function'):format(RESOURCE))
    return false
  end

  locations   = passedLocations
  onConfirmCb = cb
  currentPick = passedLocations[1]
  resolved    = false

  sendOpen()
  flyTo(currentPick)
  return true
end)

-- Release focus if the player drops while the picker is open.
AddEventHandler('playerDropped', function() releaseFocus() end)
AddEventHandler('onResourceStop', function(res)
  if res == RESOURCE and focusHeld then releaseFocus() end
end)
