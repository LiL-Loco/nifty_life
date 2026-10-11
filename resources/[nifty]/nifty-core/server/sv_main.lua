--- Server main — the connect-to-play spine (ADR-0014 layers 2-3).
---
--- Flow:
---   playerConnecting  -> whitelist check (deferred, so a slow query is a
---                        loading screen rather than a timeout)
---   nifty:server:ready-> load or create the single character (ADR-0008)
---   play              -> save is keyed by character UUID, never by slot (ADR-0001)
---
--- Nothing below trusts a value that did not come from the connection itself.

local RESOURCE = GetCurrentResourceName()

--- How many times a client may ask for bootstrap before we treat it as hostile.
local BootstrapAttempts = {}
local MAX_BOOTSTRAP_ATTEMPTS = 10

--- Identity.discordIdOf owns the identifier read (identity.lua). This file only
--- decides what an answer means.
local function discordIdOf(src)
  return Identity.discordIdOf(src)
end

--- True when the account is active and not currently banned. The Discord ID is
--- read from the connection, so a client cannot present someone else's.
local function isWhitelisted(discordId)
  if not discordId or discordId == '' then return false end

  local row = Db.one([[
    SELECT a.id AS account_id
      FROM accounts a
     WHERE a.discord_id = ?
       AND a.status = 'active'
       AND NOT EXISTS (
         SELECT 1 FROM bans b
          WHERE b.discord_id = a.discord_id
            AND b.revoked_at IS NULL
            AND (b.expires_at IS NULL OR b.expires_at > NOW())
       )
     LIMIT 1
  ]], { discordId }, 'whitelist:check')

  return row ~= nil
end

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
  local src = source
  deferrals.defer()
  Citizen.Wait(0)

  deferrals.update('Nifty Life 2.0 — checking your application…')

  local discordId = discordIdOf(src)
  if not discordId then
    deferrals.done('This server requires a connected Discord account. ' ..
      'Link Discord in your FiveM account settings and reconnect.')
    return
  end

  if not isWhitelisted(discordId) then
    -- Approval is a human act (ADR-0007) and the website that performs it does
    -- not exist yet, so an admin currently approves by inserting a row. That
    -- means the ID has to be obtainable without a debugger — print it.
    print(('[%s] whitelist rejection: Discord ID %s (name "%s")').format(
      RESOURCE, discordId, tostring(name)))
    deferrals.done('You are not whitelisted on Nifty Life 2.0.\n' ..
      'Apply on the website — a human has to approve your application first.')
    return
  end

  deferrals.done()
end)

--- Send the client its character, open a session, and let the world begin.
local function enterWorld(src, character)
  Identity.beginSession(src, character.id)

  -- Layer 4. Order matters: money and items are pushed before the Stütze arms,
  -- so the first balance a player sees is the truth rather than the truth plus
  -- an instalment that arrives a frame later.
  Economy.push(src, character.id)
  Inventory.push(src, character.id)
  Stuetze.start(src, character.id)

  TriggerClientEvent('nifty:client:enterWorld', src, {
    character = {
      id = character.id,
      firstName = character.first_name,
      lastName = character.last_name,
      dateOfBirth = character.date_of_birth,
      gender = character.gender,
      appearance = character.appearance and json.decode(character.appearance) or nil,
      spawnPoint = character.spawn_point,
    },
    spawn = SpawnPoints[character.spawn_point or 'default'],
  })

  -- The unread badge has to exist before the player first presses the key,
  -- otherwise the phone opens with no idea how many messages are waiting. Sent
  -- only if the character is actually carrying a handset (ADR-0018).
  if Inventory.has(character.id, 'phone', 1) then
    TriggerClientEvent('nifty:client:phoneUnread', src, Phone.unreadCount(character.id))
  end
end

--- Client signals its resources are up. Used instead of guessing when the
--- player has finished connecting.
RegisterNetEvent('nifty:server:ready', function()
  local src = source

  local attempts = (BootstrapAttempts[src] or 0) + 1
  BootstrapAttempts[src] = attempts
  if attempts > MAX_BOOTSTRAP_ATTEMPTS then
    DropPlayer(src, 'Nifty Life 2.0 — too many connection attempts.')
    return
  end

  -- A player who already has a session must not be able to bootstrap twice and
  -- overwrite it. One connection, one character.
  if Identity.getActiveCharacter(src) then return end

  local account = Identity.resolveAccount(src)
  if not account then
    DropPlayer(src, 'Your account could not be loaded. Please contact staff.')
    return
  end

  local character = Identity.getCharacter(account.id)
  if character then
    enterWorld(src, character)
  else
    TriggerClientEvent('nifty:client:needsCharacter', src)
  end
end)

--- Create the one character this account is allowed.
RegisterNetEvent('nifty:server:createCharacter', function(payload)
  local src = source

  if Identity.getActiveCharacter(src) then
    return TriggerClientEvent('nifty:client:creatorError', src, 'You are already playing.')
  end

  -- Coerce to a table: the event argument is entirely client-supplied and may
  -- be any type at all, including nil.
  if type(payload) ~= 'table' then payload = {} end

  local character, err = Identity.createCharacter(src, payload)
  if not character then
    print(('[%s] character creation refused for slot %s: %s'):format(RESOURCE, src, tostring(err)))
    return TriggerClientEvent('nifty:client:creatorError', src, tostring(err))
  end

  enterWorld(src, character)
end)

--- Save mutable character state. Keyed by the active session's character UUID.
RegisterNetEvent('nifty:server:saveCharacter', function(payload)
  local src = source

  -- An unconnected or session-less player has nothing to save. This is the check
  -- that stops a client from saving as a character it is not playing.
  if not Identity.getActiveCharacter(src) then return end
  if type(payload) ~= 'table' then return end

  Identity.saveCharacter(src, payload)
end)

-- Per-connection scratch state. The session itself is closed by identity.lua,
-- which owns it; all this needs is to stop its own timers.
SessionGuard.onStop('bootstrap', function(src)
  BootstrapAttempts[src] = nil
  Stuetze.stop(src)
end)

RegisterCommand('niftystatus', function(src)
  local characterId = Identity.getActiveCharacter(src)
  print(('[%s] slot=%s discord=%s whitelisted=%s character=%s'):format(
    RESOURCE, src, tostring(discordIdOf(src)),
    tostring(isWhitelisted(discordIdOf(src))), tostring(characterId)))
end, true)

exports('isWhitelisted', isWhitelisted)
exports('resolveAccount', Identity.resolveAccount)