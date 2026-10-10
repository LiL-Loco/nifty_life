--- Housing entrances — markers, blips and a prompt. Nothing more.
---
--- This file is **presentation only**, and that is the whole design. It does not
--- know whether a house is free, whether the player may have it, or what it
--- costs. Those are the server's answers (ADR-0013, ADR-0009). The client draws
--- a marker on the map and sends a request when a key is pressed; if the answer
--- is no, the server says no and the client changes nothing.
---
--- It also does not teleport. Teleporting needs a confirmed interior (ADR-0013)
--- and a known interior exit coordinate, and `properties.exit_*` is NULL for
--- every seeded row until Bob74_IPL has proved the interior loads. Teleporting
--- into an IPL that silently failed to load drops the player into the void with
--- no geometry and no way back. Markers are the half of housing that is honest
--- before that verification, and they are genuinely useful on their own.
---
--- Coordinates come from the server's property list, so a catalogue row is the
--- only way a marker appears. There is no marker table in this file that could
--- drift from the database.

local RESOURCE = GetCurrentResourceName()

--- propertyId -> { blip, marker, name, owned }
local entrances = {}

--- Tier decides colour, not value. One extra lookup is cheaper than asking the
--- server what a district is worth, and the answer cannot go stale on screen.
local TIER_COLOURS = {
  outlier  = 5,   -- red
  entry    = 2,   -- green
  standard = 1,   -- white
  premium  = 3,   -- blue
  luxury   = 4,   -- purple
}

--- Three-dimensional floating text. GTA has no native for this; every project
--- writes its own and they all differ slightly. This one draws a rect measured
--- from the text width rather than a fixed box, so a long property name does not
--- sit in a box sized for a short one.
local function DrawText3D(x, y, z, text)
  local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)

  if not onScreen then return end

  local cam = GetGameplayCamCoords()
  local distance = #(cam - vector3(x, y, z))
  local scale = (distance / 2.0) + 0.15

  SetTextScale(0.0, scale)
  SetTextFont(4)
  SetTextCentre(true)
  SetTextColour(255, 255, 255, 215)
  SetTextEntry('STRING')
  AddTextComponentString(text)
  DrawText(screenX, screenY)

  -- A hairline under the text, so the prompt is readable against a bright sky
  -- and against dark asphalt without needing a background box.
  local rectWidth = (string.len(text) * scale) + 10

  DrawRect(screenX, screenY + (scale * 10.0), rectWidth, 1.0, 0, 0, 0, 120)
end

-- ---------------------------------------------------------------------------
-- Building and tearing down
-- ---------------------------------------------------------------------------

local function clearEntrances()
  for id, entrance in pairs(entrances) do
    if entrance.blip then RemoveBlip(entrance.blip) end
    if entrance.marker then DeleteMarker(entrance.marker) end
    entrances[id] = nil
  end
end

--- Rebuild from scratch on every push. Patching a list instead would let a
--- property that was sold or deactivated keep a marker until something else
--- happened to notice.
local function buildEntrances(list)
  clearEntrances()

  for _, property in ipairs(list) do
    local x, y, z = property.entrance.x, property.entrance.y, property.entrance.z

    -- A row without a position cannot be marked. The seed leaves entrance_x/y
    -- NULL for entries whose coordinates were never measured, and this is where
    -- that honesty has to be respected instead of defaulted to 0,0,0 — which
    -- would put a marker in the middle of the ocean.
    if x == nil or y == nil then
      print(('[%s] property %s has no entrance position, not marked'):format(
        RESOURCE, tostring(property.code)))
    else
      local blip = AddBlipForCoord(x, y, z)
      SetBlipSprite(blip, 40)
      SetBlipDisplay(blip, 4)
      SetBlipScale(blip, 0.7)
      SetBlipColour(blip, TIER_COLOURS[property.tier] or 1)
      SetBlipAsShortRange(blip, false)

      local marker = AddMarker(1, x, y, z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.6, 0.6, 0.3, 120, 200, 120, 100, false, true, 2, false, nil, nil, false)

      entrances[property.id] = {
        blip = blip,
        marker = marker,
        name = property.name,
        owned = property.owned,
        x = x, y = y, z = z,
      }
    end
  end
end

RegisterNetEvent('nifty:client:properties', function(list)
  if type(list) ~= 'table' then return end
  buildEntrances(list)
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  clearEntrances()
end)

-- ---------------------------------------------------------------------------
-- Proximity prompt
-- ---------------------------------------------------------------------------

--- Shown while standing at a door. Text is chosen by the state the SERVER last
--- reported — a client that decided this itself could show "take this house" to
--- somebody who already owns it, and the player would learn about it by being
--- refused.
local function promptFor(entrance)
  if entrance.owned then
    return ('~a~%s~s~n~i~Deine Wohnung~s~'):format(entrance.name)
  end
  return ('~a~%s~s~n~i~[E] In Besitz nehmen~s~'):format(entrance.name)
end

CreateThread(function()
  local nearestId, nearestDistance = nil, 2.5

  while true do
    Wait(0)

    local player = PlayerPedId()
    local px, py = GetEntityCoords(player)

    nearestId, nearestDistance = nil, 2.5

    for id, entrance in pairs(entrances) do
      -- Cheapest possible distance check: a squared 2D comparison. Two
      -- properties in the same tower share a door, so Y is the axis that
      -- actually separates them, and this is also why the marker Y in the seed
      -- is a measured value and not a rounded one.
      local dx, dy = px - entrance.x, py - entrance.y
      local distanceSquared = (dx * dx + dy * dy)

      if distanceSquared < nearestDistance then
        nearestDistance = distanceSquared
        nearestId = id
      end
    end

    if nearestId then
      local entrance = entrances[nearestId]
      DrawMarker(1, entrance.x, entrance.y, entrance.z, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.6, 0.6, 0.3, 200, 120, 120, 120,
        false, true, 2, false, nil, nil, false)
      DrawText3D(entrance.x, entrance.y, entrance.z + 0.3, promptFor(entrance))
    end
  end
end)

--- E at a door. Deliberately dumb: no client-side check of tier, cost or
--- eligibility. It forwards the property id and lets `Ownership.acquireProperty`
--- be the only thing that answers.
RegisterCommand('niftyenter', function()
  local player = PlayerPedId()
  local px, py = GetEntityCoords(player)

  local bestId, bestDistance = nil, 2.5

  for id, entrance in pairs(entrances) do
    local dx, dy = px - entrance.x, py - entrance.y
    local distanceSquared = dx * dx + dy * dy

    if distanceSquared < bestDistance then
      bestDistance = distanceSquared
      bestId = id
    end
  end

  if bestId then
    TriggerServerEvent('nifty:server:acquireProperty', bestId)
  end
end, false)

RegisterKeyMapping('niftyenter', 'Nifty Life — Haustür benutzen', 'keyboard', 'E')

-- ---------------------------------------------------------------------------
-- Debug
-- ---------------------------------------------------------------------------

--- `niftyhouses` prints what the client actually built. The failure mode this
--- exists for: the server sent 50 properties, and 12 of them had no measured
--- entrance. Without this, that shows up as "some doors are missing" and gets
--- debugged in the wrong file.
RegisterCommand('niftyhouses', function()
  local total, marked = 0, 0
  for _, entrance in pairs(entrances) do
    total = total + 1
    if entrance.marker ~= nil then marked = marked + 1 end
  end
  print(('[%s] %d entrance(s) built, %d with a marker'):format(RESOURCE, total, marked))
end, false)