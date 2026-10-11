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
  setHeadBlendData  = SetPedHeadBlendData,
  setEyeColor       = _SetPedEyeColor or SetPedEyeColor,
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
--- Facial decorations: the hair overlay and the tattoos.
---
--- THEY SHARE ONE CHANNEL, and that is the whole reason this is one function
--- rather than two. `ClearPedDecorations` removes ALL decorations - hair overlay,
--- tattoos, everything - and `SetPedFacialDecoration` adds one without touching
--- the others. So applying a second tattoo without clearing would stack it on top
--- of the first, and clearing on every change would erase the hair overlay the
--- player has been wearing since they picked a hairstyle.
---
--- Therefore: clear ONCE, then add everything, every time. There is no partial
--- update and there cannot be one.
---
--- The hair overlay arrives already resolved - collection and preset, both hashes -
--- because resolving it needs natives the world resource has no reason to know
--- about. The creator does that once, when the hairstyle changes.
local function applyDecorations(ped, appearance)
  local n = Natives

  if n.clearPedDecorations then
    n.clearPedDecorations(ped)
  end

  if not n.setFacialDecoration then return end

  if type(appearance.hairOverlay) == 'table'
    and appearance.hairOverlay.collection
    and appearance.hairOverlay.preset
  then
    n.setFacialDecoration(ped, appearance.hairOverlay.collection, appearance.hairOverlay.preset)
  end

  if type(appearance.tattoos) == 'table' then
    for _, tattoo in ipairs(appearance.tattoos) do
      if tattoo.collection and tattoo.preset then
        n.setFacialDecoration(ped, tattoo.collection, tattoo.preset)
      end
    end
  end
end

local function applyFace(ped, appearance)
  -- HEAD BLEND FIRST. It rebuilds the face the overlays are painted onto, so
  -- applying overlays first and the blend afterwards throws them away.
  if appearance.headBlend and Natives.setHeadBlendData then
    local blend = appearance.headBlend

    -- THE CONVERSION. The engine takes three presets but only two shape weights
    -- plus one third blend, and derives the actual proportions itself:
    --
    --   third  = thirdMix
    --   mother = (1 - shapeMix) * (1 - thirdMix)
    --   father =       shapeMix  * (1 - thirdMix)
    --
    -- So a player asking for a, b, c gets them back by choosing thirdMix = c and
    -- shapeMix = b / (a + b) on the NORMALISED weights. Divide all three by one
    -- and the same face comes out - which is why the sliders can be percentages
    -- that do not have to add up to anything.
    --
    -- Three parents at equal strength is reachable this way: 33 / 33 / 33.
    --
    -- This is the ONLY place that conversion exists. The database stores what the
    -- player set; if a second copy of this arithmetic appeared anywhere, the menu
    -- and the ped would drift apart on the first save/load round trip.
    local wm = tonumber(blend.motherWeight) or 0.5
    local wf = tonumber(blend.fatherWeight) or 0.5
    local wc = tonumber(blend.thirdWeight) or 0.0

    local total = wm + wf + wc
    if total <= 0 then
      -- All three at zero is a request with no answer. Falling back to the plain
      -- two-parent average is what the menu would show anyway, and returning
      -- without calling would leave the ped on whatever it had.
      wm, wf, wc, total = 0.5, 0.5, 0.0, 1.0
    end

    local parents = wm + wf
    -- Parents both at zero leaves only the third parent, and shapeMix is then a
    -- division by zero. 0.5 is the neutral middle, and with no parent weight left
    -- it has no effect on the result anyway.
    local shapeMix = (parents > 0) and (wf / parents) or 0.5
    local thirdMix = wc / total

    -- Argument order looks wrong and is not: MOTHER before FATHER, and the two
    -- skin slots mirror the two id slots. The third preset supplies both the third
    -- shape and the third skin tone, because `thirdMix` is shared between them -
    -- the one degree of freedom the native does not give us.
    Natives.setHeadBlendData(ped,
      blend.mother, blend.father, blend.third,
      blend.mother, blend.father, blend.third,
      shapeMix, tonumber(blend.skinTone) or 0.5, thirdMix,
      false)
  end

  if appearance.eyeColour and Natives.setEyeColor then
    Natives.setEyeColor(ped, appearance.eyeColour)
  end

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

  -- Last. The hair overlay sits on the hairstyle and the tattoos on the skin, so
  -- both want the final word about what the ped looks like.
  applyDecorations(ped, appearance)
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

  local appearance = data.character.appearance

  -- Spawn THROUGH the spawn module, not with a bare SetEntityCoords.
  --
  -- Two reasons. The obvious one is that a player who died on a previous life is
  -- still dead here, and moving a corpse does not resurrect it - so this is where
  -- `NetworkResurrectLocalPlayer` has to happen. The subtler one is the model:
  -- the spawn sets it, so the resurrect lands in the right body, and the
  -- appearance then only has to dress that body. Calling the model-setting
  -- `applyAppearance` here as well would reset the ped a second time and throw
  -- away everything the spawn just did.
  exports['nifty-world']:spawnPlayer({
    x = data.spawn.x,
    y = data.spawn.y,
    z = data.spawn.z,
    heading = data.spawn.heading or 0.0,
    model = appearance and appearance.model,
  }, function()
    -- Dressing happens once the spawn's screen fade is in, so the player does not
    -- watch their own clothes assemble while the screen is still black.
    applyAppearanceParts(PlayerPedId(), appearance)
  end)

  -- Autospawn is armed AFTER the spawn, never before. During the creator the
  -- player is standing at the creation point and must stay there; arming it
  -- earlier would let the death monitor move them out from under the menu.
  exports['nifty-world']:setAutoSpawn(true)

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