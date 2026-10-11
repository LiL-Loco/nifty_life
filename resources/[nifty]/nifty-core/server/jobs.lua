--- Jobs (ADR-0008).
---
--- Two decisions shape this module, and both are about what a job is *not*:
---
---   * It is not a progression system. There is no level, no unlock, no
---     qualification. Anyone may join anything, at any time, with no cooldown.
---     A department that is empty because nobody qualified for it is a dead
---     server on a 48-slot weekend, and 48 slots is the entire population.
---   * It is not a job you hold. You may hold as many as you like, and be on
---     duty for at most one at a time — being two places at once is not a
---     clever exploit, it is just not a thing that can be paid for honestly.
---
--- What a job *is*: a wage table, a duty flag, and somewhere to stand.

local RESOURCE = GetCurrentResourceName()

Jobs = {}

--- Job definitions, loaded once like the item catalogue. Static config.
local Definitions = {}

local function loadDefinitions()
  Definitions = {}

  local rows = Db.all([[
    SELECT code, name, kind, is_emergency, base_x, base_y, base_z FROM job_defs
  ]], {}, 'jobs:definitions')

  for _, row in ipairs(rows) do
    Definitions[row.code] = {
      code = row.code,
      name = row.name,
      kind = row.kind,
      isEmergency = tonumber(row.is_emergency) == 1,
      base = { x = row.base_x, y = row.base_y, z = row.base_z },
    }
  end

  print(('[%s] loaded %d job definitions'):format(RESOURCE, #rows))
end

--- Hourly wage for a job. Missing setting means zero, not a fallback guess —
--- an unknown job must pay nothing rather than pay something plausible.
function Jobs.wagePerHour(code)
  local def = Definitions[code]
  if not def then return 0 end

  return Db.money.toNumber(GetSetting('job.wage_per_hour.' .. def.code, 0))
end

function Jobs.list()
  local result = {}

  for _, def in pairs(Definitions) do
    result[#result + 1] = {
      code = def.code,
      name = def.name,
      kind = def.kind,
      isEmergency = def.isEmergency,
      base = def.base,
      wagePerHour = Jobs.wagePerHour(def.code),
    }
  end

  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

function Jobs.get(code)
  return Definitions[code]
end

-- ---------------------------------------------------------------------------
-- Joining and leaving
-- ---------------------------------------------------------------------------

--- Sign up. Open to everyone by ADR-0008, so there is nothing to check beyond
--- "does this job exist" — a job nobody can reach is a dead feature, not a
--- gated one.
function Jobs.join(characterId, code)
  if not Definitions[code] then return false, 'unknown job' end

  local existing = Db.one([[
    SELECT 1 AS joined FROM character_jobs WHERE character_id = ? AND job_code = ?
  ]], { characterId, code }, 'jobs:already')

  if existing then return false, 'already signed up' end

  local ok = Db.insert([[
    INSERT INTO character_jobs (character_id, job_code, is_duty) VALUES (?, ?, 0)
  ]], { characterId, code }, 'jobs:join')

  if ok == nil then return false, 'could not sign up' end

  Jobs.sync(characterId)
  return true, nil
end

function Jobs.leave(characterId, code)
  if not Definitions[code] then return false, 'unknown job' end

  -- Going off duty first means nobody can leave mid-shift and walk away from
  -- the earnings they had already accrued.
  if Jobs.isOnDuty(characterId, code) then
    Jobs.endDuty(characterId, code)
  end

  local affected = Db.update([[
    DELETE FROM character_jobs WHERE character_id = ? AND job_code = ?
  ]], { characterId, code }, 'jobs:leave')

  if affected == nil or affected == 0 then return false, 'not signed up' end

  Jobs.sync(characterId)
  return true, nil
end

function Jobs.listFor(characterId)
  local rows = Db.all([[
    SELECT cj.job_code, cj.is_duty, cj.duty_since, d.name, d.kind
      FROM character_jobs cj
      JOIN job_defs d ON d.code = cj.job_code
     WHERE cj.character_id = ?
     ORDER BY d.name
  ]], { characterId }, 'jobs:listFor')

  local result = {}

  for _, row in ipairs(rows) do
    result[#result + 1] = {
      code = row.job_code,
      name = row.name,
      kind = row.kind,
      onDuty = tonumber(row.is_duty) == 1,
      dutySince = row.duty_since,
    }
  end

  return result
end

--- Push the character's job list to their client. Same contract as the money and
--- inventory pushes: the server decides what is true.
function Jobs.sync(characterId, src)
  local list = Jobs.listFor(characterId)

  -- No src means "tell every session playing this character", which during
  -- normal play is exactly one.
  if src then
    return TriggerClientEvent('nifty:client:jobs', src, list)
  end

  for _, playerId in ipairs(GetPlayers()) do
    if Identity.getActiveCharacter(tonumber(playerId)) == characterId then
      TriggerClientEvent('nifty:client:jobs', tonumber(playerId), list)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Duty
-- ---------------------------------------------------------------------------

function Jobs.isOnDuty(characterId, code)
  local row = Db.one([[
    SELECT is_duty FROM character_jobs WHERE character_id = ? AND job_code = ?
  ]], { characterId, code }, 'jobs:isOnDuty')

  return row ~= nil and tonumber(row.is_duty) == 1
end

--- One character, one shift. Enforced here rather than by a partial unique
--- index because MariaDB has no such thing — a constraint that would need a
--- second table and a trigger is not worth it for a rule this easy to state.
local function isOnAnyDuty(characterId)
  local row = Db.one([[
    SELECT job_code FROM character_jobs WHERE character_id = ? AND is_duty = 1 LIMIT 1
  ]], { characterId }, 'jobs:onAnyDuty')

  return row and row.job_code or nil
end

--- Start a shift. Costs a payslip fee (the ADR-0009 sink that stops "clocking in
--- and standing still" from being free) and refuses if the character is already
--- working somewhere.
function Jobs.startDuty(characterId, code)
  if not Definitions[code] then return false, 'unknown job' end

  local signedUp = Db.one([[
    SELECT 1 AS signed_up FROM character_jobs WHERE character_id = ? AND job_code = ?
  ]], { characterId, code }, 'jobs:signedUp')

  if not signedUp then return false, 'not signed up for this job' end

  local elsewhere = isOnAnyDuty(characterId)
  if elsewhere then
    return false, ('already on duty as %s'):format(elsewhere)
  end

  local fee = Economy.round(GetSetting('economy.price.payslip', 0))
  if fee > 0 then
    local paid, err = Economy.debit(characterId, 'cash', fee, 'job_wage', 'job', code)
    if not paid then return false, err end
  end

  local affected = Db.update([[
    UPDATE character_jobs SET is_duty = 1, duty_since = NOW()
     WHERE character_id = ? AND job_code = ? AND is_duty = 0
  ]], { characterId, code }, 'jobs:startDuty')

  if affected == nil or affected == 0 then return false, 'could not start' end

  Jobs.sync(characterId)
  return true, nil
end

--- Finish a shift and pay for the time actually worked.
---
--- The wage is pro-rated by real elapsed seconds, because the alternative —
--- paying a flat rate per shift — turns "clock in, stand in a corner" into the
--- optimal strategy. Minimum seconds guards the opposite abuse: clocking in and
--- out repeatedly to farm a tiny payout per transaction.
function Jobs.endDuty(characterId, code)
  if not Jobs.isOnDuty(characterId, code) then return false, 'not on duty' end

  local row = Db.one([[
    SELECT duty_since FROM character_jobs WHERE character_id = ? AND job_code = ?
  ]], { characterId, code }, 'jobs:dutySince')

  local seconds = 0
  if row and row.duty_since then
    -- Computed from the database's own clock: the server's wall clock and the
    -- game's are not the same clock, and only one of them is authoritative.
    local elapsed = Db.one([[
      SELECT TIMESTAMPDIFF(SECOND, duty_since, NOW()) AS elapsed
        FROM character_jobs WHERE character_id = ? AND job_code = ?
    ]], { characterId, code }, 'jobs:elapsed')

    if elapsed and elapsed.elapsed then
      seconds = math.max(0, tonumber(elapsed.elapsed) or 0)
    end
  end

  local affected = Db.update([[
    UPDATE character_jobs SET is_duty = 0, duty_since = NULL
     WHERE character_id = ? AND job_code = ?
  ]], { characterId, code }, 'jobs:endDuty')

  if affected == nil or affected == 0 then return false, 'could not end shift' end

  local minimum = tonumber(GetSetting('job.duty.min_seconds', 300)) or 300
  local payout = 0

  if seconds < minimum then
    -- Below the minimum the shift pays nothing at all. The fee is already gone;
    -- that is the cost of a shift too short to count, and it is visible.
    print(('[%s] %s worked %s for %ds — under the %ds minimum, unpaid'):format(
      RESOURCE, characterId, code, seconds, minimum))
  else
    local hourly = Jobs.wagePerHour(code)
    payout = Economy.round(hourly * (seconds / 3600))

    if payout > 0 then
      Economy.credit(characterId, 'cash', payout, 'job_payoff', 'job', code)
    end
  end

  Jobs.sync(characterId)
  return true, seconds, payout
end

-- ---------------------------------------------------------------------------
-- Life cycle
-- ---------------------------------------------------------------------------

--- On boot, nobody is on duty.
---
--- ADR-0004 freezes the server Monday to Thursday, so a character left flagged
--- on duty across a shutdown was not working — the world did not exist. Clearing
--- it is not a convenience, it is the same reasoning that keeps parked vehicles
--- where they were: the freeze preserves the world, it does not preserve an
--- open timesheet.
AddEventHandler('onResourceStart', function(resource)
  if resource ~= RESOURCE then return end

  -- Wait for the connection, not for the resource: see the note in settings.lua.
  -- Without a live database this used to report "loaded 0 job definitions" and
  -- carry on, which is a server that accepts players it cannot pay.
  Db.ready(function()
    loadDefinitions()
    Db.update([[UPDATE character_jobs SET is_duty = 0, duty_since = NULL WHERE is_duty = 1]],
      {}, 'jobs:clearDuty')
  end)
end)

--- Leaving a job that pays out is the last chance to settle up, so it happens
--- here rather than in `Jobs.leave` — which may be called from anywhere.
---
--- Registered with the session guard, not hooked to `playerDropped`: in OneSync
--- big mode a distant disconnect delivers no event, and an unsettled shift means
--- a worker who logged off never gets paid.
SessionGuard.onSettle('jobs', function(src)
  local characterId = Identity.getActiveCharacter(src)
  if not characterId then return end

  local row = Db.one([[
    SELECT job_code FROM character_jobs WHERE character_id = ? AND is_duty = 1 LIMIT 1
  ]], { characterId }, 'jobs:onDutyAtDrop')

  if row and row.job_code then
    Jobs.endDuty(characterId, row.job_code)
  end
end)

exports('list', Jobs.list)
exports('join', Jobs.join)
exports('leave', Jobs.leave)
exports('startDuty', Jobs.startDuty)
exports('endDuty', Jobs.endDuty)