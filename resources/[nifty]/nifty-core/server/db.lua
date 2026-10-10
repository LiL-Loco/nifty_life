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
local function guard(label, sql, params)
  local ok, result = pcall(function()
    return exports.oxmysql:await(sql, params or {})
  end)

  if not ok then
    print(('[%s] query failed (%s): %s\n  sql: %s'):format(
      RESOURCE, label, tostring(result), sql))
    return nil
  end

  return result
end

--- Single row.
function Db.one(sql, params, label)
  return guard(label or 'one', sql, params)
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
    return exports.oxmysql:await_transaction(queries)
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