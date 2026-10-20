--[[
  The bridge to nifty-core, loaded before every file in this resource.

  Why this file exists at all, since `exports['nifty-core']:facade()` is one line:

  A `local` in fxmanifest does NOT reach the files loaded after it. Every script
  chunk is compiled and run in its OWN scope, so a local written in fxmanifest is
  gone by the time the next file runs — and the failure shows up as a nil index
  deep inside the business logic, pointing at the database rather than at scope.

  So the value is fetched here, once, into a global, and the files below read it.
  A global is the correct choice precisely because it must cross chunk boundaries.
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
Nifty.SessionGuard = Nifty.core.SessionGuard
Nifty.Validate = Nifty.core.Validate
Nifty.Economy = Nifty.core.Economy

--- nifty-inventory is a separate resource and exposes its interface through
--- exports, not through nifty-core's facade — so it is fetched the same way, and
--- the absence is handled rather than assumed. ADR-0018 makes the inventory a
--- hard dependency: a phone is a device, and a device exists only if something is
--- carrying it.
Nifty.Inventory = exports['nifty-inventory']