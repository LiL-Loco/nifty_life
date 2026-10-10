--- The ownership primitive (ADR-0013).
---
--- Properties and vehicles are different things — one is a place with an
--- interior, the other a mobile instance — but "who owns this, and may they sell
--- it" is the same question with the same answer. So it lives here once.
---
--- The rule that makes it worth isolating: ownership is a **row**, never a field
--- on the thing. A property does not have an `owner_id` column that can be
--- half-written; it has an absence or a presence in `property_owners`. There is
--- no state in which a property belongs to someone and to nobody.
---
--- Acquisition is deliberately unconstrained: ADR-0013 makes housing free to
--- obtain, with the tier governing rent and upkeep. Nobody is locked out, so the
--- sink is recurring cost rather than an entry price. Changing that later is a
--- change to `acquire`, not to every call site.

local RESOURCE = GetCurrentResourceName()

Ownership = {}

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

--- Every property, with its owner. The catalogue is static config; ownership is
--- per-character state, so the join is the honest shape of the answer.
function Ownership.listProperties(kind)
  local rows = Db.all([[
    SELECT p.id, p.code, p.name, p.district, p.tier, p.kind, p.is_active,
           p.entrance_x, p.entrance_y, p.entrance_z,
           o.character_id AS owner_id
      FROM properties p
      LEFT JOIN property_owners o ON o.property_id = p.id
     WHERE p.is_active = 1 AND (? IS NULL OR p.kind = ?)
     ORDER BY p.district, p.name
  ]], { kind, kind }, 'ownership:listProperties')

  local result = {}

  for _, row in ipairs(rows) do
    result[#result + 1] = {
      id = row.id,
      code = row.code,
      name = row.name,
      district = row.district,
      tier = row.tier,
      kind = row.kind,
      owned = row.owner_id ~= nil,
      ownerId = row.owner_id,
      entrance = {
        x = row.entrance_x, y = row.entrance_y, z = row.entrance_z,
      },
    }
  end

  return result
end

function Ownership.getProperty(propertyId)
  local row = Db.one([[
    SELECT p.*, o.character_id AS owner_id
      FROM properties p
      LEFT JOIN property_owners o ON o.property_id = p.id
     WHERE p.id = ? AND p.is_active = 1
  ]], { propertyId }, 'ownership:getProperty')

  if not row then return nil end

  return {
    id = row.id,
    code = row.code,
    name = row.name,
    kind = row.kind,
    district = row.district,
    tier = row.tier,
    interiorIpl = row.interior_ipl,
    storageSlots = tonumber(row.storage_slots) or 0,
    rentAmount = Db.money.toNumber(row.rent_amount),
    upkeepAmount = Db.money.toNumber(row.upkeep_amount),
    ownerId = row.owner_id,
  }
end

--- Does this character own this property? The single authorisation check every
--- property action goes through — doors, storage, sale, rent. Nothing else may
--- answer this question.
function Ownership.owns(characterId, propertyId)
  local row = Db.one([[
    SELECT 1 AS owned FROM property_owners WHERE property_id = ? AND character_id = ?
  ]], { propertyId, characterId }, 'ownership:owns')

  return row ~= nil
end

--- Take ownership. Refuses if anyone already holds it — the UNIQUE key on
--- `property_owners.property_id` is the real guard, and this pre-check only
--- exists to return a sentence instead of a constraint name.
function Ownership.acquireProperty(characterId, propertyId)
  if Ownership.owns(characterId, propertyId) then return false, 'already yours' end

  local existing = Db.one([[
    SELECT character_id FROM property_owners WHERE property_id = ?
  ]], { propertyId }, 'ownership:propertyTaken')

  if existing then return false, 'someone else owns it' end

  local property = Ownership.getProperty(propertyId)
  if not property then return false, 'unknown property' end

  -- Housing is free to obtain (ADR-0013); businesses are bought. Splitting this
  -- by kind keeps "no entry price" a housing decision rather than a global one.
  if property.kind == 'business' then
    local price = Economy.round(GetSetting('economy.price.property_' .. property.tier, 0))
    if price > 0 then
      local ok, err = Economy.debit(characterId, 'bank', price, 'property_purchase', 'property', propertyId)
      if not ok then return false, err end
    end
  end

  local ok = Db.insert([[
    INSERT INTO property_owners (property_id, character_id) VALUES (?, ?)
  ]], { propertyId, characterId }, 'ownership:acquire')

  if ok == nil then return false, 'could not take ownership' end

  print(('[%s] %s acquired %s'):format(RESOURCE, characterId, property.code))
  return true, nil
end

--- Give it up. Returns the character it went to, so the caller can credit them —
--- there is no automatic resale, because deciding a price is a player action and
--- automating it would collapse the housing market into a formula.
function Ownership.releaseProperty(characterId, propertyId, toCharacterId)
  if not Ownership.owns(characterId, propertyId) then return nil, 'not yours' end

  local affected = Db.update([[
    DELETE FROM property_owners WHERE property_id = ? AND character_id = ?
  ]], { propertyId, characterId }, 'ownership:release')

  if affected == nil or affected == 0 then return nil, 'release failed' end

  if toCharacterId then
    if Ownership.owns(toCharacterId, propertyId) then return nil, 'recipient already owns it' end
    Db.insert([[INSERT INTO property_owners (property_id, character_id) VALUES (?, ?)]],
      { propertyId, toCharacterId }, 'ownership:transfer')
  end

  return toCharacterId or 'unowned', nil
end

-- ---------------------------------------------------------------------------
-- Vehicles
-- ---------------------------------------------------------------------------

--- Vehicles follow the same ownership semantics but keep their own table: a
--- vehicle has a position that changes, and putting a mutable coordinate on a
--- row in `properties` would be a category error that only shows up six months in.
function Ownership.listVehicles(characterId)
  local rows = Db.all([[
    SELECT id, model, plate, x, y, z, heading, fuel, engine_health, body_health, is_stored
      FROM vehicles WHERE owner_id = ? ORDER BY created_at
  ]], { characterId }, 'ownership:listVehicles')

  local result = {}

  for _, row in ipairs(rows) do
    result[#result + 1] = {
      id = row.id,
      model = row.model,
      plate = row.plate,
      x = row.x, y = row.y, z = row.z, heading = row.heading,
      fuel = Db.money.toNumber(row.fuel),
      engineHealth = Db.money.toNumber(row.engine_health),
      bodyHealth = Db.money.toNumber(row.body_health),
      stored = row.is_stored == 1,
    }
  end

  return result
end

function Ownership.ownsVehicle(characterId, vehicleId)
  local row = Db.one([[
    SELECT 1 AS owned FROM vehicles WHERE id = ? AND owner_id = ?
  ]], { vehicleId, characterId }, 'ownership:ownsVehicle')

  return row ~= nil
end

--- Persist a vehicle's world state. Called on a timer and on disconnect — a
--- vehicle only exists in the database between those calls, which is exactly
--- ADR-0004's "nothing is lost" wearing an efficiency hat.
function Ownership.saveVehicle(vehicleId, state)
  if not vehicleId or type(state) ~= 'table' then return false end

  local affected = Db.update([[
    UPDATE vehicles
       SET x = ?, y = ?, z = ?, heading = ?, fuel = ?, is_stored = ?
     WHERE id = ?
  ]], {
    tonumber(state.x) or 0, tonumber(state.y) or 0, tonumber(state.z) or 0,
    tonumber(state.heading) or 0, tostring(Economy.round(state.fuel)),
    state.stored and 1 or 0, vehicleId,
  }, 'ownership:saveVehicle')

  return affected ~= nil
end

exports('ownsProperty', Ownership.owns)
exports('listProperties', Ownership.listProperties)
exports('listVehicles', Ownership.listVehicles)