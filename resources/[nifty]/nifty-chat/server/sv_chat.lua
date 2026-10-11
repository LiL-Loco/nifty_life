--[[
  Chat — the server half.

  This replaces the downloaded `chat` resource, which shipped three hardcoded
  `http://chat/...` URLs. FiveM serves NUI over HTTPS, so the browser blocked
  every one of them as mixed content and the resource could not do anything.
  Two of its files were also a Vue 2.3.3-era layout with no build step, i.e.
  code that predates the NUI scheme by years.

  What this file decides, and nothing else:
    - whether a message may be spoken at all
    - who it is from        (the CHARACTER, resolved server-side)
    - who may hear it       (the proximity check)

  What it never decides: anything the client asserted. The body arrives as a
  string and is treated as untrusted text for its whole life here — trimmed,
  length-capped, stripped of control characters, and rendered by the NUI with
  `textContent`. There is no path by which a client can choose its own author,
  its own colour, or a format string.

  The author is read from the CHARACTER, not from the connection's player name.
  On a whitelisted server the FiveM name is whatever somebody typed in the Rockstar
  account, and the whole point of the whitelist is that the character is the
  identity. A player would otherwise be able to speak as anybody simply by
  renaming.
]]

local RESOURCE = GetCurrentResourceName()

--- From the base facade, fetched by shared/core.lua at load.
---
--- These were globals when this file lived inside nifty-core. They are now locals
--- resolved from another resource, which is the whole reason `shared/core.lua`
--- exists — see the note there about chunk scope.
local Db = Nifty.Db
local GetSetting = Nifty.GetSetting
local Identity = Nifty.Identity

--- System-line sink. Declared rather than created implicitly by
--- `function Chat.system(...)`, because an undeclared name here would be a GLOBAL
--- that silently disappears if this file ever loaded twice — and the original
--- `chat` resource exported a global `Chat` table that other resources may still
--- expect to exist.
Chat = Chat or {}

--- Last accepted message per connection slot, in server ms.
---
--- Keyed by slot, not by character, because the rate limit is about the CONNECTION:
--- a player who reconnects to escape a cooldown has not escaped anything, but they
--- also cost a fresh slot, and the connect gate already limits how fast somebody
--- can cycle slots.
local LastSpokeAt = {}

--- Characters are looked up per message rather than cached in the session.
--- That is one primary-key read per accepted message, and the cooldown is what
--- makes it affordable. Caching would mean a rename — or a stale name after a
--- reconnect — outliving the session that held it, and a chat log that attributes
--- messages to a name the player no longer has is worse than a slow chat.
local function authorOf(src)
  local characterId = Identity.getActiveCharacter(src)
  if not characterId then return nil end

  return Db.one([[
    SELECT first_name, last_name
      FROM characters
     WHERE id = ?
     LIMIT 1
  ]], { characterId }, 'chat:author')
end

--- Strip what a chat log has no business displaying.
---
--- Control characters, zero-width joiners and the bidirectional overrides that can
--- make a message read backwards or hide its own author. This is not paranoia: a
--- NUI that renders `textContent` is safe from injection, but a player whose name
--- is rendered with an RLO override is a genuine spoofing vector against everyone
--- reading the log.
---
--- Written with `\u{...}` rather than the byte sequences it expands to. Lua accepts
--- both, but the escape is only self-explanatory in one of them, and a reader who
--- cannot tell what is being filtered will not dare to extend the list.
local function sanitise(text)
  -- C0 controls, DEL, and C1 controls. Written as a range so tab, newline and
  -- carriage return go with them: a chat log is one line per message.
  text = text:gsub('[%z\1-\31\127-\159]', '')

  -- Zero-width: they make two different messages render identically.
  text = text:gsub('\u{200B}', '')  -- zero width space
  text = text:gsub('\u{200C}', '')  -- zero width non-joiner
  text = text:gsub('\u{200D}', '')  -- zero width joiner
  text = text:gsub('\u{FEFF}', '')  -- byte order mark

  -- Bidirectional overrides. U+202E (right-to-left override) is the one that
  -- matters: it can make a player's name render as somebody else's.
  text = text:gsub('[\u{202A}-\u{202E}\u{2066}-\u{2069}]', '')

  -- Collapse runs of whitespace so a pasted paragraph cannot push the log off
  -- screen, and trim the ends.
  text = text:gsub('%s+', ' ')
  text = text:gsub('^%s+', ''):gsub('%s+$', '')

  return text
end

--- Is this player close enough to hear the speaker?
---
--- OneSync gives the server real coordinates, which is what makes proximity a
--- SERVER decision. The alternative — trusting the client's own distance check — is
--- a check a cheater does not perform.
---
--- A missing ped (the character has not spawned yet, or has just died) yields no
--- coordinates. That is NOT the same as "too far": returning false there would
--- make a player who speaks at their own spawn point invisible, and the symptom —
--- a chat that sometimes works — is much harder to report than one that never does.
local function canHear(listener, speaker, radius)
  if listener == speaker then return true end

  local listenerPed = GetPlayerPed(listener)
  local speakerPed = GetPlayerPed(speaker)

  if not listenerPed or listenerPed == 0 or not speakerPed or speakerPed == 0 then
    return true
  end

  local a = GetEntityCoords(listenerPed)
  local b = GetEntityCoords(speakerPed)

  -- #(a - b) is the Three.js/GTA vector distance: metres, no sqrt needed.
  local dx = a.x - b.x
  local dy = a.y - b.y
  local dz = a.z - b.z

  return (dx * dx + dy * dy + dz * dz) <= (radius * radius)
end

-- ---------------------------------------------------------------------------
-- The event
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:chatSay', function(payload)
  local src = source

  if type(payload) ~= 'table' then return end

  local raw = payload.text
  if type(raw) ~= 'string' then return end

  local body = sanitise(raw)
  local maxLength = GetSetting('chat.max_length', 150)
  if #body > maxLength then
    body = body:sub(1, maxLength)
  end

  if body == '' then return end

  -- Rate limit before anything expensive. The lookup is a primary key read and
  -- the author lookup is another, so a player spamming T+Enter would otherwise be
  -- able to make the server do work it has no reason to do.
  local cooldown = GetSetting('chat.cooldown_ms', 1200)
  local now = GetGameTimer()
  local last = LastSpokeAt[src]

  if last and (now - last) < cooldown then
    -- Silent. A "you are talking too fast" line for every rejected keystroke-run
    -- turns the log into a wall of refusals and teaches players the message is
    -- noise.
    return
  end
  LastSpokeAt[src] = now

  local character = authorOf(src)
  if not character then
    TriggerClientEvent('nifty:client:chat', src, {
      system = true,
      text = 'Du kannst erst schreiben, wenn du einen Character hast.',
    })
    return
  end

  local author = character.first_name
  if character.last_name and character.last_name ~= '' then
    author = author .. ' ' .. character.last_name
  end

  local radius = GetSetting('chat.radius', 40)

  for _, slot in ipairs(GetPlayers()) do
    local listener = tonumber(slot)
    if listener and canHear(listener, src, radius) then
      TriggerClientEvent('nifty:client:chat', listener, {
        author = author,
        text = body,
      })
    end
  end
end)

--- Server-initiated lines: join, leave, and the refusals a player should read.
---
--- Separate from `chatSay` on purpose. A system line has no author and is
--- rendered in a different style by the NUI, so a player cannot pass one off as
--- something somebody else said.
function Chat.system(target, text)
  TriggerClientEvent('nifty:client:chat', target, { system = true, text = text })
end

AddEventHandler('playerDropped', function()
  -- Cleared here rather than left to accumulate: the table is keyed by slot, and
  -- slots are RECYCLED. A stale entry would hand the next player to occupy that
  -- slot somebody else's cooldown, and the symptom would be "chat sometimes does
  -- not work" for no visible reason.
  LastSpokeAt[source] = nil
end)

exports('system', function(target, text)
  if type(target) ~= 'number' or type(text) ~= 'string' then return false end
  Chat.system(target, text)
  return true
end)

print(('[%s] chat loaded'):format(RESOURCE))