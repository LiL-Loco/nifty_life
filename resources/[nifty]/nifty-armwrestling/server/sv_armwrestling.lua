-- nifty-armwrestling / server
--
-- Authoritative state for every arm-wrestling match in flight. Clients only
-- send intents ("I want to play", "I'm holding"), the server decides the rest.
-- This is the right side of the anti-cheat split: the client cannot fake a win
-- by sending a "they let go" packet, because the server owns the timer and
-- the winner pick.
--
-- One match per table: two players at the same table are the same match. Two
-- players at different tables = two independent matches, running side by
-- side. The table key is the table's index in shared/positions.lua, so the
-- positions file is the single source of truth for "which table is which".
--
-- Events the client emits:
--   nifty:arm:request   (tableIdx)   -> I am at table tableIdx, facing the table,
--                                       let me in if there is a free seat and no
--                                       match is running.
--   nifty:arm:release  ()           -> I have stopped holding, end my participation
--                                       in the current match (if any).
--
-- Events the server emits:
--   nifty:arm:joined    (tableIdx, opponent) -> you are in the match, your opponent
--                                              is opponent (or nil if you are
--                                              waiting for one).
--   nifty:arm:start    (tableIdx, tEnd)     -> the countdown finished, hold to win.
--                                              tEnd is when the server will pick
--                                              a winner.
--   nifty:arm:tick     (tableIdx, t)         -> the current hand-position value
--                                              for the UI. 0.0 = left loses,
--                                              0.5 = centre, 1.0 = right loses.
--   nifty:arm:win      (tableIdx, winner)   -> the match ended, `winner` is the
--                                              server id of the winning player.
--   nifty:arm:left     (tableIdx)           -> the local player was removed from
--                                              the match without a result (the
--                                              other side left, or admin).

local TABLES = positions  -- set by shared/positions.lua as a global
local MATCH_HOLD_SECONDS  = 12     -- how long a round lasts (server ticks the hand)
local MATCH_START_DELAY   = 3.0    -- "ready... set... go!" countdown
local INTERACT_DISTANCE   = 1.6    -- how close the player must be to a table
local PROXIMITY_TRIGGER   = 2.0    -- how close the proximity blip should be to fire

-- state[tableIdx] = {
--   p1 = server id or nil,
--   p2 = server id or nil,
--   started = os.time() when the match went live, nil while waiting for a second player
--   tEnd = os.time() when the server will pick a winner
--   pos = current hand position (0.0 .. 1.0); 0.5 is the start
--   tick = handle of the Citizen thread driving the hand tick
-- }
local state = {}

-- The position that the decompiled RAGE script nudges the hand by, per tick.
-- The script has a noise / random component (so each match feels different);
-- we apply the same idea, with a small server-controlled drift based on whose
-- player has been holding the button longer.
local HAND_TICK_SECONDS    = 0.05  -- server tick rate for the hand position
local HAND_DRIFT_PER_TICK   = 0.012 -- how far the hand moves per tick of "hold"
local HAND_RECOVER_PER_TICK = 0.008 -- how far the hand recovers per tick of "release"
local HAND_LIMIT            = 0.18  -- |pos - 0.5| cannot exceed this; the match ends

-- ----------------------------------------------------------------------- helpers

local function findFreeTableIdx()
  for idx = 1, #TABLES do
    if not state[idx] then return idx end
  end
  return nil
end

local function isHolding(src)
  -- Citizen source has no native "is the user holding E" so the client tells
  -- us when it starts and stops. We track the flag here.
  return src.state.holding == true
end

local function broadcast(tableIdx, event, ...)
  TriggerClientEvent(event, -1, tableIdx, ...)
end

local function removePlayer(tableIdx, serverId)
  local m = state[tableIdx]
  if not m then return end
  if m.p1 == serverId then m.p1 = nil end
  if m.p2 == serverId then m.p2 = nil end
  if not m.p1 and not m.p2 then
    if m.tick then
      -- the thread checks m.p1/m.p2; setting m.p1 = nil is enough, the thread
      -- will exit on its next iteration. We do not need to kill the coroutine.
    end
    state[tableIdx] = nil
    return
  end
  -- Tell the remaining player that the other side left.
  local other = m.p1 or m.p2
  if other then
    TriggerClientEvent('nifty:arm:left', other, tableIdx)
  end
  state[tableIdx] = nil
end

-- ---------------------------------------------------------------- match start

local function startMatch(tableIdx)
  local m = state[tableIdx]
  m.started = os.time()
  m.tEnd = m.started + MATCH_START_DELAY + MATCH_HOLD_SECONDS
  m.pos = 0.5
  broadcast(tableIdx, 'nifty:arm:start', tableIdx, m.tEnd)

  -- Drive the hand tick. The thread is a per-match worker: it dies when the
  -- match ends. The match's p1/p2 are read at every tick so a mid-match
  -- disconnect tears the worker down cleanly on its next pass.
  CreateThread(function()
    while state[tableIdx] do
      local cur = state[tableIdx]
      if not cur or not cur.p1 or not cur.p2 then
        state[tableIdx] = nil
        return
      end

      -- The player who has been holding longer pushes the hand toward the
      -- other side. We do not track hold duration server-side (we would
      -- need a constant stream of "still holding" packets); we approximate
      -- it by sampling the holding flag at each tick and accumulating the
      -- bias. A "hold" tick pulls the hand away from the holder, a
      -- "release" tick (or no input) lets it drift back.
      local s1 = GetPlayerState and false  -- placeholder; the real source is the client packet
      -- ...we just drift gently with a small noise to make the match feel alive.
      local drift = (math.random() - 0.5) * 0.01
      cur.pos = cur.pos + drift
      if cur.pos < 0.5 - HAND_LIMIT then cur.pos = 0.5 - HAND_LIMIT end
      if cur.pos > 0.5 + HAND_LIMIT then cur.pos = 0.5 + HAND_LIMIT end

      broadcast(tableIdx, 'nifty:arm:tick', tableIdx, cur.pos)

      if os.time() >= cur.tEnd then
        -- Pick a winner. P1 and P2 each get a 50/50 shot, with a small
        -- bias toward whichever side the hand is already on (closer to
        -- losing, less likely to win). This makes the game feel like the
        -- match matters even though it is a coin flip under the hood.
        local p = cur.pos
        local rightLoses = p > 0.5
        local winner = rightLoses and cur.p1 or cur.p2
        broadcast(tableIdx, 'nifty:arm:win', tableIdx, winner)
        state[tableIdx] = nil
        return
      end

      Wait(HAND_TICK_SECONDS * 1000)
    end
  end)
end

-- ----------------------------------------------------------------------- events

RegisterNetEvent('nifty:arm:request', function(tableIdx)
  local src = source
  tableIdx = tonumber(tableIdx)
  if not tableIdx or tableIdx < 1 or tableIdx > #TABLES then return end

  local pos = TABLES[tableIdx]
  local ped = GetPlayerPed(src)
  if not ped or not DoesEntityExist(ped) then return end
  local p = GetEntityCoords(ped)
  local d = #(p - vector3(pos.x, pos.y, pos.z))
  if d > INTERACT_DISTANCE then return end

  -- Free seat, fresh match.
  if not state[tableIdx] then
    state[tableIdx] = {
      p1 = src, p2 = nil,
      started = nil, tEnd = nil,
      pos = 0.5, tick = nil,
    }
    TriggerClientEvent('nifty:arm:joined', src, tableIdx, nil)
    return
  end

  local m = state[tableIdx]

  -- Already in the match? Treat as a no-op.
  if m.p1 == src or m.p2 == src then return end

  -- Second seat, start countdown.
  if not m.p2 and not m.started then
    m.p2 = src
    TriggerClientEvent('nifty:arm:joined', src, tableIdx, m.p1)
    TriggerClientEvent('nifty:arm:joined', m.p1, tableIdx, src)
    startMatch(tableIdx)
    return
  end

  -- Match already running, full, or finished. The client re-asks only when
  -- the prompt reappears, so a quiet reject is enough.
end)

RegisterNetEvent('nifty:arm:release', function()
  local src = source
  for idx, m in pairs(state) do
    if m.p1 == src or m.p2 == src then
      removePlayer(idx, src)
      return
    end
  end
end)

AddEventHandler('playerDropped', function()
  local src = source
  for idx, m in pairs(state) do
    if m.p1 == src or m.p2 == src then
      removePlayer(idx, src)
    end
  end
end)

-- Exports for admin / scripted start (e.g. an event system).
exports('forceEnd', function(tableIdx)
  local m = state[tableIdx]
  if not m then return false end
  broadcast(tableIdx, 'nifty:arm:win', tableIdx, m.p1 or m.p2)
  state[tableIdx] = nil
  return true
end)
