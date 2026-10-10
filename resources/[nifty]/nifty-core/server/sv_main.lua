--- Server main (ADR-0014 step 2, identity gate lands in step 3).
---
--- Today this proves the vertical slice can start: the whitelist gate reads a
--- Discord ID from the connection and looks it up server-side. No character
--- creation yet — that is layer 3.

local RESOURCE = GetCurrentResourceName()

--- ADR-0014: the vertical slice ends with "reconnect and it is still there".
--- That depends entirely on resolving identity through a stable key rather
--- than the FiveM slot ID (ADR-0001). This function is where that is enforced:
--- slot IDs never appear in a query, only the Discord ID from the connection.
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

--- Fires before the player enters. `deferrals.defer()` keeps the player in the
--- connection queue while we hit the database, so a slow query shows as a
--- loading screen rather than a timeout.
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
  local src = source
  deferrals.defer()
  Citizen.Wait(0)

  deferrals.update('Nifty Life 2.0 — checking your application…')

  -- Discord snowflake from the player's connected identifiers. We never accept
  -- an identifier from the client: FiveM reports it, we read it here.
  local discordId = GetPlayerIdentifiersByType(src, 'discord') or {}
  discordId = discordId[1]

  if not discordId then
    deferrals.done('This server requires a connected Discord account. ' ..
      'Link Discord in your FiveM account settings and reconnect.')
    return
  end

  if not isWhitelisted(discordId) then
    deferrals.done('You are not whitelisted on Nifty Life 2.0.\n' ..
      'Apply at the website — your application has to be approved first.')
    return
  end

  deferrals.done()
end)

RegisterCommand('niftystatus', function(src)
  local discordId = GetPlayerIdentifiersByType(src, 'discord') or {}
  print(('[%s] slot %s discord=%s whitelisted=%s'):format(
    RESOURCE, src, discordId[1] or 'none', tostring(isWhitelisted(discordId[1]))))
end, true)

AddEventHandler('playerDropped', function()
  local src = source
  print(('[%s] slot %s disconnected'):format(RESOURCE, src))
  -- NOTE: no character state is saved by slot id here, and there must never be.
  -- Layer 3 closes this via the sessions table.
end)

exports('isWhitelisted', isWhitelisted)