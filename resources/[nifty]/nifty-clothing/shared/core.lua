--[[
  Bridge to nifty-core, loaded before every file in this resource.

  Same shape as nifty-world/shared/core.lua: the facade is fetched once,
  into a global, so server and client files reach `Nifty.Identity` and
  friends without an exports round-trip per call.
]]

Nifty = Nifty or {}

if not IsDuplicityVersion() then return end
Nifty.core = exports['nifty-core']:facade()

if not Nifty.core then return end

Nifty.Db         = Nifty.core.Db
Nifty.Identity   = Nifty.core.Identity
Nifty.Owned      = Nifty.core.Owned
Nifty.Price      = Nifty.core.Price
Nifty.Economy    = Nifty.core.Economy
Nifty.SessionGuard = Nifty.core.SessionGuard
