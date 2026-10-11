--[[
  Dropped-item pickup.

  Companion to nifty:server:discardItemOnGround (which lives in sv_owned.lua
  alongside the rest of the inventory events for clothing). This file
  owns the server-side bookkeeping that lets a nearby player pick the
  drop back up: a `droppedItems` table keyed by network id, a proximity
  gate on pickup, an event to broadcast spawns and despawns to every
  client, and cleanup on resource stop.
]]

local RESOURCE = GetCurrentResourceName()

-- One row per active drop. Indexed by NetworkGetNetworkIdFromEntity.
-- Lookup is exact; a stale network id (entity already removed) returns
-- nil and the pickup short-circuits to a refusal.
local droppedItems = {}

local PROP_HASH = `hei_prop_carrier_bag_02a`

-- ---------------------------------------------------------------------------
-- Spawn: nifty-inventory fires `drops:create` server-side once it has
-- removed the inventory row and validated the player's coords. We spawn
-- the world prop, broadcast it to clients, and schedule a despawn timer.
-- ---------------------------------------------------------------------------

local DISCARD_LIFETIME_MS = 5 * 60 * 1000  -- 5 minutes

-- nifty-inventory's discardItemOnGround handler validates proximity +
-- inventory ownership + removes the row, then fires `drops:create` with
-- the surviving metadata. Server-side TriggerEvent reaches this listener
-- even though it lives in another resource: FiveM dispatch is process-wide.
AddEventHandler('drops:create', function(src, payload)
  Drops.create(src, payload)
end)

Drops = Drops or {}
function Drops.create(src, payload)
  if type(payload) ~= 'table' then return end

  -- The discard handler has already validated proximity and the inventory
  -- row; this function trusts those checks and only handles the spawn side.
  local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
  if not x or not y or not z then return end

  local cid = Nifty.Identity.getActiveCharacter(src)
  if not cid then return end

  local ent = CreateObject(PROP_HASH, x, y, z, true, false, false)
  if not ent or ent == 0 then return end

  SetEntityAsMissionEntity(ent, true, true)
  PlaceObjectOnGroundProperly(ent)

  local netId = NetworkGetNetworkIdFromEntity(ent)
  droppedItems[netId] = {
    -- The character_id that was holding the row before discard. Used only
    -- for ownership sanity on pickup; the recipient on pickup is the
    -- current character's inventory, which can be ANY player (the drop
    -- is global).
    original    = cid,
    code        = payload.code,
    quantity    = math.max(1, tonumber(payload.quantity) or 1),
    sourceId    = payload.itemId,
    name        = payload.name or tostring(payload.code),
    createdAt   = os.time(),
    -- Network id of the prop on this server. Same value on every other
    -- server-context. The client's NetworkGetEntityFromNetworkId
    -- returns the local entity handle.
    networkId   = netId,
    entityHandle = ent,
  }

  -- Tell every client a new drop exists so they can show proximity
  -- prompts. We pass name + code rather than the full row so the wire
  -- stays small.
  TriggerClientEvent('nifty:client:groundItemSpawned', -1, {
    networkId = netId,
    code      = payload.code,
    name      = payload.name or tostring(payload.code),
    x         = x, y = y, z = z,
  })

  -- Despawn timer. 5 minutes is enough that a player walking back to
  -- where they dropped finds the prop, short enough that the map does
  -- not accumulate litter after a busy session. The same timer exists
  -- in the discardItem handler; one of the two will fire, the other
  -- sees `droppedItems[netId] == nil` and exits.
  SetTimeout(function()
    local entry = droppedItems[netId]
    if not entry then return end
    droppedItems[netId] = nil
    TriggerClientEvent('nifty:client:groundItemDespawned', -1, { networkId = netId })
    if DoesEntityExist(entry.entityHandle) then
      DeleteEntity(entry.entityHandle)
    end
  end, DISCARD_LIFETIME_MS, 'drops:cleanup')
end

-- ---------------------------------------------------------------------------
-- Pickup: a player close enough to a drop claims the row back into their
-- inventory. Proximity is server-checked again so a hostile client cannot
-- fabricate events.
-- ---------------------------------------------------------------------------

local PICKUP_RADIUS = 4.0

RegisterNetEvent('nifty:server:pickupGroundItem', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  local netId = tonumber(payload.networkId)
  if not netId then return end

  local cid = Nifty.Identity.getActiveCharacter(src)
  if not cid then return end

  local drop = droppedItems[netId]
  if not drop then
    TriggerClientEvent('nifty:client:pickupGroundItem', src,
                       { ok = false, reason = 'gone' })
    return
  end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return end
  local ent = NetworkGetEntityFromNetworkId(netId)
  if not ent or not DoesEntityExist(ent) then
    droppedItems[netId] = nil
    TriggerClientEvent('nifty:client:groundItemDespawned', -1, { networkId = netId })
    return
  end

  local ePos = GetEntityCoords(ent)
  local pPos = GetEntityCoords(ped)
  local dx, dy, dz = ePos.x - pPos.x, ePos.y - pPos.y, ePos.z - pPos.z
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist > PICKUP_RADIUS then
    TriggerClientEvent('nifty:client:pickupGroundItem', src,
                       { ok = false, reason = 'too far' })
    return
  end

  -- Capacity preflight on the recipient.
  local Inventory = exports['nifty-inventory']
  local def = Inventory.getDefinition(drop.code)
  if not def then
    TriggerClientEvent('nifty:client:pickupGroundItem', src,
                       { ok = false, reason = 'unknown item' })
    return
  end
  local view = Inventory.view(cid)
  if view.usedWeight + (def.weight * drop.quantity) > view.maxWeight then
    TriggerClientEvent('nifty:client:pickupGroundItem', src,
                       { ok = false, reason = 'too heavy' })
    return
  end
  -- `usedSlots` is the count of distinct stacks, capped by `slotCapacity()`
  -- (an exported function is not strictly required - we let the Inventory
  -- add path reject with its own error if the bag is full).

  -- Place the row in the recipient's inventory. The dropped row did
  -- not carry a giver_name in V1 (drops are anonymous); the wardrobe
  -- render will fall through to "no suffix" for picked-up items.
  local ok, err = Inventory.add(cid, drop.code, drop.quantity)
  if not ok then
    TriggerClientEvent('nifty:client:pickupGroundItem', src,
                       { ok = false, reason = err })
    return
  end

  droppedItems[netId] = nil
  TriggerClientEvent('nifty:client:pickupGroundItem', src, { ok = true, code = drop.code })
  TriggerClientEvent('nifty:client:groundItemDespawned', -1, { networkId = netId })
  if DoesEntityExist(ent) then DeleteEntity(ent) end
end)

-- ---------------------------------------------------------------------------
-- Resource stop: clean up any props still on the ground so a restart
-- does not leak entities.
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  for netId, entry in pairs(droppedItems) do
    if entry.entityHandle and DoesEntityExist(entry.entityHandle) then
      DeleteEntity(entry.entityHandle)
    end
  end
  droppedItems = {}
end)

print(('[%s] drops tracked'):format(RESOURCE))
