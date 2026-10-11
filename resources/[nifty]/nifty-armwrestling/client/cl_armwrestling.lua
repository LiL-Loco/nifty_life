-- nifty-armwrestling / client
--
-- Per-frame work for the local player:
--   1. Find the nearest arm-wrestling table and show a prompt when in range.
--   2. On E, ask the server to enrol us.
--   3. After the server confirms we are in, play the right arm-wrestling
--      move-network clip and stream the hand position to a NUI bar.
--   4. Render the GTA-native 3-2-1 countdown and the win/lose banner on top of
--      the move network, using the same scaleform movies the RAGE script uses
--      (COUNTDOWN, MP_BIG_MESSAGE_FREEMODE). The scaleforms give the match
--      an authentic look; the NUI bar carries the dynamic hand position
--      because re-issuing scaleform SET_DATA_SLOT every 50 ms is wasteful
--      and the bar's CSS transition smooths the dot.
--   5. On win/lose, play the result pose and clean up.
--   3. After the server confirms we are in, play the right arm-wrestling
--      move-network clip and stream the hand position to a NUI bar.
--   4. On win/lose, play the result pose and clean up.
--
-- The move network clips are defined in the `mini@arm_wrestling` dictionary.
-- The RAGE script plays them via TASK::TASK_MOVE_NETWORK_BY_NAME on the
-- local player ped. FiveM's Citizen API exposes the same primitive
-- through TaskMoveNetworkByName. We use that.
--
-- The decompiled RAGE script uses the move network's own playback progress
-- to drive the hand position on the screen. That is fragile (the move
-- network clips can be skipped on slow clients, the progress is in
-- arbitrary units, and the server has no view of it). We use the server's
-- own tick instead: see server/sv_armwrestling.lua for the model.

local TABLES = positions  -- set by shared/positions.lua as a global
local INTERACT_DISTANCE = 1.6
local PROXIMITY_TRIGGER = 2.0
local NUI_DRAW_DISTANCE  = 18.0   -- we only show the NUI while in this range

-- mini@arm_wrestling dictionary, clips we use. The "a" / "b" suffix picks which
-- side of the table the player is on; player 1 plays a, player 2 plays b.
local ANIM_DICT = 'mini@arm_wrestling'
local ANIM_CLIP_STAND_IDLE   = { 'stand_idle_a_face',  'stand_idle_b_face'  }
local ANIM_CLIP_EXPR_IDLE    = { 'expression_idle_a_face', 'expression_idle_b_face' }
local ANIM_CLIP_WIN          = { 'win_a_ped_a_face',  'win_a_ped_b_face'  }
local ANIM_CLIP_LOSE         = { 'win_b_ped_a_face',  'win_b_ped_b_face'  }

-- After the match (used by the RAGE script for the TV-style pose).
local RESULT_DICT  = 'mp_player_int_uppersmoker'
local RESULT_WIN   = 'mp_player_int_uppersmoker'
-- (the "ARMMP_WRESTLE" pose is a separate dict; the decompiled RAGE script
-- plays it after the win pose as a flourish. We keep the simpler win pose
-- for now and add the flourish as a follow-up.)

-- ---------------------------------------------------------------- state

local myTable = nil      -- table index when the local player is in a match
local mySide  = nil      -- 1 = side a, 2 = side b
local myTEnd  = nil      -- os.clock() at which the server will end the match
local myTStart = nil     -- os.clock() at which the server fired nifty:arm:start
local myPos   = 0.5      -- last hand position received from the server (0..1)
local promptActive = false

-- Big-message banner: shown after a match ends, for BIG_MSG_DURATION
-- seconds. Set by nifty:arm:win, cleared on leaveMatch.
local myBigMsg = nil     -- { text, r, g, b, until } or nil
local BIG_MSG_DURATION = 3.0

-- The server runs MATCH_START_DELAY seconds of countdown before the hand
-- phase. We render the COUNTDOWN scaleform during that window. The phases
-- line up with the server's clock: countdown from myTStart, hand from
-- myTStart + MATCH_START_DELAY, end at myTEnd.
local MATCH_START_DELAY = 3.0

-- ---------------------------------------------------------------- helpers

local function getMyPed()
  return PlayerPedId()
end

local function loadAnimDict(dict)
  if HasAnimDictLoaded(dict) then return end
  RequestAnimDict(dict)
  local deadline = GetGameTimer() + 3000
  while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do
    Wait(0)
  end
end

local function nearestTable()
  local ped = getMyPed()
  if not ped or not DoesEntityExist(ped) then return nil, nil end
  local p = GetEntityCoords(ped)
  local bestIdx, bestD2 = nil, (INTERACT_DISTANCE + 1) ^ 2
  for i, t in ipairs(TABLES) do
    local dx, dy, dz = p.x - t.x, p.y - t.y, p.z - t.z
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 < bestD2 then
      bestIdx, bestD2 = i, d2
    end
  end
  if bestIdx and bestD2 <= INTERACT_DISTANCE ^ 2 then
    return bestIdx, math.sqrt(bestD2)
  end
  return nil, nil
end

local function setPrompt(active, tableIdx)
  if active == promptActive then return end
  promptActive = active
  if active then
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName('Druecke ~INPUT_CONTEXT~ um Armdruecken zu spielen.')
    EndTextCommandDisplayHelp(0, false, true, -1)
  end
end

-- ----------------------------------------------------------------- NUI

local function showNui(show)
  SendNUIMessage({ type = show and 'show' or 'hide' })
end

local function tickNui(pos)
  -- 0.5 = centre, 0 = left lost, 1 = right lost. The NUI draws a bar; we pass
  -- the position as a 0..1 float and the bar's CSS handles the rest.
  SendNUIMessage({ type = 'tick', pos = pos })
end

-- ---------------------------------------------------------- scaleform helpers

-- Two GTA-native scaleform movies. They are requested on demand (one per
-- match) and freed via SetScaleformMovieAsNoLongerNeeded at the end. The
-- RAGE script keeps them in a struct field; we let the GC collect after
-- the match leaves scope.

-- COUNTDOWN: shows "3", "2", "1", "GO!" centred on screen. We push each
-- number with SET_MESSAGE during the MATCH_START_DELAY window (3 s).
-- BIG_MSG: shows the "Player WINS / Player LOSES" banner. The RAGE script
-- loads it once at script start; we follow the same pattern.
local sfCountdown = nil
local sfBigMsg    = nil

local function requireScaleform(name)
  if not HasScaleformMovieLoaded(name) then
    RequestScaleformMovie(name)
    local deadline = GetGameTimer() + 3000
    while not HasScaleformMovieLoaded(name) and GetGameTimer() < deadline do
      Wait(0)
    end
  end
  return GetScaleformMovieHandle(name) or nil
end

local function drawBigMessage(text, r, g, b, a)
  -- MP_BIG_MESSAGE_FREEMODE setup the RAGE script does:
  --   SET_BACKGROUND_COLOUR  0, 0, 0, 200
  --   SET_MESSAGE             <text>
  --   SET_COLOUR_OF_NEXT_TEXT_COMPONENT <HUD colour 12 = "HUD_COLOUR_BLUE">
  -- and then DRAW the scaleform fullscreen every frame.
  -- We follow the same pattern, except the colour is passed in directly
  -- so we can use a green tint for wins and a red tint for losses.
  if not sfBigMsg or sfBigMsg == 0 then return end
  BeginScaleformMovieMethod(sfBigMsg, 'SET_BACKGROUND_COLOUR')
  ScaleformMovieMethodAddParamFloat(0.0)
  ScaleformMovieMethodAddParamFloat(0.0)
  ScaleformMovieMethodAddParamFloat(0.0)
  ScaleformMovieMethodAddParamFloat(200.0)
  EndScaleformMovieMethod()

  BeginScaleformMovieMethod(sfBigMsg, 'SET_MESSAGE')
  BeginTextCommandScaleformString('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandScaleformString()
  ScaleformMovieMethodAddParamInt(r)
  ScaleformMovieMethodAddParamInt(g)
  ScaleformMovieMethodAddParamInt(b)
  ScaleformMovieMethodAddParamInt(a)
  EndScaleformMovieMethod()

  DrawScaleformMovieFullscreen(sfBigMsg, 255, 255, 255, 255, 0)
end

local function drawCountdown(text)
  if not sfCountdown or sfCountdown == 0 then return end
  -- COUNTDOWN takes the number / "GO!" via SET_MESSAGE too. The RAGE script
  -- only ever pushes "CNTDWN_GO"; the 3-2-1 is implicit in the move network's
  -- built-in timing. We push each number explicitly so the countdown is
  -- legible even if the move network clips early.
  BeginScaleformMovieMethod(sfCountdown, 'SET_MESSAGE')
  BeginTextCommandScaleformString('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandScaleformString()
  ScaleformMovieMethodAddParamInt(255)
  ScaleformMovieMethodAddParamInt(255)
  ScaleformMovieMethodAddParamInt(255)
  ScaleformMovieMethodAddParamInt(255)
  EndScaleformMovieMethod()

  DrawScaleformMovieFullscreen(sfCountdown, 255, 255, 255, 255, 0)
end

-- ---------------------------------------------------------------- actions

local function enterMatch(tableIdx, side)
  myTable = tableIdx
  mySide  = side
  myTEnd  = nil
  myTStart = nil
  myPos   = 0.5
  myBigMsg = nil

  local ped = getMyPed()
  local t = TABLES[tableIdx]
  -- Sit at the table. The RAGE script teleports both players into the
  -- move network by moving them onto the table's animation anchor. We
  -- freeze the player and play the right clip; the server's start event
  -- actually triggers the timed phase.
  FreezeEntityPosition(ped, true)
  SetEntityCollision(ped, false, false)

  -- Face the table.
  SetEntityHeading(ped, t.heading + (side == 1 and 90 or -90))

  loadAnimDict(ANIM_DICT)
  TaskMoveNetworkByName(ped, 'arm_wrestling_sweep_paired_a_rev3', 0.0, true, ANIM_DICT, 0)
  showNui(true)

  -- Pre-load the two scaleforms. We request them on demand because each
  -- one is a fairly heavy asset; once the match is over we drop them.
  sfCountdown = requireScaleform('COUNTDOWN')
  sfBigMsg    = requireScaleform('MP_BIG_MESSAGE_FREEMODE')
end

local function startHold(tEnd)
  myTEnd   = tEnd
  myTStart = os.clock()
  myPos    = 0.5
end

local function leaveMatch()
  if not myTable then return end
  local ped = getMyPed()
  FreezeEntityPosition(ped, false)
  SetEntityCollision(ped, true, true)
  ClearPedTasks(ped)
  showNui(false)
  if sfCountdown and sfCountdown ~= 0 then SetScaleformMovieAsNoLongerNeeded(sfCountdown) end
  if sfBigMsg    and sfBigMsg    ~= 0 then SetScaleformMovieAsNoLongerNeeded(sfBigMsg)    end
  sfCountdown = nil
  sfBigMsg    = nil
  myTable  = nil
  mySide   = nil
  myTEnd   = nil
  myTStart = nil
  myPos    = 0.5
  myBigMsg = nil
end

local function playResult(won)
  if not myTable then return end
  local ped = getMyPed()
  local clip = won and ANIM_CLIP_WIN[mySide] or ANIM_CLIP_LOSE[mySide]
  loadAnimDict(ANIM_DICT)
  -- short ad-hoc play: a static pose clipped to 2 s. The RAGE script does
  -- the same trick with REQUEST_CLIP_SET + TASK_PLAY_ANIM; we do it
  -- through TaskPlayAnim with a finite duration.
  TaskPlayAnim(ped, ANIM_DICT, clip, 8.0, -8.0, 2000, 0, 0.0, false, false, false)

  -- Schedule the big-message banner. The RAGE script shows the winner's
  -- name to both players with a green tint for wins and a red tint for
  -- losses. We do the same with the player's own first name.
  local name = GetPlayerName(PlayerId()) or 'Du'
  if won then
    myBigMsg = { text = name .. ' gewinnt',  r = 80, g = 220, b = 110, a = 255, untilAt = os.clock() + BIG_MSG_DURATION }
  else
    myBigMsg = { text = name .. ' verliert', r = 220, g = 70,  b = 70,  a = 255, untilAt = os.clock() + BIG_MSG_DURATION }
  end
end

-- ---------------------------------------------------------------- events

RegisterNetEvent('nifty:arm:joined', function(tableIdx, opponent)
  if source ~= 255 and source ~= GetPlayerServerId(PlayerId()) then return end
  if opponent then
    -- second player joined: we are side 2
    enterMatch(tableIdx, 2)
  else
    -- first player joined: we wait for an opponent
    enterMatch(tableIdx, 1)
  end
end)

RegisterNetEvent('nifty:arm:start', function(tableIdx, tEnd)
  if source ~= 255 and source ~= GetPlayerServerId(PlayerId()) then return end
  if tableIdx ~= myTable then return end
  startHold(tEnd)
end)

RegisterNetEvent('nifty:arm:tick', function(tableIdx, pos)
  if source ~= 255 and source ~= GetPlayerServerId(PlayerId()) then return end
  if tableIdx ~= myTable then return end
  myPos = pos
  tickNui(pos)
end)

RegisterNetEvent('nifty:arm:win', function(tableIdx, winner)
  if source ~= 255 and source ~= GetPlayerServerId(PlayerId()) then return end
  if tableIdx ~= myTable then return end
  playResult(GetPlayerServerId(PlayerId()) == winner)
  Wait(2000)
  leaveMatch()
end)

RegisterNetEvent('nifty:arm:left', function(tableIdx)
  if source ~= 255 and source ~= GetPlayerServerId(PlayerId()) then return end
  if tableIdx ~= myTable then return end
  leaveMatch()
end)

-- --------------------------------------------------------------- interaction

CreateThread(function()
  while true do
    local ped = getMyPed()
    if not ped or not DoesEntityExist(ped) then
      Wait(500)
      goto continue
    end

    if myTable then
      -- already in a match; render the countdown + big-message overlays
      -- in addition to whatever else the server is driving.

      -- Countdown: visible for the first MATCH_START_DELAY seconds after
      -- startHold() recorded myTStart. We show 3-2-1-GO at one number per
      -- second; on the GO tick we leave the scaleform up for the rest of
      -- the second so it doesn't blank between numbers.
      if myTStart then
        local elapsed = os.clock() - myTStart
        if elapsed < MATCH_START_DELAY then
          local phase = math.floor(elapsed) + 1
          local text
          if phase >= 4 then text = 'GO!'
          else text = tostring(4 - phase) end
          drawCountdown(text)
        end
      end

      -- Big-message banner: shown for BIG_MSG_DURATION seconds after
      -- a match result. Wins green, losses red, both with the player's
      -- own first name as the headline.
      if myBigMsg and os.clock() < myBigMsg.untilAt then
        drawBigMessage(myBigMsg.text, myBigMsg.r, myBigMsg.g, myBigMsg.b, myBigMsg.a)
      end

      Wait(0)
      goto continue
    end

    local idx, dist = nearestTable()
    if idx then
      setPrompt(true, idx)
      if IsControlJustPressed(0, 38) then  -- INPUT_CONTEXT (E on keyboard)
        TriggerServerEvent('nifty:arm:request', idx)
      end
    else
      setPrompt(false, nil)
    end

    Wait(0)
    ::continue::
  end
end)

-- Release-on-quit: tell the server we left so the other side is freed.
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  if myTable then TriggerServerEvent('nifty:arm:release') end
end)

AddEventHandler('playerDropped', function()
  if myTable then TriggerServerEvent('nifty:arm:release') end
end)
