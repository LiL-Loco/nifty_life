-- nifty-armwrestling / client
--
-- Per-frame work for the local player:
--   1. Find the nearest arm-wrestling table and show a prompt when in range.
--   2. On E, ask the server to enrol us.
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

local TABLES = require('shared/positions')
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
local myPos   = 0.5      -- last hand position received from the server (0..1)
local promptActive = false

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

-- ---------------------------------------------------------------- actions

local function enterMatch(tableIdx, side)
  myTable = tableIdx
  mySide  = side
  myTEnd  = nil
  myPos   = 0.5

  local ped = getMyPed()
  local t = TABLES[tableIdx]
  -- Sit at the table. The RAGE script teleports both players into the
  -- move network by moving them onto the table's animation anchor. We
  -- freeze the player and play the right clip; the server's start event
  -- actually triggers the timed phase.
  FreezeEntityPosition(ped, true)
  SetEntityCollision(ped, false, false)

  -- Face the table.
  local headingRad = math.rad(t.heading + (side == 1 and 90 or -90))
  SetEntityHeading(ped, t.heading + (side == 1 and 90 or -90))

  loadAnimDict(ANIM_DICT)
  TaskMoveNetworkByName(ped, 'arm_wrestling_sweep_paired_a_rev3', 0.0, true, ANIM_DICT, 0)
  showNui(true)
end

local function startHold(tEnd)
  myTEnd = tEnd
  myPos = 0.5
end

local function leaveMatch()
  if not myTable then return end
  local ped = getMyPed()
  FreezeEntityPosition(ped, false)
  SetEntityCollision(ped, true, true)
  ClearPedTasks(ped)
  showNui(false)
  myTable = nil
  mySide  = nil
  myTEnd  = nil
  myPos   = 0.5
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
      -- already in a match; the server is the source of truth for the
      -- hand position, which it streams via nifty:arm:tick.
      Wait(50)
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
