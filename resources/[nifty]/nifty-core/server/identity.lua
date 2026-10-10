--- Identity (ADR-0014 layer 3).
---
--- Owns the character lifecycle and the session record:
---   connect -> whitelist -> load-or-create character -> play -> save -> end session
---
--- The rule this file exists to enforce is ADR-0001: a FiveM slot ID is never a
--- key. It is recorded once in `sessions` and nowhere else, and the in-memory
--- map from slot to character is runtime state that dies with the connection.
--- Every save is keyed by character UUID, which is why reconnecting restores the
--- right person even if the engine hands the same slot number to someone else.

local RESOURCE = GetCurrentResourceName()

math.randomseed(os.time() + math.floor(os.clock() * 1000))

--- Runtime-only. Maps FiveM slot -> { characterId, sessionId }. Lost on
--- restart, which is fine: `sessions` is the durable record, this is a cache.
local ActiveSessions = {}

--- Per-player attempt counters, so a client cannot spam character creation.
local CreationAttempts = {}
local MAX_CREATE_ATTEMPTS = 5

local function uuid()
  return Nifty.newUuid()
end

Identity = {}

--- The Discord ID behind a connection, or nil.
---
--- Two APIs can answer this and only one is guaranteed to exist. `GetPlayerIdentifiers`
--- has been in the server runtime since forever and returns prefixed entries like
--- `discord:123456`. `GetPlayerIdentifiersByType` is a newer convenience wrapper that
--- is NOT present on every build — calling it unconditionally kills the resource on
--- the first connection, which is exactly what happened on this server. So the
--- guaranteed API is primary and the optional one is only used when it exists.
---
--- The returned value is normalised to a bare digit string, because the two APIs
--- disagree about the prefix and `accounts.discord_id` is stored bare.
local function discordIdOf(src)
  local ids = nil

  if type(GetPlayerIdentifiersByType) == 'function' then
    ids = GetPlayerIdentifiersByType(src, 'discord')
  end

  if not ids or #ids == 0 then
    for _, entry in ipairs(GetPlayerIdentifiers(src) or {}) do
      local kind, value = string.match(entry, '^(%w+):(.+)$')
      if kind == 'discord' then
        ids = { value }
        break
      end
    end
  end

  local raw = ids and ids[1]
  if type(raw) ~= 'string' then return nil end

  -- Defensive: strip a prefix if one survived, then refuse anything that is not
  -- a plain ID. An unparseable value must fail closed, never reach the whitelist.
  local id = string.match(raw, '^(%d+)$') or string.match(raw, '^discord:(%d+)$')
  if not id or id == '' then return nil end

  return id
end

--- Public because sv_main.lua's connection gate needs the same answer, and two
--- copies of this logic are two places for them to disagree.
Identity.discordIdOf = discordIdOf

--- Resolve the account behind a connection. Identity comes from the connection,
--- never from anything the client sends.
---
--- `status = 'active'` is filtered HERE as well as in the `playerConnecting`
--- whitelist check. The connecting check is the gate, but this function is also
--- reached from `nifty:server:ready`, and a gate that only exists in one of two
--- paths to the same privilege is not a gate. A pending or suspended account must
--- resolve to nothing here, so that being whitelisted once and suspended later
--- actually stops something.
function Identity.resolveAccount(src)
  local discordId = discordIdOf(src)
  if not discordId then return nil end

  return Db.one([[
    SELECT id, discord_id, teamspeak_uid, status
      FROM accounts
     WHERE discord_id = ?
       AND status = 'active'
     LIMIT 1
  ]], { discordId }, 'identity:account')
end

function Identity.getCharacter(accountId)
  return Db.one([[
    SELECT id, first_name, last_name, date_of_birth, gender, appearance, spawn_point
      FROM characters
     WHERE account_id = ?
     LIMIT 1
  ]], { accountId }, 'identity:character')
end

--- Create the character and its wallet together. A character without a wallet is
--- an unplayable state, so both rows go in one transaction or neither does.
function Identity.createCharacter(src, payload)
  local attempts = (CreationAttempts[src] or 0) + 1
  CreationAttempts[src] = attempts
  if attempts > MAX_CREATE_ATTEMPTS then
    return nil, 'too many attempts'
  end

  local account = Identity.resolveAccount(src)
  if not account then return nil, 'no account' end

  if Identity.getCharacter(account.id) then
    return nil, 'this account already has a character'
  end

  local firstName, err = Validate.characterName(payload and payload.firstName)
  if not firstName then return nil, err end

  local lastName
  if payload and payload.lastName and payload.lastName ~= '' then
    lastName, err = Validate.characterName(payload.lastName)
    if not lastName then return nil, err end
  end

  local dateOfBirth
  dateOfBirth, err = Validate.dateOfBirth(payload and payload.dateOfBirth)
  if not dateOfBirth and err then return nil, err end

  local gender
  gender, err = Validate.gender(payload and payload.gender)
  if not gender then return nil, err end

  local appearance
  appearance, err = Validate.appearance(payload and payload.appearance)
  if not appearance then return nil, err end

  local spawnPoint
  spawnPoint, err = Validate.spawnPoint(payload and payload.spawnPoint)
  if not spawnPoint then return nil, err end

  local characterId = uuid()
  local encoded = json.encode(appearance)

  -- ADR-0021: the number is assigned here, inside the same transaction as the
  -- character. A character with no number could not be messaged, and the number
  -- is permanent, so it cannot be added later as a convenience — it has to exist
  -- from the first second of the character's life.
  local number = Phone.newNumber()
  if not number then return nil, 'no free phone number' end

  -- ADR-0008 is enforced by UNIQUE, not by this check. If two requests race,
  -- the second insert fails here and is reported honestly.
  --
  -- `last_name` and `date_of_birth` are both OPTIONAL — most characters will have
  -- no second name, and the date of birth is only refused when it is malformed,
  -- not when it is absent. So both arrive here as nil, and a nil in the middle
  -- of a Lua table ends the table: `#{a, b, nil, nil, c, d}` has an undefined
  -- length, the driver receives fewer values than there are placeholders, and
  -- the whole INSERT fails to bind. Character creation was broken for exactly
  -- the players who left a field empty.
  --
  -- NULLIF(?, '') keeps the parameter list hole-free while the columns stay
  -- genuinely NULL, which is what "optional" has to mean in the schema.
  local ok = Db.transaction({
    {
      sql = [[INSERT INTO characters
                (id, account_id, first_name, last_name, date_of_birth, gender, appearance, spawn_point)
              VALUES (?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?)]],
      params = { characterId, account.id, firstName, lastName or '', dateOfBirth or '',
                 gender, encoded, spawnPoint },
    },
    {
      sql = [[INSERT INTO wallets (character_id, cash, bank)
              VALUES (?, ?, ?)]],
      params = { characterId,
                 tostring(GetSetting('economy.starting.cash', 0)),
                 tostring(GetSetting('economy.starting.bank', 0)) },
    },
    {
      sql = [[UPDATE accounts SET status = 'active' WHERE id = ?]],
      params = { account.id },
    },
    {
      sql = [[INSERT INTO phone_accounts (character_id, number, is_active)
              VALUES (?, ?, 1)]],
      params = { characterId, number },
    },
  }, 'identity:createCharacter')

  if not ok then return nil, 'could not create character' end

  -- ADR-0018: every character starts with a handset and an ID. The handset is
  -- inert until activated, which is the moment a player buys a number.
  Inventory.grantStartingItems(characterId)

  print(('[%s] created character %s for account %s'):format(RESOURCE, characterId, account.id))

  return Identity.getCharacter(account.id)
end

--- Open a session. The slot ID goes in for auditing only.
function Identity.beginSession(src, characterId)
  local sessionId = Db.insert([[
    INSERT INTO sessions (character_id, fivem_slot_id, fivem_license)
    VALUES (?, ?, ?)
  ]], { characterId, src, GetPlayerLicense(src) }, 'identity:beginSession')

  ActiveSessions[src] = { characterId = characterId, sessionId = sessionId }
  return sessionId
end

function Identity.getActiveCharacter(src)
  local entry = ActiveSessions[src]
  return entry and entry.characterId or nil
end

--- The DB session id for this connection, or nil. Used by the Stütze to link a
--- payout to the session it was paid in — ADR-0009 needs that link to tell
--- "someone stayed online too long" apart from "someone was paid too much".
function Identity.getActiveSessionId(src)
  local entry = ActiveSessions[src]
  return entry and entry.sessionId or nil
end

--- Persist a character's mutable state. Always keyed by character UUID.
function Identity.saveCharacter(src, patch)
  local characterId = Identity.getActiveCharacter(src)
  if not characterId then return false end

  local sets, params = {}, {}

  if patch.appearance ~= nil then
    local appearance, err = Validate.appearance(patch.appearance)
    if not appearance then
      print(('[%s] refused to save appearance for %s: %s'):format(RESOURCE, characterId, err))
      return false
    end
    sets[#sets + 1] = 'appearance = ?'
    params[#params + 1] = json.encode(appearance)
  end

  if patch.spawnPoint ~= nil then
    local spawnPoint, err = Validate.spawnPoint(patch.spawnPoint)
    if not spawnPoint then return false end
    sets[#sets + 1] = 'spawn_point = ?'
    params[#params + 1] = spawnPoint
  end

  if #sets == 0 then return false end

  params[#params + 1] = characterId
  Db.update(('UPDATE characters SET %s WHERE id = ?'):format(table.concat(sets, ', ')),
            params, 'identity:saveCharacter')

  return true
end

function Identity.endSession(src)
  local entry = ActiveSessions[src]
  if not entry then return end

  if entry.sessionId then
    Db.update('UPDATE sessions SET disconnected_at = NOW() WHERE id = ?',
              { entry.sessionId }, 'identity:endSession')
  end

  ActiveSessions[src] = nil
  CreationAttempts[src] = nil
end

exports('getActiveCharacter', Identity.getActiveCharacter)
exports('createCharacter', Identity.createCharacter)
exports('saveCharacter', Identity.saveCharacter)
exports('endSession', Identity.endSession)