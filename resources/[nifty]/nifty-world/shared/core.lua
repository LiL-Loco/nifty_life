--[[
  The bridge to nifty-core, loaded before every file in this resource.

  Why this file exists at all, since `exports['nifty-core']:facade()` is one line:

  A `local` in fxmanifest does NOT reach the files loaded after it. Every
  `server_script` chunk is compiled and run in its OWN scope, so a local written in
  fxmanifest is gone by the time the next file runs — and the failure shows up as a
  nil index deep inside the business logic, pointing at the database rather than
  at scope.

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

--- SessionGuard too. It looked like base plumbing, but three systems register teardown with it
--- (economy stops the Stuetze, jobs settles wages, world clears bootstrap state), and a
--- global that only the base could see would leave all three silently nil.
Nifty.SessionGuard = Nifty.core.SessionGuard

--- Economy, Stuetze and Jobs (the absorbed resources' globals) are exposed
--- through the same facade as Db/Identity/etc. so server-side consumers can
--- use `Nifty.Economy:round(...)` etc. without round-tripping through exports
--- per call.
Nifty.Economy = Nifty.core.Economy
Nifty.Stuetze = Nifty.core.Stuetze
Nifty.Jobs    = Nifty.core.Jobs

-- Owned follows the same pattern. The finishAppearance hook in sv_main.lua
-- grants per-piece ownership after a creator save.
Nifty.Owned    = Nifty.core.Owned

-- Price is the per-(drawable, texture) clothing pricebook. Same chain as
-- Owned: Db-backed in nifty-core, exposed through the facade.
Nifty.Price    = Nifty.core.Price