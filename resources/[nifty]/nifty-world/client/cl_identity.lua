--- Client identity (ADR-0014 layer 3).
---
--- Two jobs:
---   1. Apply a stored appearance to the player ped using COLLECTION natives
---      (ADR-0017). Not global indexes — those shift every Title Update.
---   2. Tell the server we are ready, and handle the two answers: the character
---      is finished, or it exists without an appearance and the creator has to
---      run first.
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

--- The head-overlay natives, resolved ONCE at load.
---
--- Cfx registers several of these under an underscored name in the Lua runtime
--- (`_SetPedHeadOverlayColor`, `_SetPedHairColor`, `_GetNumHairColors`,
--- `_ClearPedFacialDecorations`) and the plain name in others. Which is which
--- varies by build, and there is no documentation that states it. Reading an
--- undefined global in Lua yields nil rather than raising, so this is a probe and
--- not a try/catch - and the result is logged, because "the beard did not change"
--- and "the native does not exist" must not look the same from the outside.
local Natives = {
  setFaceFeature     = SetPedFaceFeature,
  setHeadOverlay     = SetPedHeadOverlay,
  numHeadOverlayValues = GetNumHeadOverlayValues,
  setHeadOverlayColor = _SetPedHeadOverlayColor or SetPedHeadOverlayColor,
  setHairColor       = _SetPedHairColor or SetPedHairColor,
  numHairColors      = _GetNumHairColors or GetNumHairColors,
  numMakeupColors    = _GetNumMakeupColors or GetNumMakeupColors,
  setFacialDecoration = _SetPedFacialDecoration or SetPedFacialDecoration,
  clearFacialDecorations = _ClearPedFacialDecorations or ClearPedFacialDecorations,
  clearPedDecorations = RemovePedDecorations,
  numTattooShopDlcItems = GetNumTattooShopDlcItems,
  tattooCollectionData = GetTattooCollectionData,
  hashNameForComponent = GetHashNameForComponent,
  forcedComponentCount = GetShopPedApparelForcedComponentCount,
  getForcedComponent = GetForcedComponent,
}

--- Which face natives this client actually has. Logged once, because the failure
--- mode without it is silent: the menu offers a beard, the slider moves, nothing
--- appears, and there is nothing anywhere to look.
CreateThread(function()
  local missing = {}
  for name, fn in pairs(Natives) do
    if type(fn) ~= 'function' then missing[#missing + 1] = name end
  end
  if #missing > 0 then
    print(('[nifty-world] face natives missing: %s'):format(table.concat(missing, ', ')))
  end
end)

--- The part of an appearance that does NOT include changing the ped model.
---
--- Split out because the creator needs to re-apply face, overlays and colour while
--- the player is still choosing, and calling the full `applyAppearance` for that
--- would run `SetPlayerModel` on every slider nudge - which resets the ped and would
--- throw away the clothing the player just picked, roughly forty times a second.
local function applyFace(ped, appearance)
  if type(appearance.faceFeatures) == 'table' and Natives.setFaceFeature then
    for id, value in pairs(appearance.faceFeatures) do
      Natives.setFaceFeature(ped, tonumber(id), value)
    end
  end

  if type(appearance.overlays) == 'table' then
    for id, overlay in pairs(appearance.overlays) do
      local index = tonumber(id)
      if index then
        if Natives.setHeadOverlay then
          Natives.setHeadOverlay(ped, index, overlay.style, overlay.opacity)
        end
        if Natives.setHeadOverlayColor then
          Natives.setHeadOverlayColor(ped, index,
            overlay.colourType or 1, overlay.colour or 0, overlay.secondColour or 0)
        end
      end
    end
  end

  -- AFTER the components: hair colour is bound to the hair drawable, so applying
  -- it to the previous hairstyle and then changing the hair loses the colour.
  if appearance.hairColour and Natives.setHairColor then
    Natives.setHairColor(ped, appearance.hairColour.primary or 0, appearance.hairColour.highlight or 0)
  end
end

--- Apply everything EXCEPT the model.
local function applyAppearanceParts(ped, appearance)
  if not appearance then return ped end

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

  applyFace(ped, appearance)

  return ped
end

--- Apply a saved appearance to a ped, model included.
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

  ped = applyAppearanceParts(ped, appearance)

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

  print(('[nifty-world] entered world as %s %s'):format(
    data.character.firstName, data.character.lastName or ''))

  -- Ask for money, items, jobs and the shop once the ped is real. The server
  -- already pushed these in enterWorld (server side); this is the client's own
  -- confirmation, and it covers the case where the push arrived before the HUD
  -- existed to receive it.
  TriggerEvent('nifty:client:worldReady')
end)

RegisterNetEvent('nifty:client:openCreator', function(data)
  -- The character row already exists; this is the second half of making it
  -- playable. Held frozen and invisible so nobody walks around the city as an
  -- unowned ped, but VISIBLE - the creator has to show the player their own face
  -- next to the menu it is about to open.
  --
  -- The gender is the server's, not the client's: it comes out of the row the
  -- website wrote, and it is what decides the ped model. Nothing here asks.
  local ped = PlayerPedId()
  FreezeEntityPosition(ped, true)
  SetEntityVisible(ped, true)

  exports['nifty-creator']:openCreator({
    gender = data and data.gender or 'male',
  })
end)

RegisterNetEvent('nifty:client:creatorError', function(message)
  print(('[nifty-world] creator refused: %s'):format(tostring(message)))
end)

local function getCurrentAppearance()
  return currentAppearance
end

--- Persist on the way out, opportunistically. ADR-0004: nothing is lost across a
--- restart.
---
--- This is a fast path, not the mechanism. Under OneSync big mode a player who
--- disconnects outside server range may never see this handler run, so the
--- periodic save below is what actually guarantees the appearance survives.
AddEventHandler('playerDisconnected', function()
  if not waitingForWorld then
    TriggerServerEvent('nifty:server:saveCharacter', {
      appearance = getCurrentAppearance(),
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
        appearance = getCurrentAppearance(),
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
exports('applyAppearanceParts', applyAppearanceParts)
exports('getCurrentAppearance', getCurrentAppearance)

--- The resolved face natives, for the creator to reuse.
---
--- Exported rather than duplicated on purpose: the whole point of resolving the
--- underscored spellings once is that there is one answer to "which name did we
--- get". A second probe in the creator could answer differently from this one and
--- the two halves of the same feature would disagree.
exports('faceNatives', function()
  return Natives
end)