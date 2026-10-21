-- Identity (ADR-0014 layer 3).
--
-- Owns the character record and the session lifecycle:
--   connect -> whitelist -> load character -> play -> save -> end session
--
-- Character creation itself lives on the website and is performed by the
-- create_character_from_web stored procedure (ADR-0021). The base never
-- inserts a character, so there is no "or-create" half here.
--
-- The rule this file exists to enforce is ADR-0001: a FiveM slot ID is never a
-- key. It is recorded once in `sessions` and nowhere else, and the in-memory
-- map from slot to character is runtime state that dies with the connection.
-- Every save is keyed by character UUID, which is why reconnecting restores the
-- right person even if the engine hands the same slot number to someone else.

local RESOURCE = GetCurrentResourceName()

-- Lua 5.4 auto-seeds `math.random` with a high-quality seed. The previous
-- `math.randomseed(os.time() + math.floor(math.clock() * 1000))` was a
-- carryover from earlier FiveM versions; both `os.clock` and `math.clock`
-- are removed from the server-side sandbox now (timing-attack protection),
-- and seeding is no longer needed.

-- Runtime-only. Maps FiveM slot -> { characterId, sessionId }. Lost on
-- restart, which is fine: `sessions` is the durable record, this is a cache.
local ActiveSessions = {}

Identity = {}

-- The Discord ID behind a connection, or nil.
--
-- Two APIs can answer this and only one is guaranteed to exist. `GetPlayerIdentifiers`
-- has been in the server runtime since forever and returns prefixed entries like
-- `discord:123456`. `GetPlayerIdentifiersByType` is a newer convenience wrapper that
-- is NOT present on every build - calling it unconditionally kills the resource on
-- the first connection, which is exactly what happened on this server. So the
-- guaranteed API is primary and the optional one is only used when it exists.
--
-- The returned value is normalised to a bare digit string, because the two APIs
-- disagree about the prefix and `accounts.discord_id` is stored bare.
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

--- The player's Rockstar license, or nil.
---
--- There is no `GetPlayerLicense` in the server runtime. The name reads exactly
--- right and does not exist, so calling it took the whole character creation
--- flow down with it: `Identity.beginSession` runs immediately before the
--- appearance is saved, so every "Fertig" in the creator died on the line
--- after the session insert - and the player was left with a character that
--- was never written.
---
--- The license is in the IDENTIFIERS, behind the `license:` prefix, and that
--- is where every other identifier-based lookup in this file reads it from.
local function licenseOf(src)
  for _, entry in ipairs(GetPlayerIdentifiers(src) or {}) do
    local kind, value = string.match(entry, '^(%w+):(.+)$')
    if kind == 'license' then return value end
  end
  return nil
end

-- Public because sv_main.lua's connection gate needs the same answer, and two
-- copies of this logic are two places for them to disagree.
Identity.discordIdOf = discordIdOf

-- Resolve the account behind a connection. Identity comes from the connection,
-- never from anything the client sends.
--
-- `status = 'active'` is filtered HERE as well as in the `playerConnecting`
-- whitelist check. The connecting check is the gate, but this function is also
-- reached from `nifty:server:ready`, and a gate that only exists in one of two
-- paths to the same privilege is not a gate. A pending or suspended account must
-- resolve to nothing here, so that being whitelisted once and suspended later
-- actually stops something.
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
  -- `position` IS IN THIS LIST. It was not, and the column it feeds is the one
  -- the player feels: `worldPayload` reads `character.position` to decide
  -- whether the character resumes where it stood or starts at the default
  -- spawn point. Without the column the value was always nil, and every
  -- character started at the default point - no matter how often the autosave
  -- had written the position down.
  return Db.one([[
    SELECT id, first_name, last_name, date_of_birth, gender, appearance, position, spawn_point
      FROM characters
     WHERE account_id = ?
     LIMIT 1
  ]], { accountId }, 'identity:character')
end

-- Open a session. The slot ID goes in for auditing only.
function Identity.beginSession(src, characterId)
  local sessionId = Db.insert([[
    INSERT INTO sessions (character_id, fivem_slot_id, fivem_license)
    VALUES (?, ?, ?)
  ]], { characterId, src, licenseOf(src) }, 'identity:beginSession')

  ActiveSessions[src] = { characterId = characterId, sessionId = sessionId }
  return sessionId
end

function Identity.getActiveCharacter(src)
  local entry = ActiveSessions[src]
  return entry and entry.characterId or nil
end

-- Every slot this resource currently believes is active.
--
-- Exists for the session watchdog, which has to compare this list against the
-- engine's player list to find slots the engine has released. Keeping the table
-- private is deliberate; exposing a copy of the keys is not the same as exposing
-- the table.
function Identity.activeSlots()
  local slots = {}
  for src in pairs(ActiveSessions) do slots[#slots + 1] = src end
  return slots
end

-- The DB session id for this connection, or nil. Used by the Stütze to link a
-- payout to the session it was paid in - ADR-0009 needs that link to tell
-- "someone stayed online too long" apart from "someone was paid too much".
function Identity.getActiveSessionId(src)
  local entry = ActiveSessions[src]
  return entry and entry.sessionId or nil
end

-- Persist a character's mutable state. Always keyed by character UUID.
--
-- `opts.fromCreator` is the ONE case where the ownership check does not
-- apply: the character creator, where the loadout IS the character's own
-- choice and the ownership is granted immediately afterwards.
--
-- Without it, a character could never keep a first appearance. The check asks
-- "does this character own these pieces?" and for a new character the answer
-- is always no - because the pieces are granted AFTER the save. The creator
-- was therefore a deadlock: save first, be the owner later, and the check
-- refuses the save because the character is not yet the owner.
--
-- EVERY OTHER CHECK STILL APPLIES THERE. The allowlist, the model and the
-- bounds are what stop a client from writing something the server would not
-- accept. The ownership check is what stops a client from claiming a piece it
-- did not pick - and the creator is the place where picking happens.
function Identity.saveCharacter(src, patch, opts)
  local characterId = Identity.getActiveCharacter(src)
  if not characterId then return false end

  local sets, params = {}, {}
  local fromCreator = opts and opts.fromCreator

  -- A REFUSAL IS NOT A REASON TO THROW THE REST AWAY.
  --
  -- The autosave sends the appearance AND the position in one call, and the
  -- two have nothing to do with each other. When the appearance was refused
  -- - a piece the character does not own, a collection the server does not
  -- permit - the function returned false right there, and the position was
  -- never written: the character came back where it had been last, forever,
  -- and nothing in the log said that the position had been dropped as well.
  --
  -- So the branches are independent. Each one either contributes its column
  -- or records why it did not, and the write happens with whatever was
  -- accepted.
  local refused = nil

  if patch.appearance ~= nil then
    local appearance, err = Validate.appearance(patch.appearance)
    if not appearance then
      print(('[%s] refused to save appearance for %s: %s'):format(RESOURCE, characterId, err))
      refused = err
    else
      -- Every piece the loadout wears must be one this character owns.
      -- checkEquipped is what stops a forged saveCharacter from sneaking
      -- a drawable past - a client cannot claim they own a piece they did
      -- not buy or pick in the creator.
      if not fromCreator then
        local owned, ownedErr = Owned.checkEquipped(characterId, appearance)
        if not owned then
          print(('[%s] refused to save appearance for %s: not owned (%s)'):format(
            RESOURCE, characterId, tostring(ownedErr)))
          refused = ownedErr
        else
          sets[#sets + 1] = 'appearance = ?'
          params[#params + 1] = json.encode(appearance)
        end
      else
        sets[#sets + 1] = 'appearance = ?'
        params[#params + 1] = json.encode(appearance)
      end
    end
  end

  if patch.spawnPoint ~= nil then
    local spawnPoint, err = Validate.spawnPoint(patch.spawnPoint)
    if not spawnPoint then
      print(('[%s] refused to save spawn point for %s: %s'):format(
        RESOURCE, characterId, tostring(err)))
      refused = refused or err
    else
      sets[#sets + 1] = 'spawn_point = ?'
      params[#params + 1] = spawnPoint
    end
  end

  if patch.position ~= nil then
    local position, err = Validate.position(patch.position)
    if not position then
      print(('[%s] refused to save position for %s: %s'):format(RESOURCE, characterId, tostring(err)))
      refused = refused or err
    else
      sets[#sets + 1] = 'position = ?'
      params[#params + 1] = json.encode(position)
    end
  end

  -- Nothing was accepted: there is nothing to write, and the caller has to
  -- hear about it - the creator turns this into "Das Aussehen konnte nicht
  -- gespeichert werden".
  if #sets == 0 then return false end

  params[#params + 1] = characterId
  Db.update(('UPDATE characters SET %s WHERE id = ?'):format(table.concat(sets, ', ')),
            params, 'identity:saveCharacter')

  -- The write happened. A refused part of the patch does not undo the part
  -- that was accepted - but the caller is told, so it can say so.
  return true, refused
end

function Identity.endSession(src)
  local entry = ActiveSessions[src]
  if not entry then return end

  if entry.sessionId then
    Db.update('UPDATE sessions SET disconnected_at = NOW() WHERE id = ?',
              { entry.sessionId }, 'identity:endSession')
  end

  ActiveSessions[src] = nil
end

-- Identity closes its own sessions.
--
-- This lived in sv_main and was moved here deliberately. sv_main orchestrates a
-- connection; the session belongs to this module. Registering it here also means
-- the guarantee is exercised by the harness, which loads this file but not
-- sv_main - and it keeps the rule "the guard drives teardown, the owner performs
-- it" free of exceptions.
SessionGuard.onClose('identity', Identity.endSession)

exports('getActiveCharacter', Identity.getActiveCharacter)
exports('activeSlots', Identity.activeSlots)
exports('saveCharacter', Identity.saveCharacter)
exports('endSession', Identity.endSession)
