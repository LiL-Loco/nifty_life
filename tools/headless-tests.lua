-- ============================================================================
-- tools/headless-tests.lua
-- Nifty Life 2.0 — headless execution harness for the server layer.
--
-- WHY THIS EXISTS
--   `luac -p` proves a file parses. `database/verify.ps1` proves the SCHEMA
--   holds. Neither proves that Economy.apply, Shop.buy or Jobs.endDuty actually
--   work — they only ever ran through a game server that has never been started.
--   The vertical slice showed what that costs: 44 green checks, zero reachable
--   code.
--
--   This harness loads the REAL server modules, stubs the small slice of the
--   FiveM API they touch, and executes them against a real MariaDB. Claims
--   become assertions.
--
-- WHAT IT IS NOT (read before trusting a green run)
--   * The DB driver is a shim that shells out to the `mariadb` CLI. The SQL is
--     the project's real SQL; the transport is not oxmysql. A bug in oxmysql
--     specifically would not be caught here.
--   * Transactions are issued as START TRANSACTION/COMMIT inside a single
--     client session, so atomicity IS exercised — but multi-statement rollback
--     semantics of a real connection pool are not.
--   * Appearance is not tested: it needs the collection natives, which is the
--     one thing this harness cannot provide.
--   * Natives, NUI and net events are out of scope. Still unverified.
--
-- USAGE (from the container):
--   lua5.4 tools/headless-tests.lua
--   NIFTY_DB_USER / NIFTY_DB_PASS / NIFTY_DB_NAME override the defaults.
-- ============================================================================

local DB_USER = os.getenv('NIFTY_DB_USER') or 'root'
local DB_PASS = os.getenv('NIFTY_DB_PASS') or 'test'
local DB_NAME = os.getenv('NIFTY_DB_NAME') or 'nifty_life'
local RESOURCE_ROOT = os.getenv('NIFTY_ROOT') or '.'

-- ============================================================================
-- Test runner
-- ============================================================================

local passed, failed = 0, 0
local failures = {}
local currentGroup = ''

local function group(name)
  currentGroup = name
  io.write('\n=== ', name, ' ===\n')
end

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    io.write('  PASS  ', name, '\n')
  else
    failed = failed + 1
    local message = detail and (' — ' .. detail) or ''
    failures[#failures + 1] = currentGroup .. ' / ' .. name
    io.write('  FAIL  ', name, message, '\n')

    -- Replay whatever the modules logged just before failing. Without this the
    -- harness reports "database error" and hides the actual MariaDB complaint,
    -- which is the one thing worth seeing.
    if #capturedPrints > 0 then
      for _, line in ipairs(capturedPrints) do
        io.write('         ', line, '\n')
      end
      capturedPrints = {}
    end
  end
end

-- ============================================================================
-- FiveM native stubs
--
-- Only what the server modules actually reference. Anything a module calls
-- that is not defined here is a bug the harness reports loudly rather than
-- silently tolerating — a stubbed-out world that lies is worse than no world.
-- ============================================================================

_G.GetCurrentResourceName = function() return 'nifty-core' end
_G.GetResourceState = function() return 'started' end
_G.GetGameTimer = function() return 0 end
-- FiveM provides `json` as a Cfx global; the harness has no engine. This one
-- self-tests on load, so a wrong codec fails immediately rather than quietly
-- corrupting every appearance assertion that follows.
_G.json = dofile((RESOURCE_ROOT .. '/tools/json.lua'))

-- FiveM calls GetConvar with a single argument. The stub originally took `(_, key)`
-- and therefore read nil as the key, which made db.lua believe no connection
-- string was configured and log a FATAL on every load.
_G.GetConvar = function(key)
  if key == 'mysql_connection_string' then
    return DB_NAME .. '?user=' .. DB_USER .. '&password=' .. DB_PASS
  end
  return ''
end

--- The server prints are diagnostics, not test output — the modules log loudly
--- on every refusal path the suite deliberately walks. They are captured
--- instead of printed, and replayed only when a check FAILS, because a silent
--- harness that swallows the error it needs is worse than a noisy one.
local capturedPrints = {}
_G.print = function(...)
  local parts = {}
  for _, value in ipairs({ ... }) do parts[#parts + 1] = tostring(value) end
  capturedPrints[#capturedPrints + 1] = table.concat(parts, ' ')
end
_G.capturedPrints = capturedPrints

--- Event handlers are collected rather than dropped. `onResourceStart` is what
--- loads the item catalogue and the settings cache, so a harness that ignores
--- it tests a server with an empty world and every lookup fails for the wrong
--- reason.
local registeredHandlers = {}
_G.AddEventHandler = function(name, handler)
  registeredHandlers[name] = registeredHandlers[name] or {}
  table.insert(registeredHandlers[name], handler)
end
_G.registeredHandlers = registeredHandlers

local timers = {}
_G.SetTimeout = function(ms, fn) local id = #timers + 1; timers[id] = fn; return id end
_G.ClearTimeout = function(id) timers[id] = nil end

_G.RegisterNetEvent = function() end
_G.RegisterCommand = function() end
_G.DropPlayer = function() end
_G.GetPlayers = function() return {} end
--- Fake connections. `GetPlayerIdentifiersByType` must answer truthfully, because
--- the whitelist and identity layers read the Discord ID straight off the
--- connection — that is the point of ADR-0007. A stub returning an empty list
--- would make every identity test exercise the "no account" path instead.
local FakePlayers = {}
_G.FakePlayers = FakePlayers

--- Register a fake connection with a Discord ID. Returns the slot id.
function FakePlayers.connect(src, discordId)
  FakePlayers[src] = discordId
  return src
end

function FakePlayers.disconnect(src)
  FakePlayers[src] = nil
end

_G.GetPlayerIdentifiersByType = function(src, kind)
  if kind == 'discord' and FakePlayers[src] then
    return { FakePlayers[src] }
  end
  return {}
end

_G.GetPlayerLicense = function(src) return 'license-' .. tostring(src) end

--- Events the modules try to send. Recorded, not sent, so a test can assert
--- that something was pushed — and so nothing pretends a player received it.
local sentEvents = {}
_G.TriggerClientEvent = function(name, target, payload)
  sentEvents[#sentEvents + 1] = { name = name, target = target, payload = payload }
end
_G.sentEvents = sentEvents

-- ============================================================================
-- oxmysql shim
--
-- Statements are executed through the `mariadb` CLI over stdin, so no SQL ever
-- passes through a shell quoting layer. Placeholders are escaped to literals —
-- which is the whole reason the project parameterises queries in the first
-- place: there is exactly one place where a value becomes text.
-- ============================================================================

local function escapeValue(value)
  local kind = type(value)

  if kind == 'number' then return tostring(value) end
  if kind == 'boolean' then return value and '1' or '0' end
  if kind == 'nil' then return 'NULL' end

  local s = tostring(value)
  s = s:gsub('\\', '\\\\'):gsub("'", "\\'"):gsub('\n', '\\n'):gsub('\r', '\\r')
  return "'" .. s .. "'"
end

--- Replace each `?` in order. A query with fewer placeholders than parameters is
--- a bug in the caller, so it fails loudly rather than running partially bound.
local function bind(sql, params)
  if not params or #params == 0 then return sql end

  local index = 0
  local out = sql:gsub('%?', function()
    index = index + 1
    if params[index] == nil then
      error(('bind: placeholder %d has no value — %s'):format(index, sql))
    end
    return escapeValue(params[index])
  end)

  if index ~= #params then
    error(('bind: %d placeholders but %d values'):format(index, #params))
  end

  return out
end

--- Run SQL, return raw stdout.
--
-- SQL goes through a temp file rather than `-e`, for two reasons: `io.popen`
-- closes the pipe before it can be read, and a file means no statement ever
-- passes through a shell quoting layer. Written to a file, executed, read back.
local SQL_FILE = '/tmp/nifty-headless.sql'

local function runSql(sql)
  local handle, err = io.open(SQL_FILE, 'w')
  if not handle then error('cannot write SQL file: ' .. tostring(err)) end

  handle:write(sql)
  handle:write('\n')
  handle:close()

  -- TCP is forced explicitly: sharing another container's network namespace
  -- does not move the socket, and the client would otherwise look for a unix
  -- socket that does not exist here.
  local cmd = ('mariadb --batch --raw --protocol=TCP -h 127.0.0.1 -P 3306 ' ..
    '--default-character-set=utf8mb4 -u%s -p%s %s < %s 2>&1'):format(
    DB_USER, DB_PASS, DB_NAME, SQL_FILE)

  local pipe = io.popen(cmd, 'r')
  if not pipe then error('cannot run mariadb client') end

  local output = pipe:read('*a') or ''
  pipe:close()

  return output
end

--- TSV -> row list.
---
--- Three behaviours of the `mariadb --batch` client drive the shape of this:
---   * A SELECT returning ZERO rows prints no header at all — not even an empty
---     one, sometimes not even a newline. Parsing that as "header, then a blank
---     data row" produces a phantom row with every field nil, and the caller
---     dies on `tonumber(row.slot)` two modules away from the real cause.
---   * SQL NULL arrives as `NULL`, or as `\N` with `--raw`.
---   * Lines end CRLF, so a "NULL" that is really "NULL\r" is a truthy string.
local function parseTsv(output)
  if output == nil then return nil end

  local lines = {}
  for line in (output .. '\n'):gmatch('([^\n]*)\n') do
    lines[#lines + 1] = (line:gsub('\r$', ''))
  end

  -- Header must contain at least one column name. Without this a blank line
  -- becomes the header and the whole result is silently misaligned.
  local columns = {}
  for name in lines[1]:gmatch('[^\t]+') do
    columns[#columns + 1] = name
  end

  if #columns == 0 then return nil end

  local rows = {}

  for i = 2, #lines do
    if lines[i] ~= '' then
      -- An explicit counter, and a sentinel for NULL.
      --
      -- `values[#values + 1] = nil` looks like it records a NULL, but assigning
      -- nil to a table slot does not create the slot — `#values` stays the same,
      -- so the NEXT value is written to the same index and every column after a
      -- NULL shifts one to the left. A character with a NULL last name and a NULL
      -- date of birth came back with gender under last_name and the appearance
      -- JSON under date_of_birth. The database was right the whole time; the
      -- reader was misaligned.
      local values = {}
      local count = 0

      for value in (lines[i] .. '\t'):gmatch('([^\t]*)\t') do
        count = count + 1
        if value == 'NULL' or value == '\\N' then
          values[count] = false
        else
          values[count] = value
        end
      end

      local row = {}
      for index, name in ipairs(columns) do
        local value = values[index]
        -- A branch, never `(value == false) and nil or value`: that is the same
        -- trap as above — `true and nil` is nil, and `nil or value` is value,
        -- so the NULL string came straight back. (This file had already been
        -- written up in LEARNINGS.md, and still got it wrong once.)
        if value == false then
          row[name] = nil
        else
          row[name] = value
        end
      end
      rows[#rows + 1] = row
    end
  end

  return rows
end

--- Row values arrive as strings. These comparisons must therefore compare the
--- same way the server would after a real driver's own conversion — if these
--- helpers ever lie about a type, every numeric assertion above them becomes
--- meaningless, so they are deliberately strict.
local function toNumber(value)
  if type(value) == 'number' then return value end
  return tonumber(tostring(value))
end

local function isPositiveZero(value)
  return type(value) == 'number' and value > 0
end

--- Normalise a statement so it can be followed by a probe query. Statements fed
--- through a FILE (rather than `-e`) are not newline-separated the way they are
--- on the command line, so each one has to be explicitly terminated or the probe
--- is parsed as a syntax error inside the statement.
local function terminate(statement)
  local trimmed = statement:gsub('%s+$', '')
  if trimmed:sub(-1) == ';' then
    return trimmed
  end
  return trimmed .. ';'
end
local Oxmysql = {}
Oxmysql.__index = Oxmysql

function Oxmysql:await(sql, params)
  local bound = bind(sql, params)
  local verb = bound:match('^%s*(%a+)') or ''
  verb = verb:upper()

  if verb == 'INSERT' then
    local output = runSql(terminate(bound) .. '\nSELECT LAST_INSERT_ID();')
    if output:find('ERROR') then error(output) end
    local rows = parseTsv(output)
    return { insertId = rows and rows[1] and toNumber(rows[1]['LAST_INSERT_ID()']) or 0 }
  end

  if verb == 'UPDATE' or verb == 'DELETE' then
    -- ROW_COUNT() must be read immediately after the statement, in the same
    -- session, or it reports the previous statement's result. This is exactly
    -- what makes the guarded "0 rows means refused" pattern testable.
    local output = runSql(terminate(bound) .. '\nSELECT ROW_COUNT();')
    if output:find('ERROR') then error(output) end
    local rows = parseTsv(output)
    return { affectedRows = rows and rows[1] and toNumber(rows[1]['ROW_COUNT()']) or 0 }
  end

  local output = runSql(bound)
  if output:find('ERROR') then error(output) end

  return parseTsv(output)
end

function Oxmysql:await_transaction(queries)
  -- One client session, one transaction. A failing statement aborts before
  -- COMMIT, so a half-applied multi-statement write is observable here — which
  -- is the behaviour the identity layer relies on.
  local parts = { 'START TRANSACTION;' }

  for _, query in ipairs(queries) do
    parts[#parts + 1] = bind(query.query, query.values) .. ';'
  end

  parts[#parts + 1] = 'COMMIT;'

  local output = runSql(table.concat(parts, '\n'))
  if output:find('ERROR') then return false end

  return true
end

-- The modules call `exports.oxmysql:await(sql, params)` and also register their
-- own exports with `exports('name', fn)`. FiveM's `exports` is both indexable
-- and callable, so the shim must be too — an earlier version was a plain table
-- and identity.lua crashed on load. That mismatch is exactly the class of bug
-- this harness exists to find.
local registeredExports = {}

_G.exports = setmetatable({
  oxmysql = setmetatable({}, Oxmysql),
}, {
  __call = function(_, name, fn)
    registeredExports[name] = fn
  end,
})

_G.registeredExports = registeredExports

-- ============================================================================
-- Load the real server modules
--
-- These are the project's own files, unmodified. If one of them calls a native
-- that is not stubbed above, this fails loudly — which is the point.
-- ============================================================================

local function load(path)
  local chunk, err = loadfile(path)
  if not chunk then
    error(('cannot load %s: %s'):format(path, tostring(err)))
  end
  return chunk()
end

local RES = RESOURCE_ROOT .. '/resources/[nifty]/nifty-core'

load(RES .. '/shared/constants.lua')
load(RES .. '/shared/appearance_config.lua')
load(RES .. '/server/db.lua')
load(RES .. '/server/settings.lua')
load(RES .. '/server/validate.lua')
load(RES .. '/server/identity.lua')
load(RES .. '/server/economy.lua')
load(RES .. '/server/stuetze.lua')
load(RES .. '/server/inventory.lua')
load(RES .. '/server/ownership.lua')
load(RES .. '/server/jobs.lua')
load(RES .. '/server/shop.lua')
load(RES .. '/server/phone.lua')

-- Fire `onResourceStart` exactly as FiveM would. This is what loads the settings
-- cache and the item catalogue; skipping it leaves the modules loaded but their
-- world empty, and every subsequent failure points at the wrong thing.
for _, handler in ipairs(registeredHandlers['onResourceStart'] or {}) do
  handler('nifty-core')
end

-- ============================================================================
-- Fixtures
-- ============================================================================

local function sql(statement)
  local output = runSql(statement)
  if output:find('ERROR') then error('fixture failed: ' .. output) end
end

local TEST_ACCOUNT = 'acct-test'
local OTHER_ACCOUNT = 'acct-test-2'
local TEST_CHARACTER = 'chr-headless-0001'
local OTHER_CHARACTER = 'chr-headless-0002'
local TEST_PROPERTY = 'prp-headless-0001'

--- Single-quoted SQL literal. These are fixture identifiers hardcoded here, not
--- user input — the server modules parameterise for real callers, and this file
--- only ever builds statements from constants it defined itself.
local function q(value)
  return "'" .. tostring(value) .. "'"
end

local function resetFixtures()
  -- TRUNCATE, not DELETE: the ledger has a BEFORE DELETE trigger that refuses
  -- every row, on purpose. A test that tried to clean up with DELETE would fail
  -- for the right reason and the wrong message — the trigger is working.
  sql('TRUNCATE TABLE ledger')

  sql(('DELETE FROM stuetze_payouts WHERE character_id = %s'):format(q(TEST_CHARACTER)))
  sql(('DELETE FROM character_jobs WHERE character_id = %s'):format(q(TEST_CHARACTER)))
  sql(('DELETE FROM property_owners WHERE character_id = %s'):format(q(TEST_CHARACTER)))
  sql(('DELETE FROM inventory_items WHERE character_id = %s'):format(q(TEST_CHARACTER)))
  sql(('DELETE FROM wallets WHERE character_id IN (%s, %s)'):format(q(TEST_CHARACTER), q(OTHER_CHARACTER)))
  sql(('DELETE FROM characters WHERE id IN (%s, %s)'):format(q(TEST_CHARACTER), q(OTHER_CHARACTER)))
  sql(('DELETE FROM accounts WHERE id IN (%s, %s)'):format(q(TEST_ACCOUNT), q(OTHER_ACCOUNT)))
  sql(('DELETE FROM properties WHERE id = %s'):format(q(TEST_PROPERTY)))

  sql(('INSERT INTO accounts (id, discord_id, status) VALUES (%s, %s, %s)'):format(
    q(TEST_ACCOUNT), q('999000001'), q('active')))
  sql(('INSERT INTO characters (id, account_id, first_name, appearance) VALUES (%s, %s, %s, %s)'):format(
    q(TEST_CHARACTER), q(TEST_ACCOUNT), q('Headless'), q('{}')))
  -- The second character is created properly, on its own account, WITH a phone
  -- account. Before this it was only a wallet row, so every test that expected a
  -- refusal from it was really testing a missing foreign key and passing for the
  -- wrong reason.
  sql(('INSERT INTO accounts (id, discord_id, status) VALUES (%s, %s, %s)'):format(
    q(OTHER_ACCOUNT), q('999000002'), q('active')))
  sql(('INSERT INTO characters (id, account_id, first_name, appearance) VALUES (%s, %s, %s, %s)'):format(
    q(OTHER_CHARACTER), q(OTHER_ACCOUNT), q('Second'), q('{}')))
  sql(('INSERT INTO phone_accounts (character_id, number, is_active) VALUES (%s, %s, 1)'):format(
    q(TEST_CHARACTER), q('555-0001')))
  sql(('INSERT INTO phone_accounts (character_id, number, is_active) VALUES (%s, %s, 1)'):format(
    q(OTHER_CHARACTER), q('555-9999')))
  sql(('INSERT INTO wallets (character_id, cash, bank) VALUES (%s, 500.00, 200.00)'):format(q(TEST_CHARACTER)))
  sql(('INSERT INTO wallets (character_id, cash, bank) VALUES (%s, 500.00, 200.00)'):format(q(OTHER_CHARACTER)))
  sql(('INSERT INTO properties (id, code, name, district, kind, tier) VALUES (%s, %s, %s, %s, %s, %s)'):format(
    q(TEST_PROPERTY), q('headless_flat'), q('Headless Flat'), q('Testburg'), q('housing'), q('entry')))
end

local function balance(account)
  local row = Db.one('SELECT cash, bank FROM wallets WHERE character_id = ?', { TEST_CHARACTER }, 'test')
  return toNumber(row and row[account])
end

local function ledgerCount(reason)
  local row = Db.one('SELECT COUNT(*) AS c FROM ledger WHERE character_id = ? AND reason = ?',
    { TEST_CHARACTER, reason }, 'test')
  return toNumber(row and row.c)
end

local function itemCount(code)
  return Inventory.count(TEST_CHARACTER, code)
end

group('Money rounding — half-up, and nothing else')

-- Regression: the first implementation nudged the value by half a unit before
-- flooring, which shifted EVERY amount by exactly 0.50. A 12.00 bread cost
-- 12.50 and a 250.00 Stütze paid 250.50. Nothing else caught it, because every
-- other check compared a balance against another balance — both inflated.
check('a whole amount is unchanged', Economy.round(250) == 250.00)
check('an exact cent amount is unchanged', Economy.round(12.25) == 12.25)
check('rounds down below half', Economy.round(0.124) == 0.12, 'got ' .. tostring(Economy.round(0.124)))
check('rounds up above half', Economy.round(0.126) == 0.13, 'got ' .. tostring(Economy.round(0.126)))
check('negative amounts round symmetrically', Economy.round(-0.126) == -0.13,
  'got ' .. tostring(Economy.round(-0.126)))
check('zero stays zero', Economy.round(0) == 0, 'got ' .. tostring(Economy.round(0)))

-- ============================================================================
group('Persistence — a row, never a row array')

resetFixtures()

-- Regression with teeth. Drivers return a ROW ARRAY for a SELECT. An empty
-- array is still truthy in Lua, so `row ~= nil` treated "no such account" as
-- "account found" — and that check is the whitelist gate in sv_main.lua.
check('an empty result becomes nil, not an empty table',
  Db.one('SELECT id FROM accounts WHERE discord_id = ?', { '000000000' }, 'test') == nil)

check('a missing row becomes nil',
  Db.one('SELECT character_id FROM wallets WHERE character_id = ?', { 'nobody' }, 'test') == nil)

local found = Db.one('SELECT id FROM accounts WHERE discord_id = ?', { '999000001' }, 'test')
check('a real row is returned as a row, not an array',
  type(found) == 'table' and found.id == TEST_ACCOUNT,
  'got ' .. tostring(found and found.id))

local many = Db.all('SELECT id FROM accounts')
check('Db.all still returns every row', type(many) == 'table' and #many >= 1)

-- Dump helper: when a row-shaped assertion fails, seeing the actual table is
-- worth more than a message saying "it was wrong".
local function dump(value)
  local parts = {}
  for key, item in pairs(value or {}) do
    parts[#parts + 1] = tostring(key) .. '=' .. tostring(item)
  end
  return table.concat(parts, ', ')
end

-- Two-column row, the shape `findTargetSlot` depends on. If the column order or
-- the null handling is off by one, `tonumber(row.slot)` returns nil and the
-- caller dies on `used[nil] = true` — which is exactly what happened once.
resetFixtures()
Inventory.add(TEST_CHARACTER, 'bread', 3)

local slotRows = Db.all('SELECT slot, quantity FROM inventory_items WHERE character_id = ?',
  { TEST_CHARACTER }, 'test')
check('a two-column row survives parsing',
  type(slotRows) == 'table' and #slotRows == 1 and slotRows[1] ~= nil,
  '#rows=' .. tostring(#slotRows))
check('the slot column is a usable number',
  tonumber(slotRows[1] and slotRows[1].slot) ~= nil,
  'first row = {' .. dump(slotRows[1]) .. '}')
check('the quantity column is a usable number',
  tonumber(slotRows[1] and slotRows[1].quantity) ~= nil,
  'first row = {' .. dump(slotRows[1]) .. '}')

-- ============================================================================
-- Economy
-- ============================================================================

group('Economy — one guarded statement, always explained')

-- Fixtures FIRST. Without a wallet row the guarded UPDATE legitimately matches
-- zero rows and reports "insufficient funds" — the module is right and the test
-- is wrong, which is the exact shape of mistake worth not repeating twice.
resetFixtures()

local ok, err = Economy.apply(TEST_CHARACTER, 'cash', 100, 'job_wage')
check('a credit succeeds', ok, err)
check('cash actually moved', balance('cash') == 600, 'got ' .. tostring(balance('cash')))
check('a ledger row was written', ledgerCount('job_wage') == 1)

local ledgerRow = Db.one([[
  SELECT balance_after FROM ledger WHERE character_id = ? AND reason = 'job_wage' ORDER BY id DESC LIMIT 1
]], { TEST_CHARACTER }, 'test')
check('the ledger recorded the balance the INSERT itself read',
  toNumber(ledgerRow and ledgerRow.balance_after) == 600,
  'got ' .. tostring(ledgerRow and ledgerRow.balance_after))

local before = balance('cash')
local beforeLedger = ledgerCount('sale')
ok, err = Economy.apply(TEST_CHARACTER, 'cash', -99999, 'sale')
check('an unaffordable debit is refused', ok == false and err == 'insufficient funds', tostring(err))
check('the refused debit left the balance untouched', balance('cash') == before)
check('a refused debit writes no ledger row', ledgerCount('sale') == beforeLedger)

ok, err = Economy.apply(TEST_CHARACTER, 'cash', 50, 'not_a_real_reason')
check('an unknown reason is refused', ok == false and err == 'bad reason', tostring(err))

ok, err = Economy.apply(TEST_CHARACTER, 'cash', 0 / 0, 'sale')
check('NaN is refused', ok == false and err == 'bad amount', tostring(err))

ok, err = Economy.apply(TEST_CHARACTER, 'cash', 1e300, 'sale')
check('an absurd amount is refused', ok == false and err == 'bad amount', tostring(err))

ok, err = Economy.apply(TEST_CHARACTER, 'crypto', 10, 'sale')
check('an unknown account is refused', ok == false and err == 'bad account', tostring(err))

local beforeZero = ledgerCount('sale')
Economy.apply(TEST_CHARACTER, 'cash', 0, 'sale')
check('a zero delta writes no ledger row', ledgerCount('sale') == beforeZero)

-- Regression: `transfer` calls apply() with NO reference, so refType/refId were
-- nil. A nil inside the parameter table ends the table, the ledger INSERT got
-- fewer values than placeholders, and deposit/withdraw could never record a
-- movement. Every balance assertion above passed only because it was not
-- checking the ledger.
local cashBeforeTransfer = balance('cash')
local bankBeforeTransfer = balance('bank')
ok, err = Economy.transfer(TEST_CHARACTER, 'cash', 'bank', 100)
check('a transfer between own accounts succeeds', ok, tostring(err))
check('cash left the cash account', balance('cash') == cashBeforeTransfer - 100,
  'got ' .. tostring(balance('cash')))
check('the money arrived in the bank', balance('bank') == bankBeforeTransfer + 100,
  'got ' .. tostring(balance('bank')))
-- Two rows, not one: a transfer is a debit and a credit, and both belong in the
-- ledger. A single row would mean half the movement was unexplained.
check('both legs of a transfer are in the ledger', ledgerCount('bank_deposit') == 2,
  'got ' .. tostring(ledgerCount('bank_deposit')))

ok, err = Economy.transfer(TEST_CHARACTER, 'cash', 'bank', 999999)
check('an unaffordable transfer is refused', ok == false, tostring(err))
check('a refused transfer moves nothing',
  balance('cash') == cashBeforeTransfer - 100 and balance('bank') == bankBeforeTransfer + 100)

ok, err = Economy.transfer(TEST_CHARACTER, 'cash', 'cash', 10)
check('transferring to the same account is refused', ok == false, tostring(err))

-- ============================================================================
-- Shop — the refund path
--
-- This is the case that could not be proven by schema tests: charge first,
-- deliver second, refund on failure. To trigger delivery failure the weight
-- limit is lowered to below the weight of the item being bought, so the
-- inventory refuses it after the money has already moved.
-- ============================================================================

group('Shop — charge first, deliver second, refund on failure')

resetFixtures()

Inventory.add(TEST_CHARACTER, 'bread', 2)
check('bread was stocked', itemCount('bread') == 2)

local cashBeforeBuy = balance('cash')
ok, err = Shop.buy(TEST_CHARACTER, 'bread', 1)
check('a purchase succeeds', ok, tostring(err))
check('cash dropped by the price', balance('cash') == cashBeforeBuy - 12.00,
  'got ' .. tostring(balance('cash')))
check('the item arrived', itemCount('bread') == 3)

local cashBeforeRefund = balance('cash')
local ledgerBefore = ledgerCount('purchase')

-- Now make delivery impossible: max carry weight drops below one bread.
--
-- GetSetting reads a cache populated at resource start, so editing the row is
-- not enough — the settings have to be reloaded, exactly as a resource restart
-- would. That caching is deliberate (one read instead of one per lookup) and it
-- is also why a settings change needs a restart to take effect.
sql("UPDATE settings SET value = '0.050' WHERE `key` = 'inventory.max_weight'")
LoadSettings()
check('the new weight limit is in effect after a reload',
  Db.money.toNumber(Nifty.Settings['inventory.max_weight']) == 0.05,
  'got ' .. tostring(Nifty.Settings['inventory.max_weight']))

ok, err = Shop.buy(TEST_CHARACTER, 'bread', 1)
check('a purchase that cannot be delivered is refused', ok == false, tostring(err))
check('the customer was refunded in full',
  balance('cash') == cashBeforeRefund,
  'expected ' .. tostring(cashBeforeRefund) .. ', got ' .. tostring(balance('cash')))
check('no bread was delivered', itemCount('bread') == 3)
check('both the charge and the refund are in the ledger',
  ledgerCount('purchase') == ledgerBefore + 2,
  'expected ' .. tostring(ledgerBefore + 2) .. ', got ' .. tostring(ledgerCount('purchase')))

-- Restore the limit AND reload it. Forgetting the reload leaves the cache at
-- 0.050 for the rest of the run, and every later group then fails "too heavy"
-- for reasons that have nothing to do with what it is testing.
sql("UPDATE settings SET value = '50.000' WHERE `key` = 'inventory.max_weight'")
LoadSettings()
check('the weight limit is restored for later groups',
  Db.money.toNumber(Nifty.Settings['inventory.max_weight']) == 50.00,
  'got ' .. tostring(Nifty.Settings['inventory.max_weight']))

local cashBeforeSell = balance('cash')
ok, err = Shop.sell(TEST_CHARACTER, 'bread', 2)
check('a sale succeeds', ok, tostring(err))
check('the goods left before the money arrived', itemCount('bread') == 1)
check('the seller was paid half price',
  balance('cash') == cashBeforeSell + 12.00,
  'expected ' .. tostring(cashBeforeSell + 12) .. ', got ' .. tostring(balance('cash')))

ok, err = Shop.sell(TEST_CHARACTER, 'phone', 1)
check('selling something not carried is refused', ok == false, tostring(err))

ok, err = Shop.buy(TEST_CHARACTER, 'phone', 99)
check('an unbounded quantity is refused', ok == false, tostring(err))

-- ============================================================================
-- Inventory
-- ============================================================================

group('Inventory - stacking, capacity, swapping')

resetFixtures()

local okA, errA = Inventory.add(TEST_CHARACTER, 'bread', 10)
check('a full stack of bread is accepted', okA, tostring(errA))

local okB, errB = Inventory.add(TEST_CHARACTER, 'bread', 5)
check('a second stack is accepted', okB, tostring(errB))

check('stacks merge up to max_stack', itemCount('bread') == 15)

local rows = Db.all('SELECT slot, quantity FROM inventory_items WHERE character_id = ? AND item_code = ?',
  { TEST_CHARACTER, 'bread' }, 'test')
check('the merge used exactly two slots', #rows == 2, 'got ' .. tostring(#rows) .. ' slots')

Inventory.add(TEST_CHARACTER, 'screwdriver', 2)
check('a stack that would exceed max_stack is refused', itemCount('screwdriver') == 0,
  'got ' .. tostring(itemCount('screwdriver')))

Inventory.add(TEST_CHARACTER, 'screwdriver', 1)
check('a single non-mergeable item is accepted', itemCount('screwdriver') == 1)

Inventory.add(TEST_CHARACTER, 'no_such_item', 1)
check('an item with no catalogue entry is refused', itemCount('no_such_item') == 0)

Inventory.move(TEST_CHARACTER, 0, 1)
local moved = Db.all('SELECT slot FROM inventory_items WHERE character_id = ? ORDER BY slot',
  { TEST_CHARACTER }, 'test')
local capacity = Inventory.view(TEST_CHARACTER).totalSlots
local allLive = #moved > 0
for _, row in ipairs(moved) do
  if (tonumber(row.slot) or 65535) >= capacity then allLive = false end
end
check('a move leaves nothing parked outside capacity', allLive and #moved == 3,
  'rows=' .. tostring(#moved))

Inventory.move(TEST_CHARACTER, 99, 0)
check('moving to an out-of-range slot is refused', itemCount('bread') == 15)

Inventory.use(TEST_CHARACTER, 'bread', 1)
check('using an item consumes exactly one', itemCount('bread') == 14)

Inventory.remove(TEST_CHARACTER, 'bread', 999)
check('removing more than is carried is refused', itemCount('bread') == 14)

-- ============================================================================group('Jobs — open to anyone, paid by elapsed time')

resetFixtures()

ok, err = Jobs.join(TEST_CHARACTER, 'taxi')
check('anyone may sign up', ok, tostring(err))
ok, err = Jobs.join(TEST_CHARACTER, 'taxi')
check('signing up twice is refused', ok == false, tostring(err))
ok, err = Jobs.join(TEST_CHARACTER, 'astronaut')
check('a job that does not exist is refused', ok == false, tostring(err))

check('the job list reports the signing', #Jobs.listFor(TEST_CHARACTER) == 1)

local cashBeforeDuty = balance('cash')
ok, err = Jobs.startDuty(TEST_CHARACTER, 'taxi')
check('a shift starts', ok, tostring(err))
check('the payslip was charged', balance('cash') == cashBeforeDuty - 25.00,
  'got ' .. tostring(balance('cash')))

ok, err = Jobs.startDuty(TEST_CHARACTER, 'police')
check('a second simultaneous shift is refused', ok == false, tostring(err))

ok, err = Jobs.startDuty(TEST_CHARACTER, 'taxi')
check('starting the same shift twice is refused', ok == false, tostring(err))

-- End it immediately: under job.duty.min_seconds, so the payout must be zero.
local cashBeforeEnd = balance('cash')
local started, elapsed, payout = Jobs.endDuty(TEST_CHARACTER, 'taxi')
check('the shift ends', started, tostring(elapsed))
check('a shift under the minimum pays nothing', payout == 0, 'got ' .. tostring(payout))
check('an unpaid shift still costs the payslip',
  balance('cash') == cashBeforeEnd,
  'got ' .. tostring(balance('cash')))

-- Force the "worked long enough" case by ageing the duty timestamp, since
-- waiting five real minutes is not something a test should do.
sql(('UPDATE character_jobs SET is_duty = 1, duty_since = DATE_SUB(NOW(), INTERVAL 2 HOUR) ' ..
  'WHERE character_id = %s AND job_code = %s'):format(q(TEST_CHARACTER), q('taxi')))

local cashBeforePay = balance('cash')
started, elapsed, payout = Jobs.endDuty(TEST_CHARACTER, 'taxi')
check('a two-hour shift reports its elapsed time',
  started and elapsed and elapsed >= 7100 and elapsed <= 7300,
  'got ' .. tostring(elapsed))
check('a two-hour shift is paid pro-rata',
  started and payout and payout > 0 and payout < 200,
  'got ' .. tostring(payout))
check('the wage actually reached the wallet',
  balance('cash') > cashBeforePay,
  'got ' .. tostring(balance('cash')))

-- ============================================================================
-- Ownership
-- ============================================================================

group('Appearance — the server rebuilds, never stores what it was given')

-- ADR-0017. The collection natives are client-only, so the server cannot ask the
-- engine whether a combination is real. This allowlist is the gate, which makes
-- it the most client-facing validation in the project — and previously the least
-- tested, because every existing check stopped at the database.

local function slot(collection, drawable, texture)
  return { collection = collection, drawable = drawable, texture = texture }
end

local okApp, errApp = Validate.appearance({
  model = 'mp_m_freemode_01',
  components = { ['0'] = slot('', 27, 0), ['4'] = slot('female_heist', 9, 3) },
  props = { ['0'] = slot('mp_f_bikerdlc_01', 0, 0) },
})
check('a well-formed appearance is accepted', okApp ~= nil, tostring(errApp))
check('the model survives', okApp ~= nil and okApp.model == 'mp_m_freemode_01')
local function describeApp(value)
  if type(value) ~= 'table' then return tostring(value) end
  local parts = {}
  for id, s in pairs(value.components or {}) do
    parts[#parts + 1] = ('c%s=%s/%s/%s'):format(id, tostring(s.collection), tostring(s.drawable), tostring(s.texture))
  end
  for id, s in pairs(value.props or {}) do
    parts[#parts + 1] = ('p%s=%s/%s/%s'):format(id, tostring(s.collection), tostring(s.drawable), tostring(s.texture))
  end
  return #parts > 0 and table.concat(parts, ' ') or '(components and props both empty)'
end

check('both components survive',
  okApp ~= nil and okApp.components['0'] ~= nil and okApp.components['4'] ~= nil,
  describeApp(okApp))
check('props survive', okApp ~= nil and okApp.props['0'] ~= nil, describeApp(okApp))

-- The rejection cases, which is the entire point of the allowlist.
local rejections = {
  { 'unknown collection', { model = 'mp_m_freemode_01', components = { ['0'] = slot('mp_m_secret_relic', 1, 0) } } },
  { 'drawable out of range', { model = 'mp_m_freemode_01', components = { ['0'] = slot('', 9999, 0) } } },
  { 'negative drawable', { model = 'mp_m_freemode_01', components = { ['0'] = slot('', -1, 0) } } },
  { 'fractional drawable', { model = 'mp_m_freemode_01', components = { ['0'] = slot('', 1.5, 0) } } },
  { 'texture out of range', { model = 'mp_m_freemode_01', components = { ['0'] = slot('', 0, 9999) } } },
  { 'unsupported ped model', { model = 's_m_y_man', components = {} } },
  { 'slot is not an object', { model = 'mp_m_freemode_01', components = { ['0'] = 'not-a-table' } } },
  { 'missing collection', { model = 'mp_m_freemode_01', components = { ['0'] = { drawable = 0, texture = 0 } } } },
}

for _, case in ipairs(rejections) do
  local result = Validate.appearance(case[2])
  check('rejected: ' .. case[1], result == nil, 'accepted instead of refused')
end

-- An out-of-range component id is DROPPED rather than refused. That is the
-- deliberate reading of ADR-0017: the server rebuilds the structure from what it
-- recognises, so anything it does not recognise simply does not exist. The
-- important property is that it cannot be stored, not that it is an error.
local dropped = Validate.appearance({
  model = 'mp_m_freemode_01',
  components = { ['99'] = slot('', 0, 0), ['0'] = slot('', 5, 1) },
})
check('an out-of-range component id is dropped, not stored',
  dropped ~= nil and dropped.components['99'] == nil and dropped.components['0'] ~= nil,
  'stored ' .. describeApp(dropped))

check('appearance must be an object', Validate.appearance('nonsense') == nil)
check('a missing appearance falls back to defaults',
  Validate.appearance(nil) ~= nil and Validate.appearance(nil).model == 'mp_m_freemode_01')

-- Extra keys a client sends must not survive. If they did, a client could store
-- arbitrary JSON in the character row and read it back later.
local rebuilt = Validate.appearance({
  model = 'mp_m_freemode_01',
  components = { ['0'] = slot('', 5, 1) },
  props = {},
  evil_key = 'should not persist',
})
check('unknown top-level keys are dropped', rebuilt ~= nil and rebuilt.evil_key == nil,
  'got ' .. tostring(rebuilt and rebuilt.evil_key))

-- Round-trip through JSON, which is how it actually reaches the server: a client
-- sends a string, the server decodes it. A lenient decoder would be a bypass.
local hostile = json.decode([[{
  "model": "mp_m_freemode_01",
  "components": {"0": {"collection": "mp_m_secret_relic", "drawable": 0, "texture": 0}},
  "props": {}
}]])
check('a hostile collection smuggled through JSON is still rejected',
  Validate.appearance(hostile) == nil)

local benign = json.decode([[{
  "model": "mp_m_freemode_01",
  "components": {"4": {"collection": "female_heist", "drawable": 9, "texture": 3}},
  "props": {"0": {"collection": "", "drawable": 1, "texture": 0}}
}]])
check('a legitimate appearance survives the JSON round trip',
  Validate.appearance(benign) ~= nil)

-- Identity-level validation, which sits in front of the same data.
check('a normal name is accepted', Validate.characterName('Ada') == 'Ada',
  'got ' .. tostring(Validate.characterName('Ada')))
check('a script-injection attempt in a name is refused', Validate.characterName('<script>x') == nil)
check('a one-character name is refused', Validate.characterName('A') == nil)
check('gender is a closed set', Validate.gender('other') == nil)
check('an unknown spawn point is refused', Validate.spawnPoint('atlantis') == nil)
check('a default spawn point is allowed', Validate.spawnPoint(nil) == 'default')
check('someone under 18 is refused', Validate.dateOfBirth('2015-01-01') == nil)
check('an adult date is accepted', Validate.dateOfBirth('1990-06-15') == '1990-06-15')

-- ============================================================================
group('Stütze — unconditional, recorded, capped')

resetFixtures()

local cashBeforeStuetze = balance('cash')
check('the Stütze pays with no job and no check', Stuetze.pay(1, TEST_CHARACTER) == true)
check('it credits cash', balance('cash') > cashBeforeStuetze,
  'got ' .. tostring(balance('cash')))
check('it writes a ledger row', ledgerCount('stuetze') == 1)

local payoutRow = Db.one('SELECT COUNT(*) AS c FROM stuetze_payouts WHERE character_id = ?',
  { TEST_CHARACTER }, 'test')
check('it also writes the abuse-detection row',
  toNumber(payoutRow and payoutRow.c) == 1,
  'got ' .. tostring(payoutRow and payoutRow.c))

local cap = tonumber(GetSetting('economy.stuetze.max_per_session', 8)) or 8
for _ = 1, cap + 5 do Stuetze.pay(1, TEST_CHARACTER) end
-- The cap counts EVERY instalment, including the first one above, so the ceiling
-- is `cap` in total — not `cap` more on top of it.
check('the session cap stops further payouts',
  ledgerCount('stuetze') == cap,
  'got ' .. tostring(ledgerCount('stuetze')) .. ' instalments for a cap of ' .. tostring(cap))

check('the cap is the only brake — amount is unconditional',
  toNumber(GetSetting('economy.stuetze.amount', 0)) > 0)

-- ============================================================================
group('Character creation — one transaction, or nothing at all')
-- ============================================================================

-- ADR-0008 and ADR-0018 meet here: the character, its wallet and its starting
-- items are created together. This is the path a brand-new player walks, and it
-- had never been executed.

sql('TRUNCATE TABLE ledger')
sql('DELETE FROM stuetze_payouts')
sql('DELETE FROM character_jobs')
sql('DELETE FROM property_owners')
sql('DELETE FROM inventory_items')
sql('DELETE FROM wallets')
sql('DELETE FROM sessions')
sql('DELETE FROM characters')
sql('DELETE FROM accounts')
sql('DELETE FROM properties')

FakePlayers.connect(1, '777000001')

-- ADR-0007: an account only exists once a human has approved it. The harness is
-- standing in for that human, so it inserts the approved row the website could
-- never have written itself.
sql([[
  INSERT INTO accounts (id, discord_id, status) VALUES ('acct-live', '777000001', 'active')
]])

-- An unapproved account must NOT resolve — this is the whitelist boundary.
sql([[
  INSERT INTO accounts (id, discord_id, status) VALUES ('acct-pending', '777000002', 'pending')
]])
FakePlayers.connect(3, '777000002')

local account = Identity.resolveAccount(1)
check('a whitelisted Discord ID resolves to an account', account ~= nil)
check('a pending application does NOT resolve to a playable account',
  Identity.resolveAccount(3) == nil, 'a pending account must stay inert')
check('an unknown Discord ID resolves to nothing', Identity.resolveAccount(99) == nil)
FakePlayers.disconnect(3)

-- The exact payload a player with no second name and no date of birth sends.
-- Both fields are optional, and both arrive as nil — the case that broke the
-- parameter list and made creation impossible for most people.
local created, createErr = Identity.createCharacter(1, {
  firstName = 'Ada',
  lastName = '',
  dateOfBirth = '',
  gender = 'female',
  appearance = {
    model = 'mp_f_freemode_01',
    components = { ['0'] = { collection = '', drawable = 12, texture = 0 },
                   ['4'] = { collection = 'female_heist', drawable = 9, texture = 3 } },
    props = { ['0'] = { collection = 'mp_f_bikerdlc_01', drawable = 0, texture = 0 } },
  },
  spawnPoint = 'losSantos',
})
check('a character is created with optional fields left empty', created ~= nil, tostring(createErr))

if created then
  check('the character has an id', type(created.id) == 'string' and #created.id > 0)
  check('the first name is stored', created.first_name == 'Ada')

  -- The whole point of the appearance fix last round: components must survive
  -- the round trip through the database, not just the validation call.
  local stored = Identity.getCharacter(account.id)
  local appearance = stored and stored.appearance and json.decode(stored.appearance) or nil
  check('the appearance was stored, not discarded',
    appearance ~= nil and appearance.model == 'mp_f_freemode_01',
    'stored ' .. tostring(stored and stored.appearance))
  check('components survived the database round trip',
    appearance ~= nil and appearance.components['0'] ~= nil and appearance.components['4'] ~= nil,
    'components = ' .. tostring(appearance and appearance.components and appearance.components['0']))
  check('props survived the database round trip',
    appearance ~= nil and appearance.props['0'] ~= nil)
  check('the optional columns are genuinely NULL',
    stored.last_name == nil and stored.date_of_birth == nil,
    'last_name=' .. tostring(stored.last_name) .. ' dob=' .. tostring(stored.date_of_birth))

  local newWallet = Db.one('SELECT cash, bank FROM wallets WHERE character_id = ?', { created.id }, 'test')
  check('the wallet was created in the same transaction', newWallet ~= nil)
  check('starting cash matches the setting',
    toNumber(newWallet and newWallet.cash) ==
      Db.money.toNumber(GetSetting('economy.starting.cash', 0)),
    'got ' .. tostring(newWallet and newWallet.cash))

  check('a new character carries a handset (ADR-0018)', Inventory.count(created.id, 'phone') == 1)
  check('a new character carries an ID card', Inventory.count(created.id, 'id_card') == 1)

  -- ADR-0021: the number is assigned at creation, inside the same transaction,
  -- and it is permanent. A character with no number could not be messaged.
  local accountRow = Phone.getAccount(created.id)
  check('a phone account was created with the character', accountRow ~= nil)
  check('the number matches the configured format',
    accountRow ~= nil and accountRow.number:match('^555%-%d%d%d%d$') ~= nil,
    'got ' .. tostring(accountRow and accountRow.number))
  check('the account is active', accountRow ~= nil and accountRow.active == true)

  PHONE_ONE = created.id
  PHONE_NUMBER_ONE = accountRow and accountRow.number

  -- A second attempt from the same account must be refused by ADR-0008.
  local again, againErr = Identity.createCharacter(1, {
    firstName = 'Grace', gender = 'female',
    appearance = { model = 'mp_f_freemode_01' },
  })
  check('a second character for the same account is refused',
    again == nil and againErr == 'this account already has a character',
    tostring(againErr))
end

-- Malformed payloads must be refused before anything is written.
local badName = Identity.createCharacter(2, { firstName = '<script>', gender = 'male',
  appearance = { model = 'mp_m_freemode_01' } })
check('a scripted name is refused', badName == nil)

local badAppearance = Identity.createCharacter(2, { firstName = 'Mallory', gender = 'male',
  appearance = { model = 'mp_m_freemode_01',
                 components = { ['0'] = { collection = 'mp_m_secret_relic', drawable = 0, texture = 0 } } } })
check('a hostile appearance is refused', badAppearance == nil)

local countAfter = Db.one('SELECT COUNT(*) AS c FROM characters', {}, 'test')
check('no partial character was left behind by the refusals',
  toNumber(countAfter and countAfter.c) == 1,
  'got ' .. tostring(countAfter and countAfter.c) .. ' characters')

-- Sessions: the only place a FiveM slot ID is allowed to appear (ADR-0001).
local sessionId = Identity.beginSession(1, created and created.id)
check('a session opens with an id', sessionId ~= nil)
check('the session records the slot id for auditing only',
  Db.one('SELECT fivem_slot_id FROM sessions WHERE id = ?', { sessionId }, 'test') ~= nil)
check('the active character is readable by slot', Identity.getActiveCharacter(1) == (created and created.id))
Identity.endSession(1)
check('the session closes', Identity.getActiveCharacter(1) == nil)

FakePlayers.disconnect(1)

-- ============================================================================
group('Phone — device, account, permanent number, permanent messages')
-- ============================================================================

-- ADR-0018 and ADR-0021 meet. The handset is an item; the account is the
-- character; the number is permanent and was assigned before anyone asked.
--
-- Self-contained: the character-creation group above truncates everything it
-- touches, so this group rebuilds its own two characters through the same
-- fixture path rather than relying on rows that no longer exist.

resetFixtures()

PHONE_ONE = TEST_CHARACTER
PHONE_NUMBER_ONE = Phone.getAccount(PHONE_ONE) and Phone.getAccount(PHONE_ONE).number

check('the fixture character has a phone account', Phone.getAccount(PHONE_ONE) ~= nil)
check('the second character has a DIFFERENT number',
  Phone.getAccount(OTHER_CHARACTER) ~= nil and
  Phone.getAccount(OTHER_CHARACTER).number ~= PHONE_NUMBER_ONE,
  'got ' .. tostring(Phone.getAccount(OTHER_CHARACTER) and Phone.getAccount(OTHER_CHARACTER).number))

check('the number was found by number lookup',
  Phone.findByNumber(PHONE_NUMBER_ONE) ~= nil and Phone.findByNumber(PHONE_NUMBER_ONE).id == PHONE_ONE)
check('an unknown number finds nobody', Phone.findByNumber('555-0000') == nil)
check('a nil number is refused rather than matching everything', Phone.findByNumber(nil) == nil)

local searchResults = Phone.search('Headless')
check('a character can be found by name', type(searchResults) == 'table' and #searchResults >= 1)
check('a one-character search is refused (matches everyone)', #Phone.search('a') == 0)

local otherNumber = Phone.newNumber()
check('a second number is different from the first', otherNumber ~= PHONE_NUMBER_ONE)

-- Messages.
local messageId, sendErr = Phone.send(PHONE_ONE, OTHER_CHARACTER, '  Hallo, bin neu hier.  ')
check('a message is sent', messageId ~= nil, tostring(sendErr))

local inbox = Phone.inbox(OTHER_CHARACTER, 25, 0)
check('it lands in the recipient inbox', #inbox == 1)
check('the body is trimmed', inbox[1] and inbox[1].body == 'Hallo, bin neu hier.',
  'got ' .. tostring(inbox[1] and inbox[1].body))
check('it starts unread', Phone.unreadCount(OTHER_CHARACTER) == 1)

check('the sender can see it in their outbox', #Phone.outbox(PHONE_ONE, 25, 0) == 1)
check('the recipient cannot see it in an outbox', #Phone.outbox(OTHER_CHARACTER, 25, 0) == 0)

Phone.markAllRead(OTHER_CHARACTER)
check('marking read clears the unread count', Phone.unreadCount(OTHER_CHARACTER) == 0)

local rejected
rejected = Phone.send(PHONE_ONE, PHONE_ONE, 'an internal monologue')
check('a character cannot message themselves', rejected == nil)
rejected = Phone.send(PHONE_ONE, OTHER_CHARACTER, '   ')
check('an empty message is refused', rejected == nil)
rejected = Phone.send(PHONE_ONE, 'chr-does-not-exist', 'into the void')
check('messaging a non-existent character is refused', rejected == nil)
rejected = Phone.send(PHONE_ONE, OTHER_CHARACTER, ('x'):rep(2000))
check('an over-long message is truncated, not refused',
  rejected ~= nil and #Phone.inbox(OTHER_CHARACTER, 25, 0)[1].body ==
    tonumber(GetSetting('phone.message.max_length', 1000)),
  'got ' .. tostring(#Phone.inbox(OTHER_CHARACTER, 25, 0)[1].body))

-- Deleting is private: your inbox, not theirs.
check('clearing a message works for its recipient', Phone.clear(OTHER_CHARACTER, messageId))
-- One message remains: the over-long one sent above. What matters is that the
-- cleared one is GONE and the other is untouched — not that the inbox emptied.
local afterClear = Phone.inbox(OTHER_CHARACTER, 25, 0)
check('the cleared message is gone from their inbox',
  #afterClear == 1 and afterClear[1].id ~= messageId,
  'inbox still holds ' .. tostring(#afterClear))
check('the other message is untouched',
  afterClear[1] ~= nil and #afterClear[1].body == tonumber(GetSetting('phone.message.max_length', 1000)))
check('the sender still has their copy', #Phone.outbox(PHONE_ONE, 25, 0) >= 1)
check('a character cannot clear a message that is not theirs',
  not Phone.clear(PHONE_ONE, messageId))

-- Reporting (ADR-0019): the target is derived from the message, never supplied.
check('a report can be filed', Phone.report(OTHER_CHARACTER, PHONE_ONE, messageId, 'spam') ~= nil)
check('a report with an unknown reason is refused', Phone.report(OTHER_CHARACTER, PHONE_ONE, messageId, 'because') == nil)
check('self-reporting is refused', Phone.report(PHONE_ONE, PHONE_ONE, messageId, 'spam') == nil)

local queue = Phone.openReports(10)
check('the report reaches the staff queue', #queue == 1)
check('the queue names the reported character', queue[1] and queue[1].reported_first ~= nil)
check('a report can be actioned', Phone.resolveReport(queue[1].id, 'actioned'))
check('the queue empties once resolved', #Phone.openReports(10) == 0)
check('a bad resolution status is refused', not Phone.resolveReport(queue[1].id, 'maybe'))

-- Numbers are permanent: nothing in the module may change one.
local before = Phone.getAccount(PHONE_ONE)
check('the number cannot be changed by any exported function',
  Phone.getAccount(PHONE_ONE).number == before.number and before.number == PHONE_NUMBER_ONE)

-- ============================================================================
group('Ownership — a row, not a field')

resetFixtures()

ok, err = Ownership.acquireProperty(TEST_CHARACTER, TEST_PROPERTY)
check('a property can be acquired', ok, tostring(err))
check('ownership is reported', Ownership.owns(TEST_CHARACTER, TEST_PROPERTY))

ok, err = Ownership.acquireProperty(OTHER_CHARACTER, TEST_PROPERTY)
check('a second owner is refused', ok == false, tostring(err))
check('the refused claim left the owner intact',
  Ownership.owns(TEST_CHARACTER, TEST_PROPERTY))

local released = Ownership.releaseProperty(TEST_CHARACTER, TEST_PROPERTY, nil)
check('a property can be released', released == 'unowned', tostring(released))
check('nobody owns it afterwards', not Ownership.owns(TEST_CHARACTER, TEST_PROPERTY))

ok, err = Ownership.acquireProperty(TEST_CHARACTER, 'no-such-property')
check('an unknown property is refused', ok == false, tostring(err))

-- ============================================================================
-- Result
-- ============================================================================

io.write('\n=== Result ===\n')

if failed == 0 then
  io.write(('  All %d checks passed.\n'):format(passed))
  os.exit(0)
end

io.write(('  %d of %d checks FAILED:\n'):format(failed, passed + failed))
for _, name in ipairs(failures) do
  io.write('    - ', name, '\n')
end
os.exit(1)