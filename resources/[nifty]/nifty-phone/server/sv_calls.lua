--[[
  Calls: the state machine, without the voice.

  WHY A ROW AND NOT TWO BOOLEANS

  "Ringing" is the state where a call has been placed and neither answered nor
  ended, and every way of modelling it as flags on two players has the same
  failure: the state outlives the process that created it. One disconnect
  callback that does not run, or one that is registered twice and fires once, and
  two players are left ringing each other with no way to hang up. There is no
  recovery from that except a reconnect.

  A row with `end_reason IS NULL` makes "is this still live" one indexed query
  that cannot be half-updated, because the row is the only thing holding the
  state. Two players, one row, one truth.

  WHY THERE IS NO VOICE HERE

  ADR-0020 puts calls on temporary Teamspeak channels. That needs a
  serveradmin-level query account, which this server does not have yet.

  Rather than pretend, the transport is an interface with one method and one
  implementation that refuses:

      Phone.Voice.connect(callId, callerId, calleeId) -> voiceRef|nil, err

  The state machine calls it and carries on when it returns nil. Everything a
  player can DO — place, hear it ring, answer, decline, hang up, read the log —
  works today and is exercised today. What is missing is one adapter, and when
  the credentials exist it is a new file rather than a migration, because
  `phone_calls.voice_ref` is already there and nullable.
]]

local Db = Nifty.Db
local CallState = Nifty.Phone.CallState
local CallEnd = Nifty.Phone.CallEnd
local Events = Nifty.Phone.Events

Phone = Phone or {}

-- ---------------------------------------------------------------------------
-- The voice transport
-- ---------------------------------------------------------------------------

Phone.Voice = Phone.Voice or {}

--- Join a voice channel for this call. Returns a reference or nil with a reason.
---
--- The signature is fixed by ADR-0020 so the real implementation is a drop-in:
--- create a channel named for the call id, move both parties, return the channel
--- id. Nothing above this function knows what a channel is.
--- @return string|nil voiceRef, string|nil err
function Phone.Voice.connect(callId, callerId, calleeId)
  return nil, 'ADR-0020: kein Teamspeak-Query-Zugang konfiguriert'
end

--- Leave it. Same signature discipline: safe to call for a call that never had
--- a channel, because a hangup must never be blocked by the voice being absent.
function Phone.Voice.disconnect(callId, voiceRef)
  -- Nothing to do: nothing was ever created.
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- The call a character is currently in, in the shape the panel draws.
--- @return table|nil
function Phone.liveCallFor(characterId)
  return Db.one([[
    SELECT id, caller_id, callee_id, started_at, answered_at, voice_ref
      FROM phone_calls
     WHERE end_reason IS NULL
       AND (caller_id = ? OR callee_id = ?)
     ORDER BY started_at DESC
     LIMIT 1
  ]], { characterId, characterId }, 'phone:liveCallFor')
end

--- The panel's view model for a call row.
---
--- `state` is one of four values and the panel never derives it from two
--- booleans — that is the mistake this whole file is shaped to prevent.
--- @return table|nil
function Phone.callView(characterId)
  local row = Phone.liveCallFor(characterId)
  if not row then return nil end

  local outbound = row.caller_id == characterId
  local state
  if row.answered_at then
    state = CallState.ACTIVE
  elseif outbound then
    state = CallState.OUTGOING
  else
    state = CallState.INCOMING
  end

  local otherId = outbound and row.callee_id or row.caller_id
  local otherNumber = Db.one('SELECT number FROM phone_accounts WHERE character_id = ?',
    { otherId }, 'phone:callPeerNumber')

  return {
    id       = row.id,
    state    = state,
    outbound = outbound,
    with     = {
      number  = otherNumber and otherNumber.number or '?',
      name    = Phone.displayName(otherId),
    },
    startedAt = row.started_at,
    -- False rather than absent, so the panel can render "no voice" honestly
    -- instead of hiding the row it should be showing.
    hasVoice = row.voice_ref ~= nil,
  }
end

-- ---------------------------------------------------------------------------
-- Transitions
-- ---------------------------------------------------------------------------

--- Place a call.
---
--- Three return values, because "the line is busy" is neither success nor the
--- same failure as a typo. The caller writes the reason into the caller's view
--- and the caller's panel shows a different message for it than for a wrong
--- number; collapsing the two would mean every rejection reads the same.
--- @return table|nil call, string|nil err, string|nil endReason
function Phone.placeCall(characterId, number)
  local normalised, err = Phone.normalise(number)
  if not normalised then return nil, err end

  local targetId, targetAccount = Phone.characterByNumber(normalised)
  if not targetId then return nil, 'Diese Nummer ist nicht vergeben.' end
  if targetId == characterId then return nil, 'Das bist du.' end

  if Phone.liveCallFor(characterId) then
    return nil, 'Du redest schon.'
  end
  -- The other side being busy is checked, not assumed. A player calling somebody
  -- who is already on a call gets `busy`, which is a different thing from the
  -- call silently failing, and the call log records it as different.
  if Phone.liveCallFor(targetId) then
    return nil, nil, CallEnd.BUSY
  end

  local callId = Nifty.newUuid()
  Db.insert([[
    INSERT INTO phone_calls (id, caller_id, callee_id) VALUES (?, ?, ?)
  ]], { callId, characterId, targetId }, 'phone:placeCall')

  -- The voice attempt is made and its failure is carried, not raised. An
  -- unreachable Teamspeak server must not stop a call from ringing.
  local voiceRef, voiceErr = Phone.Voice.connect(callId, characterId, targetId)
  if voiceRef then
    Db.update('UPDATE phone_calls SET voice_ref = ? WHERE id = ?',
      { voiceRef, callId }, 'phone:callVoiceRef')
  else
    print(('[nifty-phone] call %s has no voice: %s'):format(callId, tostring(voiceErr)))
  end

  TriggerClientEvent(Events.INCOMING_CALL, targetId, {
    id   = callId,
    from = normalised,
    name = Phone.displayName(characterId),
  })

  return Phone.callView(characterId)
end

--- The callee accepts.
--- @return table|nil call, string|nil err
function Phone.answerCall(characterId)
  local row = Phone.liveCallFor(characterId)
  if not row then return nil, 'Kein Anruf.' end
  if row.callee_id ~= characterId then return nil, 'Das ist kein eingehender Anruf.' end
  if row.answered_at then return Phone.callView(characterId) end

  Db.update('UPDATE phone_calls SET answered_at = NOW() WHERE id = ?',
    { row.id }, 'phone:answerCall')

  -- Tell the caller too. Without this the caller's panel sits in `outgoing`
  -- forever while the callee is already talking, which is the worst possible
  -- reading of a working call.
  TriggerClientEvent(Events.INCOMING_CALL, row.caller_id, {
    id      = row.id,
    state   = CallState.ACTIVE,
    peer    = Phone.displayName(characterId),
  })

  return Phone.callView(characterId)
end

--- The callee refuses. `declined` and `missed` are different facts and the call
--- log renders them differently, so they are different reasons here.
--- @return table|nil call, string|nil err
function Phone.declineCall(characterId)
  local row = Phone.liveCallFor(characterId)
  if not row then return nil, 'Kein Anruf.' end
  if row.callee_id ~= characterId then return nil, 'Das ist kein eingehender Anruf.' end
  if row.answered_at then return nil, 'Das Gespräch läuft schon.' end

  Db.update([[
    UPDATE phone_calls SET end_reason = ?, ended_at = NOW() WHERE id = ?
  ]], { CallEnd.DECLINED, row.id }, 'phone:declineCall')

  Phone.Voice.disconnect(row.id, row.voice_ref)
  TriggerClientEvent(Events.INCOMING_CALL, row.caller_id, {
    id    = row.id,
    state = CallState.IDLE,
    reason = CallEnd.DECLINED,
  })

  return nil
end

--- Either side hangs up. The reason is derived from the state, not passed in:
--- `declined` is only the callee's to give, and `answered` only makes sense once
--- it was answered.
--- @return boolean ok, string|nil err
function Phone.endCall(characterId)
  local row = Phone.liveCallFor(characterId)
  if not row then return false, 'Kein Anruf.' end

  local reason = row.answered_at and CallEnd.ANSWERED or CallEnd.CANCELLED
  local other  = (row.caller_id == characterId) and row.callee_id or row.caller_id

  Db.update([[
    UPDATE phone_calls SET end_reason = ?, ended_at = NOW() WHERE id = ?
  ]], { reason, row.id }, 'phone:endCall')

  Phone.Voice.disconnect(row.id, row.voice_ref)

  TriggerClientEvent(Events.INCOMING_CALL, other, {
    id     = row.id,
    state  = CallState.IDLE,
    reason = reason,
  })

  return true
end

--- A call that never got answered ends when either side gives up on it, and the
--- reason depends on WHO gave up — the caller hanging up is `cancelled`, the
--- callee never appearing is `missed`. They look identical in the log and are
--- not the same social fact, which is why the enum keeps them apart.
function Phone.abandonStaleCalls()
  local stale = Db.all([[
    SELECT id, caller_id FROM phone_calls
     WHERE end_reason IS NULL AND answered_at IS NULL
       AND started_at < (NOW() - INTERVAL 45 SECOND)
  ]], {}, 'phone:abandonStale') or {}

  for _, row in ipairs(stale) do
    Db.update([[
      UPDATE phone_calls SET end_reason = ?, ended_at = NOW() WHERE id = ?
    ]], { CallEnd.MISSED, row.id }, 'phone:markMissed')

    Phone.Voice.disconnect(row.id, nil)
    TriggerClientEvent(Events.INCOMING_CALL, row.caller_id, {
      id = row.id, state = CallState.IDLE, reason = CallEnd.MISSED,
    })
    TriggerClientEvent(Events.INCOMING_CALL, row.callee_id, {
      id = row.id, state = CallState.IDLE, reason = CallEnd.MISSED,
    })
  end

  return #stale
end

--- Recent calls, newest first — the call log.
--- @return table[]
function Phone.callLog(characterId, limit)
  local take = tonumber(limit) or 25
  if take < 1 then take = 1 end
  if take > 100 then take = 100 end

  -- `outbound` is computed HERE rather than in the panel: the panel is not told
  -- its own character id, so "did I make this call" is a question only this side
  -- can answer. Sending it as a column is cheaper than sending the id and making
  -- every client compare against it.
  return Db.all([[
    SELECT c.id, c.caller_id, c.callee_id, c.started_at, c.answered_at, c.end_reason,
           pa.number,
           ch.first_name, ch.last_name,
           (c.caller_id = ?) AS outbound
      FROM phone_calls c
      JOIN phone_accounts pa ON pa.character_id =
             IF(c.caller_id = ?, c.callee_id, c.caller_id)
      JOIN characters ch ON ch.id =
             IF(c.caller_id = ?, c.callee_id, c.caller_id)
     WHERE c.caller_id = ? OR c.callee_id = ?
     ORDER BY c.started_at DESC
     LIMIT ?
  ]], { characterId, characterId, characterId, characterId, characterId, take },
    'phone:callLog') or {}
end

-- The sweeper. A call with no end_reason is live by definition, so the only way
-- an abandoned one exists is if no player ever touches it again — and that is the
-- common case, because the person who was called has walked off.
--
-- It runs on a timer rather than on a disconnect event because "they left" is not
-- something the OTHER player can observe. The row is the evidence.
CreateThread(function()
  while true do
    Wait(15000)
    local ok, err = pcall(Phone.abandonStaleCalls)
    if not ok then
      print(('[nifty-phone] call sweeper failed: %s'):format(tostring(err)))
    end
  end
end)