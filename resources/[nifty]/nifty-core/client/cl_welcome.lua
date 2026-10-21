--[[
  The welcome flow.

  Two parts:
    1. The pre-welcome hook (`playerSpawned`). The instant a player
       exists, this fades the screen to black and parks the ped at
       CreatorScene. Without this, the player sees the Cfx-config default
       spawn (Legion, Vespucci or Paleto) for a tick before the server
       tells the client what to do next — which is the opposite of
       "first time, in the creator".
    2. The "mp_intro_concat" welcome cutscene. Plays once, right after
       the character creator finishes, before the world is loaded.
       Concat is the CEO (organization) onboarding cutscene in GTA
       Online - a cinematic of the new character flying in a jet over
       Los Santos at sunset. It works here for any player (not just
       CEOs) and is short enough (~26s) to not feel like a barrier.
]]

-- Pre-welcome hook: blackout + park.

-- `playerSpawned` fires for every spawn this client sees, including
-- death respawns later in the session. The pre-welcome behaviour only
-- belongs on the FIRST spawn; subsequent ones are world respawns which
-- spawnmanager handles. The flag short-circuits all later invocations.
local firstSpawn = true

AddEventHandler('playerSpawned', function()
  if not firstSpawn then return end
  firstSpawn = false

  -- Instant fade to black. Anything after this is invisible until one of
  -- the two paths below explicitly calls `DoScreenFadeIn`:
  --   * creator (fresh player) → `startCamera` in nifty-creator
  --   * world   (returning)    → `doEnterWorldSpawn` in nifty-world
  -- The hook does NOT pick between them — the server does, ~50-500 ms
  -- later, via `nifty:client:openCreator` or `nifty:client:enterWorld`.
  DoScreenFadeOut(0)
  print(('[FADE-ORDER] t=%d playerSpawned handler: DoScreenFadeOut(0)'):format(GetGameTimer()))
  while not IsScreenFadedOut() do Wait(0) end
  print(('[FADE-ORDER] t=%d playerSpawned handler: now faded out'):format(GetGameTimer()))

  -- Park at the creator stage. CreatorScene is loaded as a shared
  -- script, so it is available wherever nifty-core runs. Freezing
  -- prevents a death-from-falling during the wait for the server.
  local scene = CreatorScene
  if scene then
    local ped = PlayerPedId()
    SetEntityCoords(ped, scene.x, scene.y, scene.z, false, false, false, false)
    SetEntityHeading(ped, scene.heading)
    FreezeEntityPosition(ped, true)
  end
end)

local cutsceneName = 'mp_intro_concat'
local JET_HASH = `p_cs_mp_jet_01_s`
local JET_POS = vector3(-1200.0, -1490.0, 142.385)
local PRE_POS = vector3(-1117.778, -1557.625, 3.3819)

RegisterNetEvent('nifty:client:welcomeCutscene', function(data)
  local ped = PlayerPedId()
  local gender = data and data.gender or 'male'
  local isMale = (gender ~= 'female')

  -- The world payload, handed over by the server.
  --
  -- The cutscene ENDS the world entry: it fires `nifty:client:enterWorld`
  -- with this payload when the video is over, so that the player walks into
  -- the world AFTER the video and not before it. Without the payload the
  -- client handler reads `data.character.appearance` and dies on a nil index,
  -- and the player is left on a black screen.
  local world = data and data.world or nil

  --- The world entry, with the payload - or without one, if the server did
  --- not send it. A missing payload must not be a crash: the alternative is a
  --- black screen with no way out.
  local function enterTheWorld()
    if type(world) == 'table' then
      TriggerEvent('nifty:client:enterWorld', world)
    else
      print(('[nifty-core] the cutscene got no world payload - the world entry is skipped'):format())
    end
  end

  -- Player has to be alive and visible for the cutscene to register them.
  -- Invincibility keeps the cutscene from killing them if the cutscene
  -- ends near an edge of the map.
  SetPlayerInvincible(PlayerId(), true)
  SetEntityVisible(ped, true)

  -- Park the player at a neutral position so the transition into the
  -- cutscene is not visible. The cutscene puts the camera wherever
  -- its own scripts decide.
  SetEntityCoords(ped, PRE_POS.x, PRE_POS.y, PRE_POS.z, false, false, false, false)

  -- A clone of the player is what the cutscene's "MP_Male_Character" /
  -- "MP_Female_Character" entity slot expects.
  local clone = ClonePed(ped, GetEntityHeading(ped), false, false)

  -- The jet object the cutscene attaches to the plane. CreateObject
  -- streams the model in if it is not already loaded.
  local jet = CreateObject(JET_HASH, JET_POS.x, JET_POS.y, JET_POS.z, false, true, false)
  SetModelAsNoLongerNeeded(JET_HASH)

  -- Fade out, request the cutscene, wait for it to load, register the
  -- entities in their cutscene slots, then start it.
  DoScreenFadeOut(500)
  Wait(600)

  RequestCutscene(cutsceneName, 8)

  local deadline = GetGameTimer() + 15000
  while not HasThisCutsceneLoaded(cutsceneName) do
    if GetGameTimer() > deadline then
      -- Cutscene didn't load in 15s (asset missing or build-different).
      -- Fall through to the standard world entry; the picker is still
      -- available, just without the cinematic lead-in.
      print(('[nifty-core] cutscene "%s" failed to load, falling back to plain world entry'):format(cutsceneName))
      if DoesEntityExist(jet) then DeleteEntity(jet) end
      if DoesEntityExist(clone) then DeleteEntity(clone) end
      SetPlayerInvincible(PlayerId(), false)
      enterTheWorld()
      return
    end
    Wait(0)
  end

  RegisterEntityForCutscene(jet, 'MP_Plane', 0, 0, 0)

  -- The cutscene has a default male and a default female NPC in its
  -- bank. Put the player's clone in the gender slot; the other side
  -- is unused.
  if isMale then
    RegisterEntityForCutscene(clone, 'MP_Male_Character', 0, 0, 0)
  else
    RegisterEntityForCutscene(clone, 'MP_Female_Character', 0, 0, 0)
  end
  SetEntityAsMissionEntity(jet, true, true)

  StartCutscene(0)
  DoScreenFadeIn(500)

  -- Cutscene runs to its end. Watch for IsCutsceneActive to flip
  -- false, then stop, fade out, and trigger the normal world entry.
  CreateThread(function()
    while not IsCutsceneActive() do Wait(100) end
    while IsCutsceneActive() do Wait(100) end
    StopCutsceneImmediately()
    DoScreenFadeOut(500)
    Wait(600)
    if DoesEntityExist(jet) then DeleteEntity(jet) end
    if DoesEntityExist(clone) then DeleteEntity(clone) end
    SetPlayerInvincible(PlayerId(), false)
    enterTheWorld()
  end)
end)
