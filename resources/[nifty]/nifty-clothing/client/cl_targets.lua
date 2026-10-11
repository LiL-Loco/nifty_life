--[[
  In-world prompts for clothing stores.

  No `ox_target` is installed on this server, so proximity-based interaction
  is the same DrawMarker + DrawText3D + key-press pattern nifty-housing uses
  (nifty-housing/client/cl_housing.lua:155-199). A marker and a blip appear
  for each store; pressing `K` while inside the radius opens the store menu.

  Wardrobe is property-only per the agreed design. nifty-housing does not
  yet expose an interior / closet hook, so for V1 the wardrobe opens via the
  `/wardrobe` console command (see cl_wardrobe.lua). When nifty-housing adds
  the hook, this file will gain a wardrobe zone whose prompt routes to
  Wardrobe.open.
]]

local RESOURCE = GetCurrentResourceName()

-- Stores from shared/stores.lua. The shape `{ id, name, x, y, z }`.
local stores = Stores and Stores.Stores or {}

local PROXIMITY = 2.0   -- sqrt(4) = 2 metres, matches nifty-housing.
local MARKER_TYPE = 1   -- upright cylinder.

-- ----------------------------------------------------------------------------
-- DrawText3D
-- ----------------------------------------------------------------------------

-- Same helper as nifty-housing/client/cl_housing.lua. Drawn on the client's
-- screen in world coords; lives at module scope so the proximity tick can
-- see it without any resolve-each-call dance.
local function DrawText3D(x, y, z, text)
  local onScreen, sx, sy = World3dToScreen2d(x, y, z)
  if not onScreen then return end

  SetTextScale(0.32, 0.32)
  SetTextFont(4)
  SetTextProportional(1)
  SetTextColour(255, 255, 255, 215)
  SetTextEntry('STRING')
  SetTextCentre(1)
  AddTextComponentString(text)
  DrawText(sx, sy)
end

-- ----------------------------------------------------------------------------
-- Blips
-- ----------------------------------------------------------------------------

local markers = {}

local function clearAll()
  for _, m in pairs(markers) do
    if m.blip and DoesBlipExist(m.blip) then RemoveBlip(m.blip) end
  end
  markers = {}
end

local function dropMarkers()
  for _, store in ipairs(stores) do
    local blip = AddBlipForCoord(store.x, store.y, store.z)
    SetBlipSprite(blip, 73)        -- GTA Online clothing icon.
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, false)
    SetBlipColour(blip, 47)        -- purple, distinct from the orange of shops.

    markers[store.id] = {
      store = store,
      blip = blip,
    }
  end
end

AddEventHandler('onClientResourceStart', function(resource)
  if resource ~= RESOURCE then return end
  dropMarkers()
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  clearAll()
end)

-- ----------------------------------------------------------------------------
-- Proximity tick
-- ----------------------------------------------------------------------------

local currentStoreId = nil

CreateThread(function()
  while true do
    local ped = PlayerPedId()
    if ped and ped ~= 0 then
      local coords = GetEntityCoords(ped)

      -- GetEntityCoords can briefly return a vector with nil components
      -- (very early spawn, teleport, or hidden ped). Skip this tick rather
      -- than crash on arithmetic below.
      if coords and coords.x and coords.y and coords.z then
        local px, py, pz = coords.x, coords.y, coords.z
        local nearestId, nearestDist = nil, 9999.0

        for id, m in pairs(markers) do
          local s = m.store
          local dx, dy, dz = px - s.x, py - s.y, pz - s.z
          local d2 = dx * dx + dy * dy + dz * dz
          if d2 < nearestDist then
            nearestDist = d2
            nearestId = id
          end
        end

        -- Only redraw the marker when the nearest store changes - leaves
        -- the on-screen state stable for the most part.
        currentStoreId = nearestId

        if nearestId and nearestDist <= (PROXIMITY * PROXIMITY) then
          local s = markers[nearestId].store
          DrawMarker(MARKER_TYPE, s.x, s.y, s.z - 1.0, 0, 0, 0,
            0, 0, 0, 0.6, 0.6, 0.3, 168, 80, 168, 100,
            false, true, 2, false, nil, nil, false)
          DrawText3D(s.x, s.y, s.z + 0.3, ('K - %s'):format(s.name))
        end
      end
    end

    Wait(0)
  end
end)

-- ----------------------------------------------------------------------------
-- Keypress
-- ----------------------------------------------------------------------------

local OPEN_EVENT = 'nifty:client:openStore'

RegisterCommand('+niftyclothing', function()
  if currentStoreId == nil then return end
  local m = markers[currentStoreId]
  if not m then return end

  TriggerEvent(OPEN_EVENT, m.store.id)
end, false)

RegisterCommand('-niftyclothing', function() end, false)
RegisterKeyMapping('+niftyclothing', 'Nifty Life - Klamotten kaufen', 'keyboard', 'K')
