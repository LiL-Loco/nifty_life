--[[
  The "mp_intro_concat" welcome cutscene.

  Plays once, right after the character creator finishes, before the
  world is loaded. Concat is the CEO (organization) onboarding cutscene
  in GTA Online - a cinematic of the new character flying in a jet over
  Los Santos at sunset. It works here for any player (not just CEOs) and
  is short enough (~26s) to not feel like a barrier.

  After the cutscene ends, the client triggers the standard
  nifty:client:enterWorld so the rest of the post-creation flow runs
  exactly the same as it does for any other character login.

  No on-screen text. The original JS implementation in client_packages/
  drew a welcome message between t=12s and t=22s; that text is gone
  here. The cutscene is a cinematic, not an info card.
]]

local cutsceneName = 'mp_intro_concat'
local JET_HASH = `p_cs_mp_jet_01_s`
local JET_POS = vector3(-1200.0, -1490.0, 142.385)
local PRE_POS = vector3(-1117.778, -1557.625, 3.3819)

RegisterNetEvent('nifty:client:welcomeCutscene', function(data)
  local ped = PlayerPedId()
  local gender = data and data.gender or 'male'
  local isMale = (gender ~= 'female')

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
      TriggerEvent('nifty:client:enterWorld', { skipCutscene = true })
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
    TriggerEvent('nifty:client:enterWorld', { skipCutscene = true })
  end)
end)
