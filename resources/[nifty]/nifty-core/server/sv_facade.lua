--[[
  The base facade — the ONE coupling point between nifty-core and every system
  resource.

  Before the split, all of this was one resource and these were globals:
  `Db.one(...)`, `GetSetting('shop.sell_rate', 0.2)`, `Identity.getActiveCharacter(src)`.
  Globals do not cross a resource boundary — each resource has its own Lua state,
  so every one of those ~200 call sites had to become something else.

  The obvious replacement is to turn each into an `exports` call. That is what was
  NOT done, and the reason is worth writing down: `exports.nifty_core:dbOne(...)`
  at 200 sites means 200 new names, 200 new places to typo, and a change of the DB
  layer touching every system file. The alternative is one line per system file:

      local Core = exports.nifty_core:facade()
      local Db, GetSetting, Identity = Core.Db, Core.GetSetting, Core.Identity

  The call sites then do not change AT ALL, and the base can be reworked behind
  the facade without a system file noticing. That is the same reason this project
  has `Db.one` instead of raw `MySQL.query.await` at every site: one seam, not many.

  WHAT THIS FASSADE IS NOT: a service bus. It exposes state and data access, not
  behaviour. `Inventory.add` is NOT here — it belongs to nifty-inventory, and a
  system that needs it calls that resource's export. The line is deliberate:
    * in the facade  -> things that are true of every system (identity, settings,
                        the database, UUIDs)
    * in a system    -> things that only that system owns (its own state machine)
  A facade that grew into everything would recreate the monolith with extra steps.

  Returns a table by reference. FiveM passes Lua tables across resource exports
  without copying, so this is one allocation per caller, not one per query.
]]

local RESOURCE = GetCurrentResourceName()

exports('facade', function()
  return {
    Db = Db,
    GetSetting = GetSetting,
    Identity = Identity,
    Nifty = Nifty,
    SessionGuard = SessionGuard,
    Validate = Validate,
  }
end)

--- Cheap liveness probe for a caller that wants to know the base is up before it
--- does real work. Deliberately separate from `facade()`: returning nil here is a
--- legitimate answer, returning a half-built facade is not.
exports('ready', function()
  return Db ~= nil and GetSetting ~= nil
end)

--- Print the base's own summary. Used by the boot check in docs/vertical-slice.md,
--- which asserts on specific lines — keeping the wording in one place stops that
--- assertion from silently drifting away from the code it watches.
exports('health', function()
  local settings = 0
  for _ in pairs(Nifty.Settings) do settings = settings + 1 end

  return {
    resource = RESOURCE,
    settings = settings,
    tables = 'see logs',
  }
end)

print(('[%s] base facade exposed'):format(RESOURCE))