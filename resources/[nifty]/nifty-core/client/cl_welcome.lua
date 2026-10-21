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

  -- THE GENDER COMES FROM THE PED, NOT FROM THE STRING.
  --
  -- Rockstar decides the playback list by the ped MODEL (fm_intro_cut_dev.c
  -- func_91: `mp_f_freemode_01` plays the female half), and the same model
  -- decides which character slot the player sits in. The stored gender is a
  -- fact about the PLAYER, not about the body - and for 'nonbinary' the
  -- server takes the model from the creator, because "the gender is a fact
  -- about the player and the model is a fact about the body" (sv_main.lua).
  -- The two can therefore disagree, and then the string would pick the wrong
  -- half of the video and the wrong character slot.
  --
  -- The string is only the fallback for a ped that is neither freemode model.
  local pedModel = GetEntityModel(ped)
  local isMale
  if pedModel == joaat('mp_f_freemode_01') then
    isMale = false
  elseif pedModel == joaat('mp_m_freemode_01') then
    isMale = true
  else
    isMale = (gender ~= 'female')
  end

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

  -- BLACK FIRST. EVERYTHING BELOW HAPPENS BEHIND A BLACK SCREEN.
  --
  -- What follows puts the player somewhere else, fills the cabin with seven
  -- people and parks a jet 142 metres up. The player used to watch that
  -- happen: they stood VISIBLY on the beach at PRE_POS while the passengers
  -- popped into existence at their own feet, and the cutscene started from
  -- that picture. From here to the fade-in after `StartCutscene` the screen
  -- stays black.
  DoScreenFadeOut(500)
  Wait(600)

  -- Player has to be alive and visible for the cutscene to register them.
  -- Invincibility keeps the cutscene from killing them if the cutscene
  -- ends near an edge of the map.
  SetPlayerInvincible(PlayerId(), true)
  SetEntityVisible(ped, true)

  -- Park the player at a neutral position so the transition into the
  -- cutscene is not visible. The cutscene puts the camera wherever
  -- its own scripts decide.
  SetEntityCoords(ped, PRE_POS.x, PRE_POS.y, PRE_POS.z, false, false, false, false)

  -- THE MODELS ARE LOADED ONCE, NOT ONCE PER SEAT.
  --
  -- The old code requested the model of every single seat and waited for it,
  -- with a ten second deadline EACH - seven seats, and a second model as the
  -- fallback, so up to 140 seconds before the cutscene even started.
  --
  -- That is not a slow start, it is a race with the server: the watchdog in
  -- sv_main.lua fires after 60 seconds and sends the world entry. The player
  -- was therefore teleported into the city AND the cutscene started
  -- afterwards, one after the other.
  --
  -- Three models, one wait each, a budget per model and a cache. The cache is
  -- what makes the second seat of the same gender free.
  local loadedModels = {}
  local function ensureModel(name, budgetMs)
    local hash = joaat(name)
    if loadedModels[hash] then return loadedModels[hash] end
    if HasModelLoaded(hash) then
      loadedModels[hash] = hash
      return hash
    end

    RequestModel(hash)
    local deadline = GetGameTimer() + budgetMs
    while not HasModelLoaded(hash) do
      if GetGameTimer() > deadline then return 0 end
      Wait(0)
    end

    loadedModels[hash] = hash
    return hash
  end

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
    local hash = ensureModel(model, 6000)

    -- A PLACE OF THEIR OWN, so they do not stand in the player.
    local offsetX = (index - 4) * 0.6

    local created = 0
    if hash ~= 0 then
      created = CreatePed(26, hash, PRE_POS.x + offsetX, PRE_POS.y, PRE_POS.z, 0.0, false, false)
    end

    if created and created ~= 0 then
      SetModelAsNoLongerNeeded(hash)
      -- INVISIBLE UNTIL THE CUTOISCENE TAKES THE SEAT.
      --
      -- A ped that is created visible stands at the spawn point until the
      -- cutscene moves it into the cabin - and the cutscene's own camera sees
      -- the world from its first frame, whatever the player's screen does.
      SetEntityVisible(created, false, false)
      -- A mission entity is not cleaned up by the streaming system while the
      -- cutscene is still being set up. The community ports all do this.
      SetEntityAsMissionEntity(created, true, true)
      passengers[#passengers + 1] = created
    else
      -- THE FALLBACK.
      --
      -- The NPC model is not available. Rather than an empty seat, the seat is
      -- filled with the freemode model of that seat's gender - in the suit
      -- Rockstar's passengers wear. Still not the player: different clothes,
      -- and a head that is not the player's head.
      --
      -- The freemode is usually ALREADY in memory - the player wears one -
      -- so this fallback costs nothing.
      local fallbackModel = (index <= 3) and 'mp_m_freemode_01' or 'mp_f_freemode_01'
      local fallbackHash = ensureModel(fallbackModel, 3000)

      local fallback = 0
      if fallbackHash ~= 0 then
        fallback = CreatePed(26, fallbackHash, PRE_POS.x + offsetX, PRE_POS.y, PRE_POS.z, 0.0, false, false)
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
        SetEntityVisible(fallback, false, false)
        SetEntityAsMissionEntity(fallback, true, true)
        passengers[#passengers + 1] = fallback
        print(('[nifty-core] the model "%s" for seat %d is not available - the seat gets the suit instead'):format(
          model, index))
      else
        print(('[nifty-core] neither the model "%s" nor the suit for seat %d could be created - the seat stays empty'):format(
          model, index))
      end
    end
  end

  -- THE JET.
  --
  -- The plane the whole video is about. Its model is loaded FIRST: an object
  -- whose model is not in memory comes back as 0, and the slot 'MP_Plane'
  -- would then be empty - the video without a plane, and nothing in the log
  -- to say so.
  local jet = 0
  local jetModel = ensureModel('p_cs_mp_jet_01_s', 6000)
  if jetModel ~= 0 then
    jet = CreateObject(JET_HASH, JET_POS.x, JET_POS.y, JET_POS.z, false, true, false)
    SetModelAsNoLongerNeeded(JET_HASH)
  end
  if jet ~= 0 then
    -- It starts INVISIBLE and is made visible when it is registered: at its
    -- spawn point, 142 metres up, it would otherwise hang in the sky while the
    -- cutscene loads.
    SetEntityVisible(jet, false, false)
    SetEntityLodDist(jet, 3000)
  else
    print(('[nifty-core] the jet model is not available - the video has no plane'):format())
  end

  -- THE CLEANUP, IN ONE PLACE.
  --
  -- Two paths leave this handler: the cutscene ended, and the cutscene never
  -- came. Both have to remove the jet, the passengers and the load scene -
  -- otherwise the plane stays in the sky and seven people stay in the world.
  --
  -- It is one function because it used to be written twice, and the two
  -- copies were not the same: the fallback path forgot the load scene.
  local function cleanUp()
    if DoesEntityExist(jet) then DeleteEntity(jet) end
    for _, p in ipairs(passengers) do
      if DoesEntityExist(p) then DeleteEntity(p) end
    end
    NewLoadSceneStop()
  end

  -- THE LOAD SCENE.
  --
  -- The jet is 142 metres up and a few hundred metres off the coast. Without
  -- a load scene, that corner of the world is not streamed in, and the plane
  -- the whole video is about simply is not there.
  --
  -- The coordinates are the ones from Rockstar's own script, so the sphere
  -- covers the place the cutscene actually uses.
  NewLoadSceneStartSphere(-1212.79, -1673.52, 7.0, 1000.0, 0)

  -- The screen has been black since the beginning of this handler. What is
  -- left: request the cutscene, wait for it to load, register the entities in
  -- their cutscene slots, then start it.

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
      cleanUp()
      SetPlayerInvincible(PlayerId(), false)
      enterTheWorld()
      return
    end
    Wait(0)
  end

  -- THE JET, IF IT EXISTS.
  if jet ~= 0 then
    SetEntityVisible(jet, true, false)
    RegisterEntityForCutscene(jet, 'MP_Plane', 0, 0, 0)
    SetCutsceneEntityStreamingFlags('MP_Plane', 0, 1)
  end

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
      -- They become visible HERE and not before: the cutscene's own camera
      -- sees the world from its first frame, and a visible ped that is not
      -- yet in its seat stands in the open.
      SetEntityVisible(passenger, true, false)
      RegisterEntityForCutscene(passenger, slot, 0, 0, 64)
      SetCutsceneEntityStreamingFlags(slot, 0, 1)
    end
  end

  if jet ~= 0 then
    SetEntityAsMissionEntity(jet, true, true)
  end

  -- THE SERVER IS TOLD THAT THE VIDEO IS RUNNING.
  --
  -- The world entry is the client's job while the cutscene plays, and the
  -- server has a watchdog that sends the world entry if nobody reports it. The
  -- watchdog's short deadline is meant for a cutscene that never arrives - not
  -- for one that is playing right now. Without this signal it fired in the
  -- middle of the video and teleported the player into the city, and then the
  -- cutscene ended and did it again.
  TriggerServerEvent('nifty:server:cutsceneRunning')

  StartCutscene(START_FLAGS)
  DoScreenFadeIn(500)

  -- Cutscene runs to its end. Watch for IsCutsceneActive to flip
  -- false, then stop, fade out, and trigger the normal world entry.
  CreateThread(function()
    -- IT HAS TO START.
    --
    -- The old code waited for `IsCutsceneActive()` without a deadline. If the
    -- cutscene never started, the thread spun forever and the only thing that
    -- rescued the player was the server's watchdog - a minute of black screen
    -- for a cutscene that was never going to run.
    local startDeadline = GetGameTimer() + 10000
    while not IsCutsceneActive() do
      if GetGameTimer() > startDeadline then
        print(('[nifty-core] the cutscene did not start - the world entry is sent directly'):format())
        StopCutsceneImmediately()
        cleanUp()
        SetPlayerInvincible(PlayerId(), false)
        enterTheWorld()
        return
      end
      Wait(100)
    end

    while IsCutsceneActive() do Wait(100) end
    StopCutsceneImmediately()

    -- THE PED IS HANDED BACK.
    --
    -- A ped that was registered for a cutscene can stay under the cutscene's
    -- control: invisible, frozen, or not accepting input. The pre-welcome
    -- hook froze it as well, and nothing in the project unfroze it again.
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetPlayerInvincible(PlayerId(), false)

    DoScreenFadeOut(500)
    Wait(600)
    cleanUp()
    enterTheWorld()
  end)
end)
