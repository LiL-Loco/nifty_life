--[[
  Dropped-item proximity + pickup.

  Companion to server/sv_drops.lua. The server broadcasts spawns
  (`nifty:client:groundItemSpawned`) and despawns
  (`nifty:client:groundItemDespawned`); the client keeps a small cache
  of network ids for known drops and runs a low-frequency proximity
  thread that shows a marker + DrawText3D prompt when one is in range,
  matching the `cl_targets.lua` pattern since ox_target is not installed.

  Key E picks up the nearest in-range drop. The server re-validates
  proximity + ownership before crediting the inventory.

  Refresh of the known-drops list happens on the spawn/despawn broadcast
  pairs. A drop that we never received a spawn for (network race) does
  not get picked up; the server has the canonical list.
]]

local RESOURCE = GetCurrentResourceName()

-- Known drops on this client. key = networkId, value = {code, name, x, y, z}.
local drops = {}

local PICKUP_RADIUS = 4.0
local PROXIMITY_RADIUS = 6.0

RegisterNetEvent('nifty:client:groundItemSpawned', function(data)
  if type(data) ~= 'table' or not data.networkId then return end
  drops[tonumber(data.networkId)] = {
    code = data.code,
    name = data.name or tostring(data.code),
    x    = tonumber(data.x), y = tonumber(data.y), z = tonumber(data.z),
  }
end)

RegisterNetEvent('nifty:client:groundItemDespawned', function(data)
  if type(data) ~= 'table' or not data.networkId then return end
  drops[tonumber(data.networkId)] = nil
end)

-- Proximity thread. Same nil-guard pattern as cl_targets.lua (see the
-- fix there for why we cannot trust GetEntityCoords unconditionally).
local function safeCoords(ped)
  local c = GetEntityCoords(ped)
  if not c or not c.x then return nil end
  return c.x, c.y, c.z
end

CreateThread(function()
  while true do
    local ped = PlayerPedId()
    if ped and ped ~= 0 then
      local px, py, pz = safeCoords(ped)
      if px then
        local nearestNetId, nearestDist = nil, 9999.0
        for netId, d in pairs(drops) do
          -- Use the cached spawn coords. Converting from network id
          -- to entity every frame is wasteful and the cached coords
          -- stay valid because drops don't move.
          if d.x and d.y and d.z then
            local dx, dy, dz = px - d.x, py - d.y, pz - d.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist < nearestDist then
              nearestDist = dist
              nearestNetId = netId
            end
          end
        end

        if nearestNetId and nearestDist <= PROXIMITY_RADIUS then
          local d = drops[nearestNetId]
          -- Draw marker on the ground at the drop and a small prompt.
          -- Keep the marker stable so the player can read the text.
          DrawMarker(1, d.x, d.y, d.z - 0.95, 0, 0, 0, 0, 0, 0,
            0.4, 0.4, 0.4, 168, 100, 168, 120,
            false, true, 2, false, nil, nil, false)
          -- Above-the-marker label; uses native text layer so it
          -- works without a HUD.
          SetTextScale(0.34, 0.34)
          SetTextFont(4)
          SetTextProportional(1)
          SetTextColour(255, 255, 255, 220)
          SetTextCentre(1)
          SetTextEntry('STRING')
          AddTextComponentString(('E - Aufheben (%s)'):format(d.name))
          -- Text floats slightly above the marker's center.
          local onScreen, sx, sy = World3dToScreen2d(d.x, d.y, d.z + 0.4)
          if onScreen then DrawText(sx, sy) end
        end
      end
    end

    Wait(0)
  end
end)

-- Pickup keypress. E is already used for property enter via nifty-housing
-- but those keymaps are mutually exclusive in practice (only one is
-- active at a time depending on proximity context); the wording on the
-- prompt ("Aufheben") disambiguates.
RegisterCommand('+niftygroundpickup', function()
  local ped = PlayerPedId()
  if not ped or ped == 0 then return end
  local px, py, pz = safeCoords(ped)
  if not px then return end

  local nearestNetId, nearestDist = nil, PICKUP_RADIUS
  for netId, d in pairs(drops) do
    if d.x and d.y and d.z then
      local dx, dy, dz = px - d.x, py - d.y, pz - d.z
      local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
      if dist < nearestDist then
        nearestDist = dist
        nearestNetId = netId
      end
    end
  end

  if not nearestNetId then return end

  -- The server re-validates - we send just the networkId. The server's
  -- pickup handler will refuse with too_far if the player's actual coords
  -- no longer match (e.g. walking while pressing E).
  TriggerServerEvent('nifty:server:pickupGroundItem', { networkId = nearestNetId })
end, false)

RegisterCommand('-niftygroundpickup', function() end, false)
RegisterKeyMapping('+niftygroundpickup', 'Nifty Life — Item aufheben', 'keyboard', 'E')

print(('[%s] drop pickup ready'):format(RESOURCE))
