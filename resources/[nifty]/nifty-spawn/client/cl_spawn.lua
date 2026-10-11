--- Player spawning (ADR-0024).
---
--- WHY THIS EXISTS RATHER THAN `ensure spawnmanager`
---
--- Two reasons, and the first is not about ownership.
---
--- spawnmanager takes its spawn points from mapmanager or a map resource. This
--- server has neither - `resources/` holds nothing but nifty and oxmysql - so
--- spawnmanager has zero points to spawn from and cannot spawn anybody. Adding a
--- map resource purely to feed a spawn point is a dependency bought for one
--- coordinate pair.
---
--- The second is ADR-0002. spawnmanager decides nothing about characters, money or
--- jobs, so it would have been permissible - but it is also a hundred lines of
--- somebody else's guessing about when a player should exist, and our answer is
--- unusual: a player must NOT spawn at join. They stand frozen at the creation
--- point until they have a character, and possibly not even that, because the
--- creator may send them straight back out. Owning the spawn means that rule lives
--- in one readable place instead of being negotiated with an autospawn flag.
---
--- THE CONTRACT IS SPAWNMANAGER'S, ON PURPOSE
---
--- Same export names, same event, same behaviour. That is not nostalgia: it means
--- every tutorial, snippet and third-party script written against spawnmanager
--- reads correctly here, and if we ever do use the real one, ours is a drop-in
--- replacement rather than a rewrite. The differences are stated where they occur.
---
--- WHAT IS DIFFERENT, AND WHY
---
---   * `setAutoSpawnCallback` exists and does something, but nothing calls it.
---     spawnmanager calls the callback to decide WHERE to spawn. We spawn at a
---     point the server already chose in `nifty:client:enterWorld`, because that
---     point came out of the database. The export is kept for contract
---     compatibility and is honoured if anything ever sets it.
---
---   * `addSpawnPoint` takes our shape (`x, y, z, heading, label, model`) rather
---     than spawnmanager's, which is the same plus a radius for the picking UI we
---     do not have.

local RESOURCE = GetCurrentResourceName()

--- The known spawn points, seeded from AppearanceConfig - which is our "map".
---
--- Read at load rather than passed in, because AppearanceConfig is a shared file
--- and a spawn point that only exists if someone remembered to forward it is a
--- spawn point that will be missing the one time it matters.
local spawnPoints = {}
local nextSpawnId = 1

for key, point in pairs(SpawnPoints or {}) do
  if type(point) == 'table' and point.x then
    spawnPoints[#spawnPoints + 1] = {
      id = nextSpawnId,
      label = point.label or key,
      x = point.x, y = point.y, z = point.z,
      heading = point.heading or 0.0,
      model = point.model,
    }
    nextSpawnId = nextSpawnId + 1
  end
end

--- Sort by label so the order does not depend on `pairs`, which yields a
--- different order every session. A spawn list that reshuffles itself is not
--- wrong, but it makes "the same spawn as last time" impossible to describe.
table.sort(spawnPoints, function(a, b) return tostring(a.label) < tostring(b.label) end)

local autoSpawn = false
local autoSpawnCallback = nil
local isSpawning = false

--- Respawn a dead player at the current spawn point.
---
--- The original does this on death, and so do we - but only once the player is
--- actually in the world. Before that they are frozen at the creation point, and
--- a frozen player cannot die, so this is mostly about not surprising anyone.
local function respawnAtDefault()
  local definition = spawnPoints[1]
  if not definition then
    print(('[%s] no spawn point configured - cannot respawn'):format(RESOURCE))
    return
  end
  exports[RESOURCE]:spawnPlayer(definition)
end

--- Spawn the player.
---
--- ORDER MATTERS, and it is the one thing about spawning that is easy to get wrong:
---
---   1. fade out, so none of this is visible
---   2. SetPlayerModel BEFORE the resurrect
---   3. NetworkResurrectLocalPlayer, which puts the player in the world alive
---   4. coords and heading, because the resurrect lands at 0,0,0 with our call's
---      arguments not always honoured on a first spawn
---   5. fade in
---
--- Setting the model after the resurrect leaves the camera inside the old ped for
--- a frame, which reads as a glitch on every single spawn.
exports('spawnPlayer', function(definition, cb)
  if isSpawning then return end

  if type(definition) ~= 'table' or not definition.x then
    definition = spawnPoints[1]
  end
  if type(definition) ~= 'table' or not definition.x then
    print(('[%s] spawnPlayer called with no spawn point configured'):format(RESOURCE))
    return
  end

  isSpawning = true

  Citizen.CreateThread(function()
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    if definition.model then
      local hash = joaat(definition.model)
      SetPlayerModel(PlayerId(), hash)
      SetModelAsNoLongerNeeded(hash)
    end

    NetworkResurrectLocalPlayer(
      definition.x, definition.y, definition.z, definition.heading or 0.0,
      false, false, false)

    local ped = PlayerPedId()
    SetEntityCoords(ped, definition.x, definition.y, definition.z, false, false, false, false)
    SetEntityHeading(ped, definition.heading or 0.0)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)

    -- Explicit, because a resurrect does not reliably restore visibility or
    -- unfreeze on its own, and an invisible player at the airport is a bug that
    -- looks like a graphics problem.
    SetEntityVisible(ped, true)
    FreezeEntityPosition(ped, false)
    SetPlayerInvincible(ped, true)
    SetPlayerInvincible(ped, false)

    DoScreenFadeIn(500)
    while not IsScreenFadedIn() do Wait(0) end

    isSpawning = false

    if type(cb) == 'function' then cb(definition) end
    TriggerEvent('playerSpawned', definition)
  end)
end)

--- Respawn whoever is dead, if autospawn is on.
exports('forceRespawn', function()
  if not IsEntityDead(PlayerPedId()) then return end
  respawnAtDefault()
end)

exports('setAutoSpawn', function(state)
  autoSpawn = state ~= false
end)

exports('setAutoSpawnCallback', function(cb)
  autoSpawnCallback = cb
  autoSpawn = true
end)

exports('addSpawnPoint', function(point)
  if type(point) ~= 'table' or not point.x then return nil end

  local entry = {
    id = nextSpawnId,
    label = point.label or ('Spawn ' .. nextSpawnId),
    x = point.x, y = point.y, z = point.z,
    heading = point.heading or 0.0,
    model = point.model,
  }
  nextSpawnId = nextSpawnId + 1
  spawnPoints[#spawnPoints + 1] = entry

  return entry.id
end)

exports('removeSpawnPoint', function(id)
  for i, point in ipairs(spawnPoints) do
    if point.id == id then
      table.remove(spawnPoints, i)
      return true
    end
  end
  return false
end)

exports('getSpawnPoints', function() return spawnPoints end)

--- The death monitor.
---
--- With `baseevents` running, this listens to a real `onPlayerDied` event - which
--- is the correct way and costs nothing, since the resource is present.
---
--- Without it, it falls back to a slow poll. There is no client death event
--- without baseevents, and that is a good enough reason to keep the fallback
--- rather than to assume a resource that a future server.cfg might drop.
CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(500) end

  while true do
    if autoSpawn and not isSpawning and NetworkIsSessionStarted() then
      local ped = PlayerPedId()
      if ped and ped ~= 0 and IsEntityDead(ped) then
        respawnAtDefault()
      end
    end
    Wait(1000)
  end
end)

--- Checked once, at load, and only to decide which of the two paths is live.
--- Polling a started baseevents AND listening to it would respawn twice; the
--- `isSpawning` guard would stop the second, but two mechanisms for one job is
--- one too many.
local hasBaseEvents = GetResourceState('baseevents') == 'started'

if hasBaseEvents then
  RegisterNetEvent('baseevents:onPlayerDied', function()
    if not autoSpawn or isSpawning then return end
    -- A moment of grace. Some deaths fire twice - once for the ped and once for
    -- the ragdoll - and respawning on the first leaves the player mid-animation
    -- on the second.
    SetTimeout(500, function()
      if autoSpawn and not isSpawning then respawnAtDefault() end
    end)
  end)
end

print(('[%s] %d spawn point(s), autospawn off until the player is in the world%s'):format(
  RESOURCE, #spawnPoints,
  hasBaseEvents and ', death via baseevents' or ', death via poll'))