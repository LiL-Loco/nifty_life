--- Stütze (ADR-0009).
---
--- An unconditional handout: no job, no location, no check of any kind. Every
--- connected character gets it, on a timer, forever. That is the decision, and
--- the entire economy is built around the consequence.
---
--- The number that matters is `economy.stuetze.amount`. It MUST stay below what a
--- character needs to eat. The moment it reaches subsistence, logging in becomes
--- more profitable than working, and every job, property and business in this
--- server becomes decoration nobody is obliged to touch.
---
--- So this module does not enforce that. Nothing can, from the inside — a setting
--- can be edited by anyone with database access. What it does instead is leave a
--- complete record, so the assumption being wrong is a number in a table rather
--- than a mystery discovered months later by players who stopped playing.

local RESOURCE = GetCurrentResourceName()

Stuetze = {}

--- Per-connection payout state, keyed by FiveM slot. Slot IDs are safe here and
--- only here: this table dies with the connection and never reaches the database
--- (ADR-0001).
local Timers = {}

--- How many payouts this connection has already received.
local PaidThisSession = {}

--- Start paying a character. Called when they enter the world, not when they
--- connect — a player rejected at the whitelist must not accrue welfare.
function Stuetze.start(src, characterId)
  Stuetze.stop(src)

  local interval = GetSetting('economy.stuetze.interval_sec', 900)
  PaidThisSession[src] = 0

  local function tick()
    -- Re-check the session rather than trusting the closure: a player who
    -- dropped and rejoined mid-interval must not be paid for a character they
    -- are no longer playing.
    if Identity.getActiveCharacter(src) ~= characterId then
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
  -- six hours is not worth more than a shift of actual work — not to make anyone
  -- earn it.
  local cap = GetSetting('economy.stuetze.max_per_session', 8)
  local paid = PaidThisSession[src] or 0

  if paid >= cap then
    print(('[%s] Stütze session cap reached for slot %s (%d/%d) — no payout'):format(
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
  Db.insert([[
    INSERT INTO stuetze_payouts (character_id, session_id, amount) VALUES (?, ?, ?)
  ]], { characterId, Identity.getActiveSessionId(src), tostring(amount) }, 'stuetze:record')

  PaidThisSession[src] = paid + 1

  Economy.push(src, characterId)

  return true
end

AddEventHandler('playerDropped', function()
  Stuetze.stop(source)
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