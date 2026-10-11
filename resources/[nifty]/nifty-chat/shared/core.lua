--[[
  The bridge to nifty-core, loaded before every file in this resource.

  Why this file exists at all, since `exports.nifty_core:facade()` is one line:

  A `local` in fxmanifest does NOT reach the files loaded after it. Every
  `server_script` / `client_script` chunk is compiled and run as its OWN scope, so
  `local Core = exports.nifty_core:facade()` written in fxmanifest would be gone
  by the time sv_chat.lua runs — and the failure would be `attempt to index a nil
  value` on the first query, which points at the database rather than at scope.

  So the value is fetched here, once, into a global, and the files below read it.
  A global is the correct choice precisely because it must cross chunk boundaries.
  It is namespaced under `Nifty` so it cannot collide with another resource's Lua
  state — each resource has its own state, which is also why this has to be
  repeated per resource rather than done once anywhere.
]]

Nifty = Nifty or {}

--- Nil, not an error, when the base is not up. `dependencies` in fxmanifest orders
--- the start, but a base that fails still leaves the system running against nil,
--- and a loud error here beats a nil-index ten lines deeper.
if not IsDuplicityVersion() then return end
Nifty.core = exports['nifty-core']:facade()

if not Nifty.core then
  return
end

Nifty.Db = Nifty.core.Db
Nifty.GetSetting = Nifty.core.GetSetting
Nifty.Identity = Nifty.core.Identity

--- SessionGuard too. It looked like base plumbing, but three systems register teardown with it
--- (economy stops the Stuetze, jobs settles wages, world clears bootstrap state), and a
--- global that only the base could see would leave all three silently nil.
Nifty.SessionGuard = Nifty.core.SessionGuard