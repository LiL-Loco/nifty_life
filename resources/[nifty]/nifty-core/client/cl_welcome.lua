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

-- ---------------------------------------------------------------------------
-- The cutscene, and what is actually in it.
--
-- Everything below was taken from ROCKSTAR'S OWN SCRIPT for this cutscene -
-- the decompiled `fm_intro_cut.c` from the GTA-V-Decompiled-Scripts project -
-- and cross-checked against four independent community ports of the same
-- cutscene (not-a-script/ns-online-introduction, hhfw1/cs_firstspawn,
-- BX-DEV-FIVEM/BX-Intro, ragemp-pro/streetrp). Nothing here is a guess.
--
-- THE CUTSCENE NAME IS UPPERCASE: `MP_INTRO_CONCAT`. The lowercase spelling
-- in the old code was never the name of anything.
local cutsceneName = 'MP_INTRO_CONCAT'

-- THE GENDER IS A PLAYBACK LIST, not a flag.
--
-- The cutscene has a list of playback flags, and Rockstar picks ONE of them
-- depending on the player's gender: 31 for male, 103 for female. Both with
-- the playback flags 8. The old code called `RequestCutscene(name, 8)` - no
-- list at all - so the game played its DEFAULT list, and the default list
-- contains BOTH: first the male montage, then the female one. That is
-- exactly what the player reported: a video whose end plays the male
-- character and then the female character, no matter who logged in.
--
-- With the list, only the half that belongs to the character is played.
local SECTION_MALE = 31
local SECTION_FEMALE = 103
local PLAYBACK_FLAGS = 8

-- Rockstar starts the cutscene with the flag 4. The old code used 0.
local START_FLAGS = 4

-- The seven passenger seats in the plane.
--
-- These are the real slot names of the cutscene, from Rockstar's script
-- (func_88 / func_87). The old code registered NONE of them, which is why
-- the passengers were whatever the engine made of the baked cutscene
-- entities - and why they looked like the player's own character.
local PASSENGER_SLOTS = {
  'MP_Plane_Passenger_1',
  'MP_Plane_Passenger_2',
  'MP_Plane_Passenger_3',
  'MP_Plane_Passenger_4',
  'MP_Plane_Passenger_5',
  'MP_Plane_Passenger_6',
  'MP_Plane_Passenger_7',
}

-- WHO SITS IN WHICH SEAT.
--
-- An ordinary person in a suit, not a copy of the player: that is what the
-- player asked for, and it is also what the plane is for. The seats keep the
-- original casting - the first three are male, the last four female - so the
-- cabin does not look lopsided.
--
-- If a model cannot be created, the seat stays empty and the log says so.
-- An empty seat is honest; a seat with a copy of the player in it is not.
local PASSENGER_MODELS = {
  'a_m_m_business_01', 'a_m_m_business_01', 'a_m_m_business_01',
  'a_f_m_business_01', 'a_f_m_business_01', 'a_f_m_business_01',
  'a_f_m_business_01',
}

-- THE FALLBACK OUTFIT.
--
-- If an NPC model is not available, the seat is filled with the freemode model
-- of that seat's gender - but in the suit ROCKSTAR puts its passengers in.
-- The point of the fallback is that the passenger still does not look like the
-- player: different clothes, and a head that is not the player's head.
--
-- These are the component variations from Rockstar's own script (the outfit
-- table there, one row per seat, one pair per component: drawable and
-- texture). Same numbers in all four community ports.
local PASSENGER_OUTFITS = {
  { [0] = { 21, 0 }, [1] = { 0, 0 }, [2] = { 9, 0 },  [3] = { 1, 0 },  [4] = { 9, 0 },  [5] = { 0, 0 }, [6] = { 4, 8 },   [7] = { 0, 0 },  [8] = { 15, 0 }, [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 10, 0 } },
  { [0] = { 13, 0 }, [1] = { 0, 0 }, [2] = { 5, 4 },  [3] = { 1, 0 },  [4] = { 10, 0 }, [5] = { 0, 0 }, [6] = { 10, 0 }, [7] = { 11, 2 }, [8] = { 13, 6 }, [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 10, 0 } },
  { [0] = { 15, 0 }, [1] = { 0, 0 }, [2] = { 1, 4 },  [3] = { 1, 0 },  [4] = { 0, 1 },  [5] = { 0, 0 }, [6] = { 1, 7 },   [7] = { 0, 0 },  [8] = { 2, 9 },  [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 6, 0 } },
  { [0] = { 14, 0 }, [1] = { 0, 0 }, [2] = { 5, 3 },  [3] = { 3, 0 },  [4] = { 1, 6 },  [5] = { 0, 0 }, [6] = { 11, 5 }, [7] = { 0, 0 },  [8] = { 2, 0 },  [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 3, 12 } },
  { [0] = { 18, 0 }, [1] = { 0, 0 }, [2] = { 15, 3 }, [3] = { 15, 0 }, [4] = { 2, 5 },  [5] = { 0, 0 }, [6] = { 4, 6 },   [7] = { 4, 0 },  [8] = { 3, 0 },  [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 4, 0 } },
  { [0] = { 27, 0 }, [1] = { 0, 0 }, [2] = { 7, 3 },  [3] = { 11, 0 }, [4] = { 4, 8 },  [5] = { 0, 0 }, [6] = { 13, 14 },[7] = { 5, 3 },  [8] = { 3, 0 },  [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 2, 7 } },
  { [0] = { 16, 0 }, [1] = { 0, 0 }, [2] = { 15, 1 }, [3] = { 3, 0 },  [4] = { 5, 6 },  [5] = { 0, 0 }, [6] = { 2, 8 },   [7] = { 0, 0 },  [8] = { 2, 0 },  [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 3, 7 } },
}

-- The two character slots of the cutscene.
local MALE_SLOT = 'MP_Male_Character'
local FEMALE_SLOT = 'MP_Female_Character'

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

  -- THE PASSENGERS.
  --
  -- Seven ordinary people in the cabin, one per seat, each in its own slot.
  -- They are created here and registered BEFORE the cutscene starts, so the
  -- cutscene animates THEM and not the baked entities.
  --
  -- `CreatePed` returns 0 when the model is not available. The seat then
  -- stays empty - and the log says so, because an empty seat and a seat with
  -- a copy of the player in it are not the same thing.
  local passengers = {}
  for index, model in ipairs(PASSENGER_MODELS) do
    local hash = joaat(model)

    -- THE MODEL HAS TO BE LOADED BEFORE THE PED IS CREATED.
    --
    -- `CreatePed` with a model that is not streamed in does not raise - it
    -- hands back nothing usable, and the seat stays empty without a word.
    -- The model is requested and waited for, with a deadline: a wait without
    -- a deadline is a hang.
    RequestModel(hash)
    local modelDeadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
      if GetGameTimer() > modelDeadline then break end
      Wait(0)
    end

    local created = 0
    if HasModelLoaded(hash) then
      created = CreatePed(26, hash, PRE_POS.x, PRE_POS.y, PRE_POS.z, 0.0, false, false)
    end

    if created and created ~= 0 then
      SetModelAsNoLongerNeeded(hash)
      passengers[#passengers + 1] = created
    else
      -- THE FALLBACK.
      --
      -- The NPC model is not available. Rather than an empty seat, the seat is
      -- filled with the freemode model of that seat's gender - in the suit
      -- Rockstar's passengers wear. Still not the player: different clothes,
      -- and a head that is not the player's head.
      local fallbackModel = (index <= 3) and 'mp_m_freemode_01' or 'mp_f_freemode_01'
      local fallbackHash = joaat(fallbackModel)
      RequestModel(fallbackHash)
      local fallbackDeadline = GetGameTimer() + 10000
      while not HasModelLoaded(fallbackHash) do
        if GetGameTimer() > fallbackDeadline then break end
        Wait(0)
      end

      local fallback = 0
      if HasModelLoaded(fallbackHash) then
        fallback = CreatePed(26, fallbackHash, PRE_POS.x, PRE_POS.y, PRE_POS.z, 0.0, false, false)
      end

      if fallback and fallback ~= 0 then
        SetModelAsNoLongerNeeded(fallbackHash)
        local outfit = PASSENGER_OUTFITS[index]
        if outfit then
          for component = 0, 11 do
            local variation = outfit[component]
            if variation then
              SetPedComponentVariation(fallback, component, variation[1], variation[2], 0)
            end
          end
        end
        for prop = 0, 8 do ClearPedProp(fallback, prop) end
        FinalizeHeadBlend(fallback)
        passengers[#passengers + 1] = fallback
        print(('[nifty-core] the model "%s" for seat %d is not available - the seat gets the suit instead'):format(
          model, index))
      else
        print(('[nifty-core] neither the model "%s" nor the suit for seat %d could be created - the seat stays empty'):format(
          model, index))
      end
    end
  end

  -- The jet object the cutscene attaches to the plane. CreateObject
  -- streams the model in if it is not already loaded.
  --
  -- It starts INVISIBLE and is made visible when it is registered: at its
  -- spawn point, 142 metres up, it would otherwise hang in the sky while the
  -- cutscene loads.
  local jet = CreateObject(JET_HASH, JET_POS.x, JET_POS.y, JET_POS.z, false, true, false)
  SetModelAsNoLongerNeeded(JET_HASH)
  SetEntityVisible(jet, false, false)
  SetEntityLodDist(jet, 3000)

  -- THE LOAD SCENE.
  --
  -- The jet is 142 metres up and a few hundred metres off the coast. Without
  -- a load scene, that corner of the world is not streamed in, and the plane
  -- the whole video is about simply is not there.
  --
  -- The coordinates are the ones from Rockstar's own script, so the sphere
  -- covers the place the cutscene actually uses.
  NewLoadSceneStartSphere(-1212.79, -1673.52, 7.0, 1000.0, 0)

  -- Fade out, request the cutscene, wait for it to load, register the
  -- entities in their cutscene slots, then start it.
  DoScreenFadeOut(500)
  Wait(600)

  -- THE PLAYBACK LIST IS THE GENDER.
  --
  -- `RequestCutsceneWithPlaybackList(name, playbackFlags, flags)`: the middle
  -- argument is the section to play (31 = male, 103 = female), the last one
  -- is the playback flags (8).
  --
  -- The old code called `RequestCutscene(name, 8)` - without a list - and the
  -- game then played its default list, which contains BOTH sections. That is
  -- why the video ended with the male character and then the female one.
  local section = isMale and SECTION_MALE or SECTION_FEMALE
  RequestCutsceneWithPlaybackList(cutsceneName, section, PLAYBACK_FLAGS)

  local deadline = GetGameTimer() + 15000
  while not HasCutsceneLoaded() do
    if GetGameTimer() > deadline then
      -- Cutscene didn't load in 15s (asset missing or build-different).
      -- Fall through to the standard world entry; the picker is still
      -- available, just without the cinematic lead-in.
      print(('[nifty-core] cutscene "%s" failed to load, falling back to plain world entry'):format(cutsceneName))
      if DoesEntityExist(jet) then DeleteEntity(jet) end
      for _, p in ipairs(passengers) do
        if DoesEntityExist(p) then DeleteEntity(p) end
      end
      NewLoadSceneStop()
      SetPlayerInvincible(PlayerId(), false)
      enterTheWorld()
      return
    end
    Wait(0)
  end

  SetEntityVisible(jet, true, false)
  RegisterEntityForCutscene(jet, 'MP_Plane', 0, 0, 0)
  SetCutsceneEntityStreamingFlags('MP_Plane', 0, 1)

  -- THE PLAYER THEMSELVES.
  --
  -- Rockstar registers the player's OWN ped, not a copy of it. The old code
  -- cloned - and cloned it wrong: `ClonePed(ped, isNetwork, bScriptHostPed,
  -- copyHeadBlendFlag)`, so the heading ended up in the `isNetwork` slot and
  -- the clone was created as a NETWORK ped. Registering the real ped removes
  -- the clone altogether.
  local ownSlot = isMale and MALE_SLOT or FEMALE_SLOT
  local otherSlot = isMale and FEMALE_SLOT or MALE_SLOT
  local otherModel = isMale and 'mp_f_freemode_01' or 'mp_m_freemode_01'

  RegisterEntityForCutscene(ped, ownSlot, 0, 0, 0)
  SetCutsceneEntityStreamingFlags(ownSlot, 0, 1)

  -- The slot of the OTHER gender: entity 0 with the model of the other
  -- freemode ped. Rockstar does exactly this, so the cutscene's animation
  -- for that slot fits the model it finds there.
  RegisterEntityForCutscene(0, otherSlot, 3, joaat(otherModel), 0)

  -- The passengers, one per seat.
  --
  -- The last argument of `RegisterEntityForCutscene` is 64 for the
  -- passenger slots - "ignore the model" - and 0 for the player and the
  -- plane. The old code used 0 everywhere.
  for index, passenger in ipairs(passengers) do
    local slot = PASSENGER_SLOTS[index]
    if slot then
      RegisterEntityForCutscene(passenger, slot, 0, 0, 64)
      SetCutsceneEntityStreamingFlags(slot, 0, 1)
    end
  end

  SetEntityAsMissionEntity(jet, true, true)

  StartCutscene(START_FLAGS)
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
    for _, p in ipairs(passengers) do
      if DoesEntityExist(p) then DeleteEntity(p) end
    end
    NewLoadSceneStop()
    SetPlayerInvincible(PlayerId(), false)
    enterTheWorld()
  end)
end)
