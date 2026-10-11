--[[
  The NUI focus broker.

  This file is the ONLY place in Nifty Life 2.0 that calls `SetNuiFocus`.

  Why that matters: `SetNuiFocus` is a single global client native, not a
  per-resource one. Every system resource owns its own `ui_page` and therefore
  its own CEF browser, but they all share ONE keyboard. If each of them called
  the native on its own initiative, last writer wins, the previous surface keeps
  drawing while it has lost the keyboard, and the player types into a window they
  are not looking at. The symptom is not "it breaks" — it is "the close button
  does not respond", which is close to undebuggable.

  The rule this file enforces: at most ONE surface may hold the keyboard, it is
  always named, and both natives move together. That is why there is a broker at
  all instead of each resource doing the obvious thing.

  The contract a system resource uses:
    exports.nifty_ui:acquire('nifty-phone')   -> true|false
    exports.nifty_ui:release('nifty-phone')
    exports.nifty_ui:holder()                 -> string|nil

  Acquire is a REQUEST, not a steal. A surface that is already open must be told
  to close, not silently overwritten, so `acquire` returns false and the caller
  decides what that means (the chat input refuses; the phone closes the chat).
  Letting `acquire` preempt would just move the same bug one layer down: a system
  would open on top of another without the other knowing it lost focus.
]]

local RESOURCE = GetCurrentResourceName()

--- Name of the surface currently holding the keyboard, or nil.
local Holder = nil

--- Focus moves in these two calls TOGETHER, always in this order.
---
--- `SetNuiFocusKeepInput` is the second half of the pair, not a nicety. Setting
--- focus without it leaves game input blocked in some states; releasing focus
--- without it leaves the mouse captured. Both halves are called on every acquire
--- and every release, including the ones driven by a resource stopping underneath
--- us — a captured cursor whose only cure is a reconnect is the classic FiveM bug.
local function apply(open)
  SetNuiFocus(open, open)
  SetNuiFocusKeepInput(open)
end

--- Ask for the keyboard. Returns true only if this surface ends up holding it.
---
--- The caller passes its own resource name rather than this file reading
--- `GetCurrentResourceName()`. An export runs in THIS resource's context, so the
--- name read here would be `nifty-ui` for every caller — the exact opposite of
--- what an arbitration needs to know.
exports('acquire', function(name)
  if type(name) ~= 'string' or name == '' then return false end

  -- Re-acquiring what you already hold is not an error. A chat input that is
  -- closed and reopened inside one frame would otherwise deadlock against itself.
  if Holder == name then return true end

  if Holder ~= nil then return false end

  Holder = name
  apply(true)
  return true
end)

--- Hand the keyboard back.
---
--- The name is checked rather than ignored: a surface that was told "no" by
--- `acquire` and then calls `release` must NOT drop the keyboard from whoever
--- actually has it. That mistake would look exactly like random focus loss.
exports('release', function(name)
  if Holder ~= name then return false end

  Holder = nil
  apply(false)
  return true
end)

--- Who has it. Diagnostics and the vertical slice's unverified-focus checklist.
exports('holder', function() return Holder end)

--- Drop focus no matter who holds it.
---
--- Reserved for the two situations where the holder cannot be trusted to release:
--- the player left, or the resource holding it is being restarted. Without this a
--- crashed resource leaves the player with a captured mouse and no way out.
exports('forceRelease', function()
  if Holder == nil then return false end

  Holder = nil
  apply(false)
  return true
end)

--- A player reconnecting must not inherit somebody else's focus, and must not
--- leave it held. Both halves, because a disconnect during an open phone is the
--- common case, not the edge case.
AddEventHandler('playerDropped', function()
  Holder = nil
  apply(false)
end)

--- This resource stopping must never leave the keyboard held, whatever is open.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end

  Holder = nil
  apply(false)
end)

--- AND the reverse: when the resource that HOLDS focus goes away, the broker has
--- to notice. Nothing tells it, so it watches. Without this the player keeps a
--- captured mouse with no surface drawn over it, and the only way out is a
--- reconnect — the single most reported FiveM UI bug there is.
AddEventHandler('onClientResourceStop', function(resource)
  if Holder ~= resource then return end

  Holder = nil
  apply(false)
end)

print(('[%s] NUI focus broker ready'):format(RESOURCE))