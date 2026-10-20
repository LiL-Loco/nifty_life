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

  HOW THE FIELDS ARE CALLED, AND WHY IT MATTERS
  ------------------------------------------------
  Every field in here is a PLAIN LUA TABLE, and its functions are defined with a
  DOT: `function Economy.get(characterId)`. So a consumer calls them with a DOT:
  `Economy.get(characterId)`.

  The DOPPELPUNKT form compiles, runs, and silently does the wrong thing. FiveM
  consumes an implicit first argument on an export call, and Lua's `:` syntax
  passes the table itself as that argument. Measured on this codebase's own
  functions:

      Economy.round(12.345)  ->  12.35
      Economy:round(12.345)  ->  error: attempt to compare number with table
      Economy.debit('c1','cash',100)  ->  characterId=c1 account=cash delta=100
      Economy:debit('c1','cash',100)  ->  characterId=table account=c1 delta=cash

  The second pair is the dangerous one: it does not throw. The table lands in
  `characterId`, the character id lands in `account`, and the ACCOUNT NAME lands
  in `delta`. A purchase would look up a wallet for a table, find nothing, and
  either fail or charge the wrong number — and 31 call sites across six
  resources were written that way.

  A facade field is data, not an exports proxy. `:` is only right for something
  reached through `exports[...]`, where FiveM inserts the implicit argument
  itself. Inside a plain table it is always wrong.
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
    Economy = Economy,
    -- Jobs was MISSING here, and nifty-world's shared/core.lua asks for it by
    -- name and errors out when it is nil. The symptom was invisible: the world
    -- resource started, and the jobs surface underneath it — the job list, the
    -- duty toggle, the wage payout — was simply never reachable. A field
    -- missing from the facade is not a crash, it is a feature that quietly does
    -- not exist.
    Jobs = Jobs,
    Stuetze = Stuetze,
    Owned = Owned,
    Price = Price,
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