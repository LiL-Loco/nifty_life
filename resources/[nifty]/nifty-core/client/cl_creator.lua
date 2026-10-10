--- Character creator (ADR-0017, ADR-0014 layer 3).
---
--- Staging, camera, collection discovery, and the NUI bridge.
---
--- Nothing here decides validity. The client only offers what
--- AppearanceConfig permits and the server re-validates every structure before
--- storing it — the collection natives are client-side, so the server cannot ask
--- the engine itself.

local creatorOpen = false
local currentModel = 'mp_m_freemode_01'
local currentSelection = {}   -- accumulated { components = {}, props = {} }

-- --------------------------------------------------------------- discovery

--- Enumerate what this ped model actually has, filtered to the allowlist.
--- Runs once per model (not per UI open) because it is a few hundred native
--- calls and the answer cannot change while the process lives.
local function collectSlots(ped, kind)
  local out = {}
  local collections = GetPedCollectionsCount(ped)

  for i = 0, collections - 1 do
    local name = GetPedCollectionName(ped, i)

    if AppearanceConfig.ALLOWED_COLLECTIONS[name] then
      for id = AppearanceConfig.MIN_COMPONENT_ID, AppearanceConfig.MAX_COMPONENT_ID do
        local count = (kind == 'props')
          and GetNumberOfPedCollectionPropDrawableVariations(ped, id, name)
          or  GetNumberOfPedCollectionDrawableVariations(ped, id, name)

        if count > 0 then
          local key = tostring(id)
          out[key] = out[key] or { collections = {} }
          out[key].collections[name] = count
        end
      end
    end
  end

  return out
end

local function sendSlots()
  local ped = PlayerPedId()

  SendNUIMessage({
    action = 'open',
    model = currentModel,
    slots = {
      components = collectSlots(ped, 'components'),
      props = collectSlots(ped, 'props'),
    },
  })
end

-- ----------------------------------------------------------------- camera

local creatorCam = nil
local camYaw = 0.0
local camPitch = 0.0

local function startCamera()
  local scene = CreatorScene
  local ped = PlayerPedId()

  SetEntityCoords(ped, scene.x, scene.y, scene.z, false, false, false, false)
  SetEntityHeading(ped, scene.heading)
  FreezeEntityPosition(ped, true)

  camYaw = scene.heading
  camPitch = scene.camPitch

  local cam = CreateCamWithParams(
    'DEFAULT_SCRIPTED_CAMERA',
    scene.x, scene.y + scene.camHeight, scene.z + 1.4,
    0.0, 0.0, 0.0, 50.0, false, 0
  )
  PointCamAtCoord(cam, scene.x, scene.y, scene.z + 0.9, 1.0)

  creatorCam = cam
  RenderScriptCams(cam, true, false, 0)
  FreezeCamPosition(cam, false)

  -- Firing is disabled so the player cannot shoot themselves while posed.
  DisablePlayerFiring(PlayerId(), true)
end

local function stopCamera()
  if creatorCam then
    RenderScriptCams(creatorCam, false, false, 0)
    DestroyCam(creatorCam, true)
    creatorCam = nil
  end
  DisablePlayerFiring(PlayerId(), false)
end

--- Orbit the camera with the mouse while the creator is open.
CreateThread(function()
  while true do
    if creatorOpen and creatorCam then
      Wait(0)

      local sensitivity = 0.25
      camYaw   = camYaw   - (GetDisabledControlNormal(0, 1) * sensitivity * 8.0)
      camPitch = camPitch + (GetDisabledControlNormal(0, 2) * sensitivity * 8.0)
      camPitch = math.max(-35.0, math.min(25.0, camPitch))

      local zoom = GetDisabledControlNormal(0, 0x10) * 0.05
      local radius = math.max(1.4, math.min(5.0, CreatorScene.camRadius + zoom))

      local scene = CreatorScene
      local x = scene.x + math.sin(math.rad(camYaw)) * radius
      local y = scene.y + math.cos(math.rad(camYaw)) * radius
      local z = scene.z + 1.4 + math.sin(math.rad(camPitch)) * radius

      SetCamCoord(creatorCam, x, y, z)
      PointCamAtCoord(creatorCam, scene.x, scene.y, scene.z + 0.95, 0.9)
    else
      Wait(250)
    end
  end
end)

-- ------------------------------------------------------------- open/close

local function openCreator()
  if creatorOpen then return end
  creatorOpen = true

  currentSelection = { components = {}, props = {} }
  currentModel = 'mp_m_freemode_01'

  startCamera()
  sendSlots()
end

local function closeCreator()
  if not creatorOpen then return end
  creatorOpen = false
  stopCamera()
  SendNUIMessage({ action = 'close' })
end

-- ----------------------------------------------------------- NUI callbacks

--- Apply a single slot the player just clicked. One slot at a time so the
--- preloaded drawable swaps immediately instead of rebuilding the whole ped.
RegisterNUICallback('creator:apply', function(data, cb)
  if not creatorOpen then return cb({ ok = false }) end

  local kind = (data.kind == 'props') and 'props' or 'components'
  local id = tonumber(data.id)
  local collection = type(data.collection) == 'string' and data.collection or ''
  local drawable = tonumber(data.drawable) or 0
  local texture = tonumber(data.texture) or 0

  if not id or id < AppearanceConfig.MIN_COMPONENT_ID or id > AppearanceConfig.MAX_COMPONENT_ID then
    return cb({ ok = false })
  end
  if not AppearanceConfig.ALLOWED_COLLECTIONS[collection] then
    return cb({ ok = false })
  end

  local ped = PlayerPedId()
  local slot = { collection = collection, drawable = drawable, texture = texture }
  currentSelection[kind][tostring(id)] = slot

  if kind == 'components' then
    SetPedCollectionPreloadVariationData(ped, id, collection, drawable, texture, 0)
    SetPedCollectionComponentVariation(ped, id, collection, drawable, texture, 0)
  else
    SetPedCollectionPreloadPropData(ped, id, collection, drawable, texture, true)
    SetPedCollectionPropIndex(ped, id, collection, drawable, texture, false)
  end

  exports['nifty-core']:applyAppearance(ped, {
    model = currentModel,
    components = currentSelection.components,
    props = currentSelection.props,
  })

  cb({ ok = true })
end)

RegisterNUICallback('creator:model', function(data, cb)
  if not creatorOpen then return cb({ ok = false }) end

  local model = type(data.model) == 'string' and data.model or nil
  if not model or not AppearanceConfig.PED_MODELS[model] then
    return cb({ ok = false })
  end

  currentModel = model
  currentSelection = { components = {}, props = {} }

  local hash = joaat(model)
  SetPlayerModel(PlayerId(), hash)
  SetModelAsNoLongerNeeded(hash)

  sendSlots()
  cb({ ok = true })
end)

RegisterNUICallback('creator:slots', function(_, cb)
  if creatorOpen then sendSlots() end
  cb({ ok = true })
end)

RegisterNUICallback('creator:reset', function(_, cb)
  if not creatorOpen then return cb({ ok = false }) end

  currentSelection = { components = {}, props = {} }
  local hash = joaat(currentModel)
  SetPlayerModel(PlayerId(), hash)
  SetModelAsNoLongerNeeded(hash)

  sendSlots()
  cb({ ok = true })
end)

RegisterNUICallback('creator:randomise', function(_, cb)
  if not creatorOpen then return cb({ ok = false }) end

  local ped = PlayerPedId()

  for kind, setter in pairs({
    components = SetPedCollectionComponentVariation,
    props      = SetPedCollectionPropIndex,
  }) do
    currentSelection[kind] = {}

    local slots = collectSlots(ped, kind)
    for id, info in pairs(slots) do
      -- Pick a collection that actually has options, then a random drawable.
      local names = {}
      for name in pairs(info.collections) do names[#names + 1] = name end
      if #names > 0 then
        local name = names[math.random(#names)]
        local drawable = math.random(0, info.collections[name] - 1)
        local texture = math.random(0, 2)
        currentSelection[kind][id] = {
          collection = name, drawable = drawable, texture = texture,
        }
        setter(ped, tonumber(id), name, drawable, texture, kind == 'props')
      end
    end
  end

  sendSlots()
  cb({ ok = true })
end)

RegisterNUICallback('creator:submit', function(data, cb)
  if not creatorOpen then return cb({ ok = false, error = 'not open' }) end

  TriggerServerEvent('nifty:server:createCharacter', {
    firstName = data.firstName,
    lastName = data.lastName,
    dateOfBirth = data.dateOfBirth,
    gender = data.gender,
    appearance = {
      model = data.model,
      components = currentSelection.components,
      props = currentSelection.props,
    },
  })

  -- The server answers via enterWorld or creatorError; keep the UI open until
  -- it does, so an error is visible rather than a silent no-op.
  cb({ ok = true })
end)

-- ---------------------------------------------------------------- results

RegisterNetEvent('nifty:client:enterWorld', function()
  closeCreator()
end)

RegisterNetEvent('nifty:client:creatorError', function(message)
  -- The creator stays open so the player can correct the input; the error is
  -- pushed to the UI rather than only to the console, because it is the player
  -- who needs to act on it.
  print(('[nifty-core] creator refused: %s'):format(tostring(message)))
  SendNUIMessage({ action = 'error', message = tostring(message) })
end)

exports('isCreatorOpen', function() return creatorOpen end)
exports('openCreator', openCreator)
exports('closeCreator', closeCreator)