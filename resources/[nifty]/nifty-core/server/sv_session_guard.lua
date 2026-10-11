--- Session watchdog — because `playerDropped` is not a guarantee (OneSync big mode).
---
--- `onesync on` enables OneSync big mode, and big mode scopes *entity* events by
--- distance: the official documentation states that player connect/disconnect
--- events only arrive when the player is in range. A client that drops while far
--- away produces no `playerDropped` at all.
---
--- Five handlers hung off that one event. If it does not fire, none of them run:
---   stuetze.lua  the Stütze keeps paying a character nobody is playing
---   jobs.lua     a worker's shift never settles, so they are never paid
---   sv_main.lua  the session row stays open forever
---   sv_actions.lua  an in-memory table leaks one entry per drop
---
--- The harness fires `playerDropped` synchronously by hand, so 291 green checks
--- could never see this. It is the same class of bug as the oxmysql shim: the
--- test world was not the real world.
---
--- The fix is not a better event, it is a different primitive. `GetPlayerName`
--- reads the engine's player list directly and is unaffected by entity scoping,
--- so anything this resource believes about a connection can be reconciled
--- against it. Teardown is registered here once and run from exactly one place,
--- which is what makes "the event did not arrive" survivable.

local RESOURCE = GetCurrentResourceName()

--- How often to ask the engine who is actually still connected.
--- Comfortably below the shortest interval anything here depends on (the Stütze
--- pays every `economy.stuetze.interval_sec`, default 900), so a missed payout
--- is impossible long before the watchdog notices.
local RECONCILE_INTERVAL_MS = 30000

SessionGuard = {}

--- Teardown steps, grouped by the order they must run in.
---
--- The order is not cosmetic. Settling a shift and stopping the Stütze both need
--- the character to still be the active one, so closing the session has to come
--- last. Registration order inside a phase is preserved and is the tiebreaker.
local Settle, Stop, Close = {}, {}, {}

--- Register a step. `fn(src)` runs during release.
local function register(bucket, name, fn)
  bucket[#bucket + 1] = { name = name, fn = fn }
end

--- Money owed to the character is settled first, while the session that earned
--- it is still open.
function SessionGuard.onSettle(name, fn)
  register(Settle, name, fn)
end

--- Per-connection timers are stopped next, so nothing can fire again mid-release.
function SessionGuard.onStop(name, fn)
  register(Stop, name, fn)
end

--- Session bookkeeping is closed last. Anything registered here must not depend
--- on the character still being active.
function SessionGuard.onClose(name, fn)
  register(Close, name, fn)
end

--- Run every registered step for one slot, exactly once.
---
--- `reason` is only for the log line. A slot that is released twice — once by the
--- real event, once by the watchdog — must not settle twice, so the guard is
--- idempotent per slot rather than relying on the two paths never overlapping.
local Released = {}

function SessionGuard.release(src, reason)
  if Released[src] then return end
  Released[src] = true

  -- A reconnection reuses the slot. Forgetting the mark here is what would let a
  -- second release settle a shift twice.
  SetTimeout(0, function() Released[src] = nil end)

  for _, phase in ipairs({ Settle, Stop, Close }) do
    for _, step in ipairs(phase) do
      -- One broken step must not strand the rest: a failure to settle wages is
      -- bad, but a failure to close the session afterwards is worse.
      local ok, err = pcall(step.fn, src)
      if not ok then
        print(('[%s] session guard: step "%s" failed for slot %s (%s): %s'):format(
          RESOURCE, step.name, tostring(src), tostring(reason), tostring(err)))
      end
    end
  end

  print(('[%s] session released for slot %s (%s)'):format(RESOURCE, tostring(src), tostring(reason)))
end

--- Compare what we believe against what the engine says, and release the
--- difference. Split out from the thread so it can be called directly by tests.
function SessionGuard.reconcile()
  local stale = 0

  for _, src in ipairs(Identity.activeSlots()) do
    if not GetPlayerName(src) then
      stale = stale + 1
      SessionGuard.release(src, 'watchdog: slot released by the engine')
    end
  end

  return stale
end

--- Close sessions left open by a previous run.
---
--- A hard shutdown — power cut, `Stop-Process`, an OS-level crash — never gets to
--- run any teardown at all. Those rows would otherwise stay `disconnected_at IS
--- NULL` forever, which makes "who was online" unanswerable and quietly poisons
--- every later query that joins on an open session. Same reasoning as the duty
--- reset in jobs.lua: the world did not exist between the crash and the restart.
local function closeOrphanedSessions()
  local closed = Db.update(
    'UPDATE sessions SET disconnected_at = NOW() WHERE disconnected_at IS NULL',
    {}, 'guard:closeOrphans')

  if closed and closed > 0 then
    print(('[%s] closed %d session(s) left open by a previous run'):format(RESOURCE, closed))
  end

  return closed or 0
end

SessionGuard.sweepOrphans = closeOrphanedSessions

-- The real event, kept because it is immediate and free. It is no longer the
-- mechanism the correctness of teardown rests on.
AddEventHandler('playerDropped', function()
  SessionGuard.release(source, 'playerDropped')
end)

CreateThread(function()
  -- Wait for the connection, not for the resource: a watchdog started before the
  -- database is reachable would reconcile against an empty world and report
  -- every player as gone.
  Db.ready(function()
    closeOrphanedSessions()

    while true do
      Wait(RECONCILE_INTERVAL_MS)
      SessionGuard.reconcile()
    end
  end)
end)

exports('release', SessionGuard.release)
exports('reconcile', SessionGuard.reconcile)