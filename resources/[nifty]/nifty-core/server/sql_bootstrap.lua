--[[
  Schema bootstrap — runs the bundled `sql/init.sql` once on resource start,
  before any other nifty-* module queries the database.

  Why this lives in nifty-core:
    The base is the first nifty-* resource in `server.cfg`, and every other
    module reaches the database through `Db.ready(...)`. Registering the
    bootstrap inside that same ready-queue means the schema is up before
    `settings.lua` loads its cache, before the item catalogue is scanned, and
    before identity.lua opens a session for the first player.

  Why one file, not the migration chain:
    The migration chain under `database/migrations/` is the right shape for a
    shipping server with a history. A fresh checkout has no history, and
    `sql/init.sql` is the same chain collapsed into one file. It uses
    `CREATE TABLE IF NOT EXISTS` everywhere, so re-running it is a no-op.

  Why this file handles DELIMITER:
    `init.sql` defines stored procedures (confirm_portal_email, the
    create-character-from-web procedure). MariaDB stored-procedure bodies
    contain `;` that must NOT be treated as statement terminators. The mysql
    client solves this with `DELIMITER //` and `DELIMITER ;` directives.
    oxmysql does not process DELIMITER — it talks to the server directly —
    so the pre-processor below rewrites the file into plain `;`-terminated
    statements before handing them to MySQL.
]]

local RESOURCE = GetCurrentResourceName()

-- Does this statement have any actual SQL? Whitespace alone, or only MySQL
-- directives like `USE`, `SET`, `DELIMITER`, is not a query the server will run.
-- A `/* ... */` block comment is also skipped — the parser would otherwise
-- collect a whole section like the file's long header banner as one "statement".
local function hasSql(stmt)
  local stripped = stmt
    :gsub("/%*.-%*/", " ")                    -- block comment
    :gsub("%-%-[^\n]*", " ")                  -- line comment
    :gsub("^%s*USE%s+%S+%s*;?%s*$", "")       -- USE x
    :gsub("^%s*SET%s+.-;?%s*$", "")          -- SET x = y
    :gsub("^%s*DELIMITER%s+%S+%s*$", "")      -- DELIMITER x
  return stripped:match("%S") ~= nil
end

-- Split a SQL file into a list of statements, respecting `DELIMITER // ... //`
-- blocks. Within a `DELIMITER //` block, every line is appended to the current
-- buffer; the buffer is pushed as one statement on the first `//` terminator.
-- Outside (delimiter is `;`), each line that ends with `;` closes one statement.
local function splitSqlStatements(sql)
  local statements = {}
  local delim = ";"
  local buf = {}

  for line in sql:gmatch("([^\n]*)\n?") do
    local newDelim = line:match("^%s*DELIMITER%s+(%S+)")
    if newDelim then
      if #buf > 0 then
        local joined = table.concat(buf, "\n")
        if hasSql(joined) then
          table.insert(statements, joined)
        end
        buf = {}
      end
      delim = newDelim
    else
      -- Escape the delimiter so it can be used as a literal in a Lua pattern.
      local esc = delim:gsub("%%", "%%%%"):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
      if line:find(esc .. "%s*$") then
        -- Strip the trailing delimiter from this line, append to buf, and
        -- the buffer is now a complete statement.
        local trimmed = line:gsub(esc .. "%s*$", "")
        table.insert(buf, trimmed)

        local joined = table.concat(buf, "\n")
        if hasSql(joined) then
          table.insert(statements, joined)
        end
        buf = {}
      else
        table.insert(buf, line)
      end
    end
  end

  -- Anything still in the buffer at EOF (e.g. a trailing comment block) is
  -- appended as one statement so it is not silently dropped.
  if #buf > 0 then
    local joined = table.concat(buf, "\n")
    if hasSql(joined) then
      table.insert(statements, joined)
    end
  end

  return statements
end

-- Run the split statements one at a time. Wrapping the whole thing in a
-- transaction would fail on the DELIMITER-boundary DDL/CREATE PROCEDURE
-- pairs in MariaDB, so each statement is its own query.
--
-- CRITICAL: oxmysql THROWS a Lua error on a SQL failure, it does not return
-- nil. So both paths must be handled: a pcall to catch the throw (so the
-- loop can report WHICH statement broke), and a nil check on the return
-- (for paths that produce a value). Without the pcall, the throw escapes
-- the function and db.lua's `runReady` swallows it as a generic
-- "startup callback failed" without saying which statement.
local function runStatements(statements)
  for i, stmt in ipairs(statements) do
    local ok, result = pcall(MySQL.query.await, stmt)
    if not ok or result == nil then
      -- When pcall catches a throw, `result` is the error message. When
      -- oxmysql returns nil, `result` is nil and the throw was either empty
      -- or the path oxmysql uses for "no error but no rows". Both need to print
      -- something useful so the next run is not a guess.
      local err = (not ok) and tostring(result) or '(oxmysql returned nil with no error message)'
      print(('[%s] schema bootstrap failed at statement %d\n  error: %s\n  first line: %s'):format(
        RESOURCE, i, err, (stmt:match("^[^\n]+") or '<empty>')))
      return false
    end
  end
  return true
end

local function bootstrap()
  local sql = LoadResourceFile(RESOURCE, 'sql/init.sql')
  if not sql then
    print(('[%s] FATAL: sql/init.sql missing from resource files. ' ..
      'Add it to the `files` block in fxmanifest.lua.'):format(RESOURCE))
    return
  end

  local statements = splitSqlStatements(sql)
  print(('[%s] schema bootstrap: %d statement(s)'):format(RESOURCE, #statements))

  if runStatements(statements) then
    print(('[%s] schema bootstrap complete'):format(RESOURCE))
  end
end

-- Hook into the same ready-queue the rest of the base uses. Because this
-- module is loaded between `server/db.lua` and `server/settings.lua` in the
-- manifest, and `Db.ready` is FIFO, the schema is up before any other
-- nifty-* resource reads from the database.
Db.ready(bootstrap)
