--- Client identity (ADR-0014 layer 3).
---
--- Two jobs:
---   1. Apply a stored appearance to the player ped using COLLECTION natives
---      (ADR-0017). Not global indexes — those shift every Title Update.
---   2. Tell the server we are ready, and handle the two answers: we have a
---      character, or we need to make one.
---
--- This side is an input surface, not a source of truth. The server re-validates
--- every appearance before storing it.

local waitingForWorld = false

--- The appearance the ped is currently wearing, as collection-based data.
---
--- Tracked in Lua rather than read back from the ped. Reading it back would
--- mean re-deriving drawable state through the collection natives, and the
--- texture index in particular is awkward to recover. Tracking what we set is
--- exact, because the only thing that changes a ped's appearance is this file
--- (and, later, the creator, which calls applyAppearance too).
local currentAppearance = nil

--- Apply a saved appearance to a ped.
--- Components and props are set per slot; anything the stored data omits is left
--- at the model's default, which is why a partially specified appearance still
--- produces a valid ped.
local function applyAppearance(ped, appearance)
  if not appearance then return end

  if appearance.model then
    local model = joaat(appearance.model)
    SetPlayerModel(PlayerId(), model)
    SetModelAsNoLongerNeeded(model)
    -- Changing the model resets the ped, so the handle has to be re-fetched.
    ped = PlayerPedId()
  end

  -- Preload first: swapping an unloaded drawable streams it in and hitches the
  -- frame. Preloading keeps the transition smooth (ADR-0017).
  if type(appearance.components) == 'table' then
    for id, slot in pairs(appearance.components) do
      SetPedCollectionPreloadVariationData(ped, tonumber(id),
        slot.collection, slot.drawable, slot.texture, 0)
    end
  end
  if type(appearance.props) == 'table' then
    for id, slot in pairs(appearance.props) do
      SetPedCollectionPreloadPropData(ped, tonumber(id),
        slot.collection, slot.drawable, slot.texture, true)
    end
  end

  if type(appearance.components) == 'table' then
    for id, slot in pairs(appearance.components) do
      SetPedCollectionComponentVariation(ped, tonumber(id),
        slot.collection, slot.drawable, slot.texture, 0)
    end
  end
  if type(appearance.props) == 'table' then
    for id, slot in pairs(appearance.props) do
      SetPedCollectionPropIndex(ped, tonumber(id),
        slot.collection, slot.drawable, slot.texture, false)
    end
  end

  currentAppearance = appearance
  return ped
end

--- Hand the ped to the player and drop them into the world.
RegisterNetEvent('nifty:client:enterWorld', function(data)
  waitingForWorld = false

  local ped = PlayerPedId()
  SetEntityCoords(ped, data.spawn.x, data.spawn.y, data.spawn.z, false, false, false, false)
  SetEntityHeading(ped, data.spawn.heading or 0.0)

  applyAppearance(ped, data.character.appearance)

  -- The player is held frozen until their character exists, so nobody walks
  -- around the city mid-creation.
  FreezeEntityPosition(ped, false)
  SetEntityVisible(ped, true)

  print(('[nifty-core] entered world as %s %s'):format(
    data.character.firstName, data.character.lastName or ''))

  -- Ask for money, items, jobs and the shop once the ped is real. The server
  -- already pushed these in enterWorld (server side); this is the client's own
  -- confirmation, and it covers the case where the push arrived before the HUD
  -- existed to receive it.
  TriggerEvent('nifty:client:worldReady')
end)

RegisterNetEvent('nifty:client:needsCharacter', function()
  -- Open the creator. Until the player has a character they stay frozen and
  -- hidden at the creation point rather than walking around the city as an
  -- unowned ped.
  local ped = PlayerPedId()
  FreezeEntityPosition(ped, true)
  SetEntityVisible(ped, false)

  exports['nifty-core']:openCreator()
end)

RegisterNetEvent('nifty:client:creatorError', function(message)
  print(('[nifty-core] creator refused: %s'):format(tostring(message)))
end)

--- Persist on the way out, opportunistically. ADR-0004: nothing is lost across a
--- restart.
---
--- This is a fast path, not the mechanism. Under OneSync big mode a player who
--- disconnects outside server range may never see this handler run, so the
--- periodic save below is what actually guarantees the appearance survives.
AddEventHandler('playerDisconnected', function()
  if not waitingForWorld then
    TriggerServerEvent('nifty:server:saveCharacter', {
      appearance = exports.nifty_core:getCurrentAppearance(),
    })
  end
end)

--- Periodic save. Everything a player can change about themselves is stored, and
--- none of it is worth losing to an event that is documented not to fire reliably.
local AUTOSAVE_INTERVAL_MS = 60000

CreateThread(function()
  while not NetworkIsSessionStarted() do
    Wait(200)
  end

  while true do
    Wait(AUTOSAVE_INTERVAL_MS)

    -- `waitingForWorld` is false from the moment the player has a character, so
    -- this only starts saving for someone who is actually in the world.
    if not waitingForWorld then
      TriggerServerEvent('nifty:server:saveCharacter', {
        appearance = exports.nifty_core:getCurrentAppearance(),
      })
    end
  end
end)

--- Signal readiness once the client is actually in the world.
CreateThread(function()
  while not NetworkIsSessionStarted() do
    Wait(200)
  end

  -- Give the server a moment to finish deferring our connection.
  Wait(1500)
  TriggerServerEvent('nifty:server:ready')
end)

exports('applyAppearance', applyAppearance)
exports('getCurrentAppearance', function()
  return currentAppearance
end)