--[[
  The player's action surface.

  Every event here follows the same three rules, and they are the reason this
  file exists at all:

    1. The character comes from the SESSION, never from the event payload.
       A client that sends `{ characterId = 'someone-else' }` is ignored, because
       nothing in this file reads a character ID from a client.
    2. No event takes a price, a quantity that matters economically, or a
       permission from a client. Codes and slot numbers yes ÔÇö they are looked
       up and checked. Numbers that move money never.
    3. Every handler answers with `nifty:client:result`, so the UI can say
       something honest instead of silently doing nothing.

  Rate limiting is per-slot and in memory. It exists to stop an event being
  spammed into a transaction storm, not to enforce a design ÔÇö a well-behaved
  client never trips it.
]]

local RESOURCE = GetCurrentResourceName()
--- From the base facade, fetched by shared/core.lua at load. These were globals
--- when this file lived inside nifty-core; see the note in shared/core.lua about
--- why a local in fxmanifest would not have survived the chunk boundary.
local Identity = Nifty.Identity
local SessionGuard = Nifty.SessionGuard

--- The systems this action surface drives.
---
--- These were globals when everything lived in one resource. They are now the
--- owning resources themselves, reached by export — the resource object IS the
--- public interface, which is why every system keeps exporting what a PLAYER can
--- do, not only what its own internals happen to use.
local Economy   = Nifty.Economy
local Inventory = exports['nifty-inventory']
local Jobs      = Nifty.Jobs
local Shop      = exports['nifty-shop']
local Ownership = exports['nifty-housing']

--- Actions allowed per window. A shop purchase opens a transaction and writes
--- two rows; a client spamming it 60 times a second is a denial of service
--- against the database, not against itself.
local RATE_LIMIT = 12
local RATE_WINDOW_MS = 1000

local ActionLog = {}

--- @return boolean allowed, string|nil message
local function allowAction(src)
  local now = GetGameTimer()
  local entry = ActionLog[src]

  if not entry or now - entry.start > RATE_WINDOW_MS then
    ActionLog[src] = { start = now, count = 1 }
    return true, nil
  end

  entry.count = entry.count + 1
  if entry.count > RATE_LIMIT then
    return false, 'too fast'
  end

  return true, nil
end

--- The character's id, or nil if this connection has no session. Every handler
--- starts here; there is no other way into the systems below.
local function sessionCharacter(src)
  return Identity.getActiveCharacter(src)
end

--- Tell the client what happened, then push whatever the action changed. The
--- push is not conditional on success: a refused purchase still changes nothing,
--- but a player whose balance is stale because an action failed is worse off than
--- one that is merely told "no".
local function respond(src, ok, message)
  TriggerClientEvent('nifty:client:result', src, { ok = ok, message = message })

  local characterId = sessionCharacter(src)
  if not characterId then return end

  Economy.push(src, characterId)
  Inventory:push(src, characterId)
  Jobs.sync(characterId, src)
end

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

--- One request for everything the HUD needs. Sending three separate pushes on
--- entry means the HUD renders three times and can show money without a job or a
--- job without money.
RegisterNetEvent('nifty:server:requestState', function()
  local src = source
  local characterId = sessionCharacter(src)
  if not characterId then return end

  TriggerClientEvent('nifty:client:economy', src, Economy.get(characterId))
  TriggerClientEvent('nifty:client:inventory', src, Inventory:view(characterId))
  TriggerClientEvent('nifty:client:jobs', src, Jobs.listFor(characterId))
  TriggerClientEvent('nifty:client:jobCatalogue', src, Jobs.list())
  TriggerClientEvent('nifty:client:shop', src, Shop:catalogue())
end)

-- ---------------------------------------------------------------------------
-- Jobs
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:jobJoin', function(code)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(code) ~= 'string' then return respond(src, false, 'bad request') end

  local ok, err = Jobs.join(characterId, code)
  respond(src, ok, err)
end)

RegisterNetEvent('nifty:server:jobLeave', function(code)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(code) ~= 'string' then return respond(src, false, 'bad request') end

  local ok, err = Jobs.leave(characterId, code)
  respond(src, ok, err)
end)

RegisterNetEvent('nifty:server:dutyStart', function(code)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(code) ~= 'string' then return respond(src, false, 'bad request') end

  local ok, err = Jobs.startDuty(characterId, code)
  respond(src, ok, err)
end)

RegisterNetEvent('nifty:server:dutyEnd', function(code)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(code) ~= 'string' then return respond(src, false, 'bad request') end

  -- Pays out. The response carries the earnings so the player sees the number
  -- that landed rather than having to infer it from a balance change.
  local ok, seconds, payout = Jobs.endDuty(characterId, code)
  if not ok then return respond(src, false, seconds) end

  TriggerClientEvent('nifty:client:result', src, {
    ok = true,
    message = ('Schicht beendet: %d Minuten, %s verdient.'):format(
      math.floor((seconds or 0) / 60), tostring(payout or 0)),
  })

  local refreshed = sessionCharacter(src)
  if refreshed then
    Economy.push(src, refreshed)
    Inventory:push(src, refreshed)
    Jobs.sync(refreshed, src)
  end
end)

-- ---------------------------------------------------------------------------
-- Shop
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:buy', function(code, quantity)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(code) ~= 'string' then return respond(src, false, 'bad request') end

  -- Quantity is bounded inside Shop:buy as well as here. The client value is a
  -- convenience, never an authorisation.
  local ok, err = Shop:buy(characterId, code, quantity)
  respond(src, ok, err)
end)

RegisterNetEvent('nifty:server:sell', function(code, quantity)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(code) ~= 'string' then return respond(src, false, 'bad request') end

  local ok, err = Shop:sell(characterId, code, quantity)
  respond(src, ok, err)
end)

RegisterNetEvent('nifty:server:deposit', function(amount)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  local ok, err = Shop:deposit(characterId, amount)
  respond(src, ok, err)
end)

RegisterNetEvent('nifty:server:withdraw', function(amount)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  local ok, err = Shop:withdraw(characterId, amount)
  respond(src, ok, err)
end)

-- ---------------------------------------------------------------------------
-- Inventory
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:moveItem', function(fromSlot, toSlot)
  local src = source
  local characterId = sessionCharacter(src)
  if not characterId then return end

  local ok, err = Inventory:move(characterId, fromSlot, toSlot)
  if not ok then return end

  Inventory:push(src, characterId)
end)

RegisterNetEvent('nifty:server:useItem', function(code, quantity)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(code) ~= 'string' then return respond(src, false, 'bad request') end

  local ok, err = Inventory:use(characterId, code, quantity or 1)
  respond(src, ok, err)
end)

-- ---------------------------------------------------------------------------
-- Ownership
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:properties', function()
  local src = source
  local characterId = sessionCharacter(src)
  if not characterId then return end

  TriggerClientEvent('nifty:client:properties', src, Ownership:listProperties(nil))
end)

RegisterNetEvent('nifty:server:acquireProperty', function(propertyId)
  local src = source
  local allowed, tooFast = allowAction(src)
  if not allowed then return respond(src, false, tooFast) end

  local characterId = sessionCharacter(src)
  if not characterId then return end

  if type(propertyId) ~= 'string' then return respond(src, false, 'bad request') end

  local ok, err = Ownership:acquireProperty(characterId, propertyId)
  if ok then
    TriggerClientEvent('nifty:client:properties', src, Ownership:listProperties(nil))
  end
  respond(src, ok, err)
end)

RegisterNetEvent('nifty:server:myVehicles', function()
  local src = source
  local characterId = sessionCharacter(src)
  if not characterId then return end

  TriggerClientEvent('nifty:client:vehicles', src, Ownership:listVehicles(characterId))
end)

-- ---------------------------------------------------------------------------

-- An in-memory table that is never cleaned leaks one entry per drop. Under
-- OneSync big mode a distant disconnect delivers no `playerDropped`, so it
-- leaks silently rather than visibly.
SessionGuard.onStop('actionLog', function(src)
  ActionLog[src] = nil
end)