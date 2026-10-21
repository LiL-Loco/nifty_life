--[[
  Stütze (ADR-0009).

  An unconditional handout: no job, no location, no check of any kind. Every
  connected character gets it, on a timer, forever. That is the decision, and
  the entire economy is built around the consequence.

  The number that matters is `economy.stuetze.amount`. It MUST stay below what a
  character needs to eat. The moment it reaches subsistence, logging in becomes
  more profitable than working, and every job, property and business in this
  server becomes decoration nobody is obliged to touch.

  So this module does not enforce that. Nothing can, from the inside - a setting
  can be edited by anyone with database access. What it does instead is leave a
  complete record, so the assumption being wrong is a number in a table rather
  than a mystery discovered months later by players who stopped playing.
]]

local RESOURCE = GetCurrentResourceName()

--- Same-resource state, set up by earlier files in the load chain (db.lua,
--- sv_session_guard.lua, settings.lua, identity.lua). No bridge fetch needed
--- when living inside the same resource.
local Db = Db
local SessionGuard = SessionGuard
local GetSetting = GetSetting
local Identity = Identity

Stuetze = {}

--- Per-connection payout state, keyed by FiveM slot. Slot IDs are safe here and
--- only here: this table dies with the connection and never reaches the database
--- (ADR-0001).
local Timers = {}

--- How many payouts this connection has already received.
local PaidThisSession = {}

--- Start paying a character. Called when they enter the world, not when they
--- connect - a player rejected at the whitelist must not accrue welfare.
function Stuetze.start(src, characterId)
  Stuetze.stop(src)

  local interval = GetSetting('economy.stuetze.interval_sec', 900)
  PaidThisSession[src] = 0

  local function tick()
    -- Two independent reasons to stop, because this closure moves money.
    --
    -- The first is the session: a player who dropped and rejoined mid-interval
    -- must not be paid for a character they are no longer playing.
    --
    -- The second is the engine itself. Under OneSync big mode a distant
    -- disconnect produces no playerDropped, so the session is still open and the
    -- first check passes - the Stütze would keep paying a character nobody is
    -- playing. `GetPlayerName` reads the player list directly and is not scoped
    -- by distance. The watchdog in sv_session_guard.lua would catch this within
    -- 30 seconds anyway, but the step that pays out should not depend on a
    -- background thread having run.
    if Identity.getActiveCharacter(src) ~= characterId or not GetPlayerName(src) then
      Stuetze.stop(src)
      return
    end

    Stuetze.pay(src, characterId)

    if Timers[src] then
      Timers[src] = SetTimeout(interval, tick)
    end
  end

  Timers[src] = SetTimeout(interval, tick)

  print(('[%s] Stütze armed for slot %s every %ss'):format(RESOURCE, src, tostring(interval)))
end

function Stuetze.stop(src)
  if Timers[src] then
    ClearTimeout(Timers[src])
    Timers[src] = nil
  end
  PaidThisSession[src] = nil
end

--- Pay one instalment. Returns true when money actually moved.
function Stuetze.pay(src, characterId)
  local amount = Economy.round(GetSetting('economy.stuetze.amount', 0))
  if amount <= 0 then
    print(('[%s] Stütze disabled: economy.stuetze.amount is %s'):format(RESOURCE, tostring(amount)))
    return false
  end

  -- The only brake in the whole system. It exists so that staying logged in for
  -- six hours is not worth more than a shift of actual work - not to make anyone
  -- earn it.
  local cap = GetSetting('economy.stuetze.max_per_session', 8)
  local paid = PaidThisSession[src] or 0

  if paid >= cap then
    print(('[%s] Stütze session cap reached for slot %s (%d/%d) - no payout'):format(
      RESOURCE, src, paid, cap))
    return false
  end

  local ok = Economy.credit(characterId, 'cash', amount, 'stuetze', 'session', Identity.getActiveSessionId(src))

  if not ok then
    -- A credit can only fail on a database error or a bad reason. Both are bugs,
    -- and both must be visible rather than silently skipped by the next tick.
    print(('[%s] Stütze FAILED for character %s'):format(RESOURCE, characterId))
    return false
  end

  -- `stuetze_payouts` is the abuse-detection table: one row per instalment, so
  -- "is the Stütze above subsistence?" is answerable with a query rather than an
  -- argument. The money itself is already recorded in `ledger`.
  --
  -- `NULLIF(?, '')` for the same reason as in Economy.apply: the session id is
  -- nil outside a connection, and a nil in the middle of a Lua table ends the
  -- table, which would leave this INSERT with fewer values than placeholders.
  --
  -- The CAST is there for the same reason as in Economy.apply: a parameter
  -- whose type MySQL cannot pin down inherits the type of an earlier parameter
  -- in the same statement, and the amount is a DECIMAL. Without the CAST the
  -- session id inherits DECIMAL, and the empty string cannot be converted to
  -- a number. The statement works today because the session id comes FIRST
  -- and the amount SECOND - that is luck, not design.
  local recorded = Db.insert(
    [[INSERT INTO stuetze_payouts (character_id, session_id, amount)
      VALUES (?, NULLIF(CAST(? AS CHAR), ''), ?)]],
    { characterId, Identity.getActiveSessionId(src) or '', tostring(amount) },
    'stuetze:record')

  if recorded == nil then
    -- A payout with no record is exactly the situation this table exists to
    -- detect, so it must not pass silently - and it must not stop the money.
    -- The payout already happened; the audit row is what is missing.
    print(('[%s] WARNING: Stütze paid but not recorded (character=%s amount=%s session=%s)'):format(
      RESOURCE, characterId, tostring(amount), tostring(Identity.getActiveSessionId(src))))
  end

  PaidThisSession[src] = paid + 1

  Economy.push(src, characterId)

  return true
end

-- Registered with the session guard rather than hooked to `playerDropped`
-- directly. Under OneSync big mode that event does not arrive for a player who
-- disconnects out of range, and a Stütze that keeps paying is the exact failure
-- this server's economy cannot survive.
SessionGuard.onStop('stuetze', function(src)
  Stuetze.stop(src)
end)

--- `/niftystuetze` — prints the number the whole economy hangs on, plus what the
--- server has actually paid out. The first is a setting; the second is the
--- assumption being tested against reality.
RegisterCommand('niftystuetze', function()
  local amount = GetSetting('economy.stuetze.amount', 0)
  local interval = GetSetting('economy.stuetze.interval_sec', 900)

  local stats = Db.one([[
    SELECT COUNT(*) AS payouts, COALESCE(SUM(amount), 0) AS total FROM stuetze_payouts
  ]], {}, 'stuetze:stats')

  print(('[%s] Stütze: %s every %ss = %.2f/hour of pure attendance'):format(
    RESOURCE, tostring(amount), tostring(interval), amount * (3600 / math.max(interval, 1))))
  print(('[%s] paid out so far: %s instalments, %s total'):format(
    RESOURCE, tostring(stats and stats.payouts or '?'), tostring(stats and stats.total or '?')))
end, true)

exports('start', Stuetze.start)
exports('stop', Stuetze.stop)
