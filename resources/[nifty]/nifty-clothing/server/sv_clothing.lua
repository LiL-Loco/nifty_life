--[[
  Server side of the hood toggle: player-facing notices, and the diagnostics
  channel that makes the client observable.

  There is deliberately no clothing logic here. RAGE MP's version of this
  feature lived on the server because its server can set clothes on a player;
  FiveM's cannot, so the ped is only ever touched on the client. What the
  server owns is the conversation: a message to the player, and the log.
]]

local RESOURCE = GetCurrentResourceName()
local PREFIX = ('[%s]'):format(RESOURCE)

local Chat = exports['nifty-chat']

--- Diagnostics are rate limited per slot.
---
--- Without this, a client that spams the key spams the log, and a log that can be
--- flooded is a log nobody reads. Four lines per player per ten seconds is far
--- more than a person can trigger by pressing a key.
local DIAG_WINDOW_MS = 10000
local DIAG_MAX = 4
local diagBudget = {}

local function allowDiag(src)
  local now = GetGameTimer()
  local entry = diagBudget[src]

  if not entry or now - entry.startedAt > DIAG_WINDOW_MS then
    diagBudget[src] = { startedAt = now, count = 1 }
    return true
  end

  if entry.count >= DIAG_MAX then return false end

  entry.count = entry.count + 1
  return true
end

AddEventHandler('playerDropped', function()
  diagBudget[source] = nil
end)

--- A short German line for the player.
RegisterNetEvent('nifty:server:hoodNotice', function(message)
  local src = source
  if type(message) ~= 'string' then return end

  -- The notice is ours, not the player's: a client could otherwise use this
  -- channel to put arbitrary text into another player's chat.
  Chat.system(src, message)
end)

--- Diagnostics from the client, straight into the server log.
---
--- This exists because of a measured problem, not a hypothetical one: the
--- CitizenFX log is truncated at roughly 120 KB and ends before the first
--- `print()` of any nifty-* client resource. A client-side diagnostic that
--- nobody can read is the same as no diagnostic at all.
RegisterNetEvent('nifty:server:diag', function(message)
  local src = source
  if type(message) ~= 'string' then return end
  if #message > 300 then message = message:sub(1, 300) end
  if not allowDiag(src) then return end

  print(('%s hood (slot %s): %s'):format(PREFIX, tostring(src), message))
end)