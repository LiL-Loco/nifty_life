--[[
  Diagnostics from the client, straight into the server log.

  WHY THIS EXISTS

  A client-side `print()` goes to the CLIENT's console (F8) and nowhere else.
  It never reaches the server log - which was measured, not assumed: after a
  client resource printed its name and its probe output, the server log
  contained nothing but the resource's own startup lines.

  So a client-side diagnostic that nobody can read is the same as no
  diagnostic at all, and the one thing a client diagnostic is FOR is that
  somebody reads it.

  This is the channel for the clothing-variation report: whether the engine
  really has the natives the appearance code depends on, and whether a
  variation the engine refused to apply was detected and reported.
]]

local PREFIX = '[nifty-core]'

--- How many reports one player may send in a window.
---
--- The same shape as nifty-clothing's diagnostic budget: a report is worth
--- having, a flood of them is worth less than the log lines it eats.
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

RegisterNetEvent('nifty:server:variationDiag', function(message)
  local src = source
  if type(message) ~= 'string' then return end
  if #message > 300 then message = message:sub(1, 300) end
  if not allowDiag(src) then return end

  print(('%s variation (%s): %s'):format(PREFIX, tostring(src), message))
end)
