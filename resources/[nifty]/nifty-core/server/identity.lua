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
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return (string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end))
end

Identity = {}

local function discordIdOf(src)
  local ids = GetPlayerIdentifiersByType(src, 'discord') or {}
  return ids[1]
end

--- Resolve the account behind a connection. Identity comes from the connection,
--- never from anything the client sends.
function Identity.resolveAccount(src)
  local discordId = discordIdOf(src)
  if not discordId then return nil end

  return Db.one([[
    SELECT id, discord_id, teamspeak_uid, status
      FROM accounts
     WHERE discord_id = ?
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

  -- ADR-0008 is enforced by UNIQUE, not by this check. If two requests race,
  -- the second insert fails here and is reported honestly.
  local ok = Db.transaction({
    {
      sql = [[INSERT INTO characters
                (id, account_id, first_name, last_name, date_of_birth, gender, appearance, spawn_point)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
      params = { characterId, account.id, firstName, lastName, dateOfBirth, gender, encoded, spawnPoint },
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
  }, 'identity:createCharacter')

  if not ok then return nil, 'could not create character' end

  Db.update([[UPDATE accounts SET status = 'active' WHERE id = ?]], { account.id }, 'identity:activate')

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