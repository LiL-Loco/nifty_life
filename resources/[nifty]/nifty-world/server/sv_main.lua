-- Server main — the connect-to-play spine (ADR-0014 layers 2-3).
--
-- Flow:
--   playerConnecting  -> whitelist check (deferred, so a slow query is a
--                        loading screen rather than a timeout)
--   nifty:server:ready-> find the character (ADR-0008). It is created on the
--                        WEBSITE through create_character_from_web (migration
--                        021), not here. `appearance IS NULL` means "created but
--                        not finished" and opens the creator; anything else enters
--                        the world directly.
--   finishAppearance  -> save the look, then enter the world
--   play              -> save is keyed by character UUID, never by slot (ADR-0001)
--
-- Nothing below trusts a value that did not come from the connection itself.

local RESOURCE = GetCurrentResourceName()

-- From the base facade, fetched by shared/core.lua at load. These were globals
-- when this file lived inside nifty-core.
--
-- THEY MUST BE DECLARED HERE, at the top of the file, not further down. A `local`
-- only exists from the line it appears to the end of the chunk, so a binding placed
-- next to the code that first uses it is invisible to everything above it — which
-- is how `discordIdOf` ended up at line 20 indexing a nil `Identity` while the
-- binding sat at line 74. Read the file top to bottom; the dependency has to come
-- before the dependent.
local Db = Nifty.Db
local Identity = Nifty.Identity
local SessionGuard = Nifty.SessionGuard

-- The systems this resource orchestrates.
--
-- This file is the ONLY place allowed to know that all of them exist, because the
-- connect-to-play sequence is what needs them together: a character is created,
-- gets a phone number, gets a starting inventory, and then the economy and the
-- Stütze start on top of it.
--
-- The dependency direction is one-way and that is the entire reason the base has
-- no cycles. nifty-core knows about the database and about identity. nifty-inventory
-- knows about the database. nifty-world knows about both, because it is the layer
-- above them. Nobody below knows anybody above.
--
-- Fetched once at load. An export call per player connect would be a cross-resource
-- round trip on the hot path, and a resource that is stopped mid-session would make
-- it fail at the worst moment.
local Economy   = Nifty.Economy
local Inventory = exports['nifty-inventory']
local Stuetze   = Nifty.Stuetze
local Phone     = exports['nifty-phone']

-- How many times a client may ask for bootstrap before we treat it as hostile.
local BootstrapAttempts = {}
local MAX_BOOTSTRAP_ATTEMPTS = 10

-- Identity.discordIdOf owns the identifier read (identity.lua). This file only
-- decides what an answer means.
local function discordIdOf(src)
  return Identity.discordIdOf(src)
end

-- True when the account is active and not currently banned. The Discord ID is
-- read from the connection, so a client cannot present someone else's.
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

-- Send the client its character, open a session, and let the world begin.
local function enterWorld(src, character, hasSession)
  if not hasSession then
    Identity.beginSession(src, character.id)
  end

  -- ADR-0018: every character starts with a handset and an ID. This used to be
  -- called right after `Identity.createCharacter`, in the path that created a
  -- character - and that path no longer exists, because the website creates it.
  -- Left where it was, every character made on the website would have entered the
  -- world with an empty inventory and no phone, silently. It belongs to entering
  -- the world, not to creating the row, so that is where it lives now. Idempotent,
  -- so a reconnect cannot duplicate the handset.
  Inventory:grantStartingItems(character.id)

  -- Layer 4. Order matters: money and items are pushed before the Stütze arms,
  -- so the first balance a player sees is the truth rather than the truth plus
  -- an instalment that arrives a frame later.
  Economy:push(src, character.id)
  Inventory:push(src, character.id)
  Stuetze:start(src, character.id)

  -- Resume at the player's last known position if the column has one. A null
  -- `position` means "first time after the creator finished" and the picker
  -- opens. A malformed value falls back to the default spawn, same as null.
  local lastPosition = nil
  if character.position and character.position ~= '' then
    local ok, decoded = pcall(json.decode, character.position)
    if ok and type(decoded) == 'table' and decoded.x and decoded.y and decoded.z then
      lastPosition = decoded
    end
  end

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
    -- `or SpawnPoints.default` and not `SpawnPoints[x or 'default']`: a row can
  -- carry a spawn_point that no longer exists (a point removed from
  -- appearance_config while the character row survives it), and a nil `spawn`
  -- kills the CLIENT on `data.spawn.x` at the exact moment the player was told
  -- they had entered the world.
  spawn = lastPosition or (SpawnPoints[character.spawn_point] or SpawnPoints.default),
  usePicker = lastPosition == nil,
  })

  -- The unread badge has to exist before the player first presses the key,
  -- otherwise the phone opens with no idea how many messages are waiting. Sent
  -- only if the character is actually carrying a handset (ADR-0018).
  if Inventory:has(character.id, 'phone', 1) then
    TriggerClientEvent('nifty:client:phoneUnread', src, Phone:unreadCount(character.id))
  end
end

-- Client signals its resources are up. Used instead of guessing when the
-- player has finished connecting.
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
  if not character then
    -- The character is created on the WEBSITE, through
    -- create_character_from_web (migration 021). It is not created here, and it is
    -- not created by opening an empty creator either: a whitelisted account
    -- without a character is a player who has not finished signing up, and the
    -- honest answer is to say where the next step is.
    print(('[%s] no character for account %s (discord %s)'):format(
      RESOURCE, account.id, tostring(account.discord_id)))
    return DropPlayer(src, 'Du hast noch keinen Charakter.\n' ..
      'Erstelle ihn auf der Website und verbinde dich danach erneut.')
  end

  -- `appearance IS NULL` is the single "not finished yet" signal. No status column:
  -- two ways to say the same thing drift, and this one cannot - it is set in exactly
  -- one place, by the transaction that wrote the row. It also means an abandoned
  -- creator reopens on the next login without anyone remembering to reset a flag.
  if character.appearance == nil or character.appearance == '' then
    TriggerClientEvent('nifty:client:openCreator', src, {
      gender    = character.gender,
      firstName = character.first_name,
      lastName  = character.last_name,
    })
    return
  end

  enterWorld(src, character)
end)

-- The character already exists. The player has only chosen how it looks.
--
-- This replaces `nifty:server:createCharacter`. There is no name, no date of
-- birth, no birthplace and no gender in this payload, because none of those are
-- chosen here - the website wrote them, and the gender in particular is not a
-- preference but the fact that decides which ped model this character may wear.
RegisterNetEvent('nifty:server:finishAppearance', function(payload)
  local src = source

  if Identity.getActiveCharacter(src) then
    return TriggerClientEvent('nifty:client:creatorError', src, 'Du spielst bereits.')
  end

  local account = Identity.resolveAccount(src)
  if not account then
    return DropPlayer(src, 'Dein Konto konnte nicht geladen werden. Bitte wende dich an das Team.')
  end

  local character = Identity.getCharacter(account.id)
  if not character then
    return DropPlayer(src, 'Kein Charakter gefunden. Bitte erstelle ihn auf der Website.')
  end

  -- Already finished: a resubmitted menu, or a second client racing the first.
  -- Not an error - send them in rather than making a player who already dressed
  -- their character do it again because they pressed Enter twice.
  if character.appearance ~= nil and character.appearance ~= '' then
    return enterWorld(src, character)
  end

  local appearance = type(payload) == 'table' and payload.appearance or nil
  if type(appearance) ~= 'table' then appearance = {} end

  -- The model is DERIVED from the stored gender, never taken from the client.
  -- Accepting it would let any client put a male model on a character the website
  -- recorded as female, and this is the one field whose consequence is visible
  -- everywhere else in the game.
  --
  -- `nonbinary` has no model attached, because the gender is a fact about the
  -- player and the model is a fact about the body, and the database records only
  -- the first one. Then the player chooses in the creator - and the choice is
  -- checked against the SAME allowlist everything else is checked against, so
  -- "nonbinary" never becomes a way to spawn any ped in the game.
  local model = AppearanceConfig.PED_MODELS[character.gender]

  if not model then
    local offered = type(appearance.model) == 'string' and AppearanceConfig.PED_MODELS[appearance.model] or nil
    if not offered then
      print(('[%s] character %s: gender "%s" has no model and none was offered'):format(
        RESOURCE, character.id, tostring(character.gender)))
      return TriggerClientEvent('nifty:client:creatorError', src,
        'Dieser Charakter hat kein gültiges Geschlecht. Bitte wende dich an das Team.')
    end
    model = offered
  end

  appearance.model = model

  -- The session is opened BEFORE the save, because `Identity.saveCharacter` is
  -- keyed by the active character. Saving without one is refused, quietly, and a
  -- quiet refusal here looks exactly like a creator that ignores the Fertig button.
  Identity.beginSession(src, character.id)

  if not Identity.saveCharacter(src, { appearance = appearance }) then
    Identity.endSession(src)
    return TriggerClientEvent('nifty:client:creatorError', src,
      'Das Aussehen konnte nicht gespeichert werden. Bitte erneut versuchen.')
  end

  -- Re-read rather than reusing `character`: its `appearance` is still the NULL
  -- from before the save, and the client would then be told to spawn a ped with no
  -- clothing at all.
  enterWorld(src, Identity.getCharacter(account.id), true)
end)

-- Leaving the creator on purpose.
--
-- The ped is frozen and invisible, so a player who closes the menu and stays
-- connected stands still in a dark void for as long as they like. Dropping them is
-- the honest outcome: nothing is lost, `appearance IS NULL` reopens the creator on
-- the next login, and there is no half-state to reason about.
RegisterNetEvent('nifty:server:cancelCreator', function()
  local src = source
  if Identity.getActiveCharacter(src) then return end

  DropPlayer(src, 'Du hast die Charaktererstellung abgebrochen.\n' ..
    'Dein Charakter bleibt erhalten - beim nächsten Verbinden geht es weiter.')
end)

-- Save mutable character state. Keyed by the active session's character UUID.
RegisterNetEvent('nifty:server:saveCharacter', function(payload)
  local src = source

  -- An unconnected or session-less player has nothing to save. This is the check
  -- that stops a client from saving as a character it is not playing.
  if not Identity.getActiveCharacter(src) then return end
  if type(payload) ~= 'table' then return end

  -- Capture the player's current world position so the next login resumes
  -- there. Server-side, not client-supplied: the client never gets to tell
  -- the server "I am at 100000, 100000" - the server reads the ped's actual
  -- coords. Identity.saveCharacter validates and writes them to the
  -- `position` JSON column.
  local ped = GetPlayerPed(src)
  if ped and ped ~= 0 then
    local coords = GetEntityCoords(ped)
    payload.position = { x = coords.x, y = coords.y, z = coords.z }
  end

  Identity.saveCharacter(src, payload)
end)

-- Per-connection scratch state. The session itself is closed by identity.lua,
-- which owns it; all this needs is to stop its own timers.
SessionGuard.onStop('bootstrap', function(src)
  BootstrapAttempts[src] = nil
  Stuetze:stop(src)
end)

RegisterCommand('niftystatus', function(src)
  local characterId = Identity.getActiveCharacter(src)
  print(('[%s] slot=%s discord=%s whitelisted=%s character=%s'):format(
    RESOURCE, src, tostring(discordIdOf(src)),
    tostring(isWhitelisted(discordIdOf(src))), tostring(characterId)))
end, true)

exports('isWhitelisted', isWhitelisted)
exports('resolveAccount', Identity.resolveAccount)