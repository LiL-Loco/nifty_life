--[[
  TEMPORARY PROBE — what is actually inside the welcome cutscene?

  REMOVE AFTER MEASURING. It is a probe, not a feature: it reports facts about
  the game to the server log and does nothing else.

  WHAT IT MEASURES
  ----------------
    M1  Which entity is in which cutscene slot? The player sees the cabin
        filled with people. Are they the ones this project registered, or the
        baked entities the cutscene brought with it?
    M2  Where are the passengers? In the plane (z ~ 142) or on the ground
        (z ~ 3)? The old probe measured a three-dimensional distance and the
        ground was 139 metres away from the jet, so the answer was always
        "nobody near the plane".
    M3  Which half of the video plays? The playback list is the gender, and
        `IsCutscenePlaybackFlagSet` says directly which list is active: the
        male list is 31 (bits 1, 2, 4, 8, 16), the female one 103 (bits
        1, 2, 4, 32, 64). So the flags ARE the answer.
    M5  Does a passenger wear the player's clothes? The head component is
        compared, because a passenger with the player's head is the symptom
        the player reported.

  HOW IT REPORTS
  --------------
  Over `nifty:server:variationDiag`, because a client `print()` never reaches
  the server log. That channel drops everything above 300 characters and
  allows FOUR messages per ten seconds - silently, without a word.

  So the probe MEASURES FIRST and SENDS AFTERWARDS. Measuring is a handful of
  native calls, milliseconds in total; sending is the slow part. A probe that
  measures while it sends loses every fifth measurement, which is exactly what
  the first version of this file did.
]]

local PREFIX = '[nifty-core]'

--- One fact, one line, to the server log.
local function say(text)
  TriggerServerEvent('nifty:server:variationDiag', ('%s: %s'):format(PREFIX, text))
end

--- The pace the channel accepts.
---
--- The window is ten seconds and the budget is four messages, so 3.4 seconds
--- puts three or four into every window - never five. The old probe used
--- 2.2 seconds, which is five per window, and every fifth message was gone.
local SEND_INTERVAL_MS = 3400

--- The channel cuts a message at 300 characters. This splits a long line
--- into pieces that fit, at a word boundary.
local function chunks(text, size)
  local out, current = {}, ''
  for word in text:gmatch('%S+') do
    if #current + #word + 1 > size then
      out[#out + 1] = current
      current = word
    else
      current = (current == '') and word or (current .. ' ' .. word)
    end
  end
  if current ~= '' then out[#out + 1] = current end
  return out
end

--- The slots worth asking about.
---
--- The three known ones, plus the names the game's own naming scheme would
--- produce for the other passengers. A name that does not exist answers
--- false and costs nothing - the cutscene is already loaded when this runs.
local CANDIDATE_SLOTS = {
  'MP_Plane', 'MP_Male_Character', 'MP_Female_Character',
  'MP_Plane_Passenger_1', 'MP_Plane_Passenger_2', 'MP_Plane_Passenger_3',
  'MP_Plane_Passenger_4', 'MP_Plane_Passenger_5', 'MP_Plane_Passenger_6',
  'MP_Plane_Passenger_7',
}

--- The cutscene names worth asking about.
---
--- `mp_intro_concat` is a CONCATENATION, so the halves may be cutscenes of
--- their own. A name that does not exist never loads. Asking is safe:
--- `RequestCutscene` LOADS a cutscene, it does not play it - only
--- `StartCutscene` does. This runs at the very end, after the world entry.
local CANDIDATE_CUTSCENES = {
  'mp_intro_concat',
  'mp_intro', 'mp_intro_1', 'mp_intro_2', 'mp_intro_male', 'mp_intro_female',
  'mp_intro_ceo', 'intro_freemode', 'freemode_intro', 'intro_cutscene',
}

--- The models the player is most likely to see.
---
--- The freemode models are the character; the business models are the
--- passengers this project creates. Everything else is a hash - and a hash in
--- the log is a question, not an answer.
local function modelName(hash)
  if type(hash) ~= 'number' or hash == 0 then return '?' end
  if hash == joaat('mp_m_freemode_01') then return 'mp_m_freemode_01' end
  if hash == joaat('mp_f_freemode_01') then return 'mp_f_freemode_01' end
  if hash == joaat('a_m_m_business_01') then return 'a_m_m_business_01' end
  if hash == joaat('a_f_m_business_01') then return 'a_f_m_business_01' end
  return ('h%d'):format(hash)
end

--- The natives this probe depends on. If one is missing, the probe says so
--- instead of raising - a probe that crashes tells nobody anything.
local function available(name)
  return type(_G[name]) == 'function'
end

--- A native call that may not exist, with its result or nil.
local function try(name, ...)
  if not available(name) then return nil end
  local ok, result = pcall(_G[name], ...)
  if not ok then return nil end
  return result
end

CreateThread(function()
  -- 1. THE FACTS THAT DO NOT NEED THE CUTOISCENE, SENT FIRST.
  --
  -- The models and the cutscene names can be asked at any time - and they are
  -- asked FIRST, and sent straight away, because the client died twice before
  -- the cutscene even started. A probe that waits for the cutscene and only
  -- then measures reports nothing when the client crashes during the load.
  --
  -- The model facts are the ones that matter here: a model that is not in the
  -- CD image is waited for, until the deadline, and that wait is the visible
  -- "the scene takes forever to load".
  do
    local modelFacts = {}
    for _, model in ipairs({
      'mp_m_freemode_01', 'mp_f_freemode_01',
      'a_m_m_business_01', 'a_f_m_business_01',
      'p_cs_mp_jet_01_s',
    }) do
      local hash = joaat(model)
      modelFacts[#modelFacts + 1] = ('%s cd=%s valid=%s'):format(
        model, tostring(try('IsModelInCdimage', hash, true)),
        tostring(try('IsModelValid', hash)))
    end
    say('Modelle: ' .. table.concat(modelFacts, ' | '))
    Wait(SEND_INTERVAL_MS)
  end

  -- The cutscene names. Asking is safe: `RequestCutscene` LOADS a cutscene, it
  -- does not play it - only `StartCutscene` does. A name that exists is loaded
  -- and nothing happens; a name that does not exist never loads.
  --
  -- This runs before the cutscene starts, so the answer arrives even if the
  -- client dies during the load - and it warms the assets of the name that
  -- exists, which makes the cutscene itself load faster.
  for _, name in ipairs(CANDIDATE_CUTSCENES) do
    if available('HasThisCutsceneLoaded') then
      local ok = pcall(RequestCutscene, name, 8)
      local waitUntil = GetGameTimer() + 1500
      while GetGameTimer() < waitUntil and not HasThisCutsceneLoaded(name) do
        Wait(200)
      end
      if ok and HasThisCutsceneLoaded(name) then
        say(('PROBE cutscene %s EXISTIERT'):format(name))
        Wait(SEND_INTERVAL_MS)
      end
    end
  end
  say('PROBE Namen geprueft')

  -- 2. WAIT FOR THE CUTOISCENE.
  --
  -- The cutscene plays AFTER the character creator, and the creator takes as
  -- long as the player needs - minutes, with a face to choose. The first
  -- version of this probe gave the cutscene sixty seconds from the client's
  -- start and reported "the probe ran into the void" for every player who took
  -- their time in the creator. Fifteen minutes is generous enough.
  local deadline = GetGameTimer() + 15 * 60 * 1000
  while not IsCutsceneActive() do
    if GetGameTimer() > deadline then
      say('PROBE: keine Cutscene aktiv - der Probe lief ins Leere')
      return
    end
    Wait(500)
  end

  -- 2. MEASURE EVERYTHING, IN ONE PASS.
  --
  -- Native calls are milliseconds. Sending is the slow part, and the channel
  -- allows four messages per ten seconds while the cutscene lasts half a
  -- minute. So the facts are collected here, and sent afterwards.
  local facts = {}

  -- M1: THE SLOTS.
  --
  -- `cut` is the entity the CUTSCENE has in the slot, `reg` the one THIS
  -- PROJECT registered. If they are the same, the baked entity was displaced.
  -- The model says what is sitting there.
  local slotFacts = {}
  for _, name in ipairs(CANDIDATE_SLOTS) do
    local short = name:gsub('MP_Plane_Passenger_', 'P')
    if try('DoesCutsceneEntityExist', name, 0) then
      local cut = try('GetEntityIndexOfCutsceneEntity', name, 0) or 0
      local reg = try('GetEntityIndexOfRegisteredEntity', name, 0) or 0
      local model = 0
      if cut ~= 0 and DoesEntityExist(cut) then model = GetEntityModel(cut) end
      slotFacts[#slotFacts + 1] = ('%s cut=%d reg=%d %s'):format(
        short, cut, reg, modelName(model))
    else
      slotFacts[#slotFacts + 1] = ('%s leer'):format(short)
    end
  end
  facts[#facts + 1] = 'M1 slots: ' .. table.concat(slotFacts, ' | ')

  -- M3: THE PLAYBACK FLAGS.
  --
  -- The direct answer. The male list is 31 (bits 1, 2, 4, 8, 16), the female
  -- one 103 (bits 1, 2, 4, 32, 64). Which bits are set says which half of
  -- the video is playing - without waiting for the video to end.
  if available('IsCutscenePlaybackFlagSet') then
    local active = {}
    for _, flag in ipairs({ 1, 2, 4, 8, 16, 32, 64, 128 }) do
      if try('IsCutscenePlaybackFlagSet', flag) then active[#active + 1] = tostring(flag) end
    end
    facts[#facts + 1] = 'M3 flags aktiv: ' ..
      (#active > 0 and table.concat(active, ',') or 'keine') ..
      ' (maennlich erwartet 1,2,4,8,16 - weiblich 1,2,4,32,64)'
  end

  -- M2: WHERE THE PEDS ARE.
  --
  -- The horizontal distance to the jet decides who counts, and the HEIGHT is
  -- reported separately - the jet is at z ~ 142, the ground at z ~ 3. The old
  -- probe used a three-dimensional distance, so the ground was 139 metres
  -- away from the jet and the answer was always "nobody".
  local jetAnchor = vector3(-1200.0, -1490.0, 142.385)
  if available('GetGamePool') then
    for _, obj in ipairs(GetGamePool('CObject')) do
      if GetEntityModel(obj) == joaat('p_cs_mp_jet_01_s') then
        jetAnchor = GetEntityCoords(obj)
        break
      end
    end
  end

  local pedFacts, passengerPed = {}, nil
  if available('GetGamePool') then
    for _, p in ipairs(GetGamePool('CPed')) do
      local c = GetEntityCoords(p)
      local flat = vector3(c.x - jetAnchor.x, c.y - jetAnchor.y, 0.0)
      if #flat < 60.0 then
        pedFacts[#pedFacts + 1] = ('%d %s z=%.1f'):format(
          p, modelName(GetEntityModel(p)), c.z)
        if passengerPed == nil and GetEntityModel(p) ~= joaat('mp_m_freemode_01')
          and GetEntityModel(p) ~= joaat('mp_f_freemode_01') then
          passengerPed = p
        end
      end
    end
  end
  facts[#facts + 1] = 'M2 peds (x/y nahe Jet, z lautet die Hoehe): ' ..
    (#pedFacts > 0 and table.concat(pedFacts, ' ') or 'keine')

  -- M5: THE PASSENGER'S HEAD AGAINST THE PLAYER'S.
  --
  -- Component 0 is the head. A passenger that wears the player's head is the
  -- symptom the player reported; a different head with the same clothes is
  -- not.
  if passengerPed then
    local playerPed = PlayerPedId()
    local playerHead = select(1, GetPedComponentVariation(playerPed, 0))
    local passengerHead = select(1, GetPedComponentVariation(passengerPed, 0))
    local playerTorso = select(1, GetPedComponentVariation(playerPed, 3))
    local passengerTorso = select(1, GetPedComponentVariation(passengerPed, 3))
    facts[#facts + 1] = ('M5 kopf spieler=%d gast=%d | torso spieler=%d gast=%d'):format(
      playerHead or -1, passengerHead or -1, playerTorso or -1, passengerTorso or -1)
  else
    facts[#facts + 1] = 'M5 kein Passagier-Ped gefunden'
  end

  -- 3. THE TIMELINE.
  --
  -- Which section plays when. The section index changes over the cutscene;
  -- where it changes is where the plane part ends and the character sequence
  -- begins. The samples are collected in a thread and sent at the end.
  local timeline = {}
  CreateThread(function()
    local last = -1
    while IsCutsceneActive() do
      local section = try('GetCutsceneSectionPlaying')
      if type(section) == 'number' and section ~= last then
        last = section
        timeline[#timeline + 1] = ('s%d@%dms'):format(
          section, try('GetCutscenePlayTime') or -1)
      end
      Wait(400)
    end
  end)

  -- 4. WAIT FOR THE END, THEN MEASURE THE LENGTH.
  --
  -- The end time counts the playback list in, the total duration does not.
  -- So the end time being SHORTER is the proof that the list did something -
  -- the video played one half instead of both.
  while IsCutsceneActive() do Wait(300) end
  Wait(1000)

  local total = try('GetCutsceneTotalDuration')
  -- The name with the leading underscore is the one in the native database;
  -- FiveM registers the natives without it. Both are tried, because guessing
  -- which one exists is exactly what this probe is here to avoid.
  local endTime = try('GetCutsceneEndTime') or try('_GetCutsceneEndTime')
  facts[#facts + 1] = ('M3 ende: gesamt=%s endzeit=%s %s'):format(
    tostring(total), tostring(endTime),
    (type(total) == 'number' and type(endTime) == 'number' and endTime < total)
      and '=> die Liste hat gekuerzt' or '=> kein Unterschied')
  facts[#facts + 1] = 'M3 abschnittsfolge: ' ..
    (#timeline > 0 and table.concat(timeline, ' ') or 'keine')

  -- 5. SEND.
  --
  -- The facts, in pieces the channel accepts, at a pace it accepts.
  local queue = {}
  for _, fact in ipairs(facts) do
    for _, piece in ipairs(chunks(fact, 280)) do
      queue[#queue + 1] = piece
    end
  end

  for _, piece in ipairs(queue) do
    say(piece)
    Wait(SEND_INTERVAL_MS)
  end

  -- 6. FERTIG.
  --
  -- The names were asked at the beginning - they do not need the cutscene to
  -- be running, and the answer is worth more if it arrives even when the
  -- client dies during the load.
  say('PROBE fertig')
end)
