--- Persistence layer (ADR-0005, ADR-0014 step 2).
---
--- Rules this module exists to enforce:
---   * Every query is parameterised. No caller concatenates a value into SQL.
---     That is what makes "the client is untrusted" implementable rather than
---     aspirational — there is no query in this codebase a client can reshape.
---   * Errors are logged with context, never swallowed. A silent failure here
---     surfaces days later as a player with no money and no explanation.

local RESOURCE = GetCurrentResourceName()

Db = {}

--- Wrap oxmysql's await-style calls so every failure is logged once, here,
--- rather than being handled (or not) in a hundred call sites.
---
--- The API is `MySQL.<method>.await`, NOT `exports.oxmysql:await`. The export
--- existed in older oxmysql builds and is gone from the current one; calling it
--- raises "No such export await in resource oxmysql" on the first query, which
--- is what a real FXServer run showed. Every failure then returns nil, the
--- module reports "loaded 0 settings", and the server runs happily on an empty
--- world — which is the worst possible failure mode and worth the extra lines.
local function guard(label, sql, params)
  local ok, result = pcall(function()
    return MySQL.query.await(sql, params or {})
  end)

  if not ok then
    print(('[%s] query failed (%s): %s\n  sql: %s'):format(
      RESOURCE, label, tostring(result), sql))
    return nil
  end

  return result
end

--- Run `cb` once the database connection is actually up, in the order the
--- callbacks were registered.
---
--- The previous approach was `GetResourceState('oxmysql') ~= 'started'` plus a
--- fixed two-second timeout, which is a guess: oxmysql starts, then opens the
--- socket, and a database that is not running produces ECONNREFUSED in between.
---
--- Ordering is implemented here rather than assumed. `MySQL.ready(cb)` spins up
--- a THREAD PER CALL, so two calls made in the same tick race — and the order
--- genuinely matters: the item catalogue reads capacities that only exist once
--- settings are loaded. A queue makes the dependency explicit instead of
--- leaving it to thread scheduling.
local readyQueue = {}
local readyStarted = false
local readyComplete = false

local function runReady(callback)
  local ok, err = pcall(callback)
  if not ok then
    print(('[%s] startup callback failed: %s'):format(RESOURCE, tostring(err)))
  end
end

local function drainReady()
  while #readyQueue > 0 do
    runReady(table.remove(readyQueue, 1))
  end
end

function Db.ready(cb)
  if type(cb) ~= 'function' then return end

  -- Already connected: run it now. This branch is not an optimisation, it is
  -- the fix for a real bug — an earlier version registered the connection
  -- callback only on the FIRST call, so every later caller queued a callback
  -- that nothing would ever drain. Settings loaded and then jobs, inventory and
  -- the item catalogue silently never ran.
  if readyComplete then
    return runReady(cb)
  end

  readyQueue[#readyQueue + 1] = cb

  if readyStarted then return end
  readyStarted = true

  if not MySQL or not MySQL.ready then
    print(('[%s] FATAL: oxmysql did not load — it must start before this resource.'):format(RESOURCE))
    return
  end

  MySQL.ready(function()
    readyComplete = true
    drainReady()
  end)
end

--- Single row.
---
--- Drivers return a ROW ARRAY for a SELECT. Handing that array back to a caller
--- that expects a row does not fail loudly — it fails silently, because in Lua
--- `row.cash` on an array is nil and `rows ~= nil` on an empty array is TRUE.
--- The second of those is the dangerous one: the whitelist check would treat
--- "no such account" as "account found".
---
--- So this normalises both driver shapes — array or bare row — and, crucially,
--- turns "no rows" into nil rather than an empty table.
function Db.one(sql, params, label)
  local result = guard(label or 'one', sql, params)
  if type(result) ~= 'table' then return nil end

  -- An array: take the first row.
  if result[1] ~= nil then return result[1] end

  -- No rows at all. Must be nil, not {} — see above.
  if next(result) == nil then return nil end

  -- Already a bare row.
  return result
end

--- Row list.
function Db.all(sql, params, label)
  return guard(label or 'all', sql, params) or {}
end

--- Insert and return the new id (first value).
function Db.insert(sql, params, label)
  local result = guard(label or 'insert', sql, params)
  if result == nil then return nil end
  return result.insertId
end

--- Return number of affected rows, or nil on failure.
function Db.update(sql, params, label)
  local result = guard(label or 'update', sql, params)
  if result == nil then return nil end
  return result.affectedRows or 0
end

--- Run a set of statements atomically. Used wherever money or inventory moves,
--- so a partial write can never leave a player with items they did not pay for.
function Db.transaction(statements, label)
  local queries = {}
  for _, stmt in ipairs(statements) do
    queries[#queries + 1] = { query = stmt.sql, values = stmt.params or {} }
  end

  local ok, result = pcall(function()
    return MySQL.transaction.await(queries)
  end)

  if not ok or not result then
    print(('[%s] transaction failed (%s): %s'):format(
      RESOURCE, label or 'tx', tostring(result)))
    return false
  end

  return true
end

--- ADR-0009: money is DECIMAL, and Lua numbers are doubles. Every value that
--- came from or goes to the database must pass through here so that no code
--- path is allowed to invent its own rounding.
Db.money = {
  toNumber = function(v) return tonumber(v) or 0.0 end,
}

--- True when the connection string is configured. Checked at start so a
--- missing config fails loudly instead of on the first player connect.
function Db.isConfigured()
  local ok = pcall(function()
    return GetConvar('mysql_connection_string')
  end)
  return ok and #GetConvar('mysql_connection_string') > 0
end

AddEventHandler('onResourceStart', function(resource)
  if resource ~= RESOURCE then return end

  if not Db.isConfigured() then
    print(('[%s] FATAL: mysql_connection_string is not set. ' ..
      'Copy server.cfg.example to server.cfg and fill it in.'):format(RESOURCE))
    return
  end

  print(('[%s] persistence layer loaded'):format(RESOURCE))
end)