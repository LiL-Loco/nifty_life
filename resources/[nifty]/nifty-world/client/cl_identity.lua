-- Client identity (ADR-0014 layer 3).
--
-- Two jobs:
--   1. Apply a stored appearance to the player ped using COLLECTION natives
--      (ADR-0017). Not global indexes — those shift every Title Update.
--   2. Tell the server we are ready, and handle the two answers: the character
--      is finished, or it exists without an appearance and the creator has to
--      run first.
--
-- This side is an input surface, not a source of truth. The server re-validates
-- every appearance before storing it.

local waitingForWorld = false

-- The appearance the ped is currently wearing, as collection-based data.
--
-- Tracked in Lua rather than read back from the ped. Reading it back would
-- mean re-deriving drawable state through the collection natives, and the
-- texture index in particular is awkward to recover. Tracking what we set is
-- exact, because the only thing that changes a ped's appearance is this file
-- (and, later, the creator, which calls applyAppearance too).
local currentAppearance = nil

-- The index spawnmanager hands back when we register the character's home
-- as a spawn point. Stored so playerDisconnected can remove it; otherwise
-- entries pile up across reconnects and the map's point list drifts.
local characterSpawnIndex = nil

-- The head-overlay natives, resolved ONCE at load.
--
-- Cfx registers several of these under an underscored name in the Lua runtime
-- (`_SetPedHeadOverlayColor`, `_GetNumHairColors`, `_SetPedEyeColor`) and the
-- plain name in others. Which is which varies by build, and there is no
-- documentation that states it. Reading an undefined global in Lua yields nil
-- rather than raising, so this is a probe and not a try/catch - and the result
-- is logged, because "the beard did not change" and "the native does not
-- exist" must not look the same from the outside.
--
-- FIVE OF THESE NAMES WERE WRONG, and every one of them was wrong in the same
-- way: they were read from memory, and a name that does not exist is nil, and
-- a nil behind a `if n.x then` guard is not an error - it is a feature that
-- quietly does not exist.
--
-- Checked against the runtime's own native list (6416 entries, the same file
-- the documentation is generated from):
--
--   SetPedHeadOverlayNum        YES   (it was GetNumHeadOverlayValues)
--   SetPedHairTint              YES   (there is NO SetPedHairColor at all)
--   AddPedDecorationFromHashes  YES   (there is NO SetPedFacialDecoration)
--   ClearPedDecorations         YES   (there is NO RemovePedDecorations)
--   SetPedHeadOverlayOpacity    NO    - the runtime has no such native. The
--                                         hair overlay's opacity is part of
--                                         the decal, not something that is
--                                         set separately. It is applied at
--                                         full opacity, and the slider that
--                                         pretends otherwise has nothing to
--                                         talk to.
--
-- The consequence of the other four: the hair colour never changed, the head
-- overlay styles were counted as 1, and NEITHER the hair overlay NOR a single
-- tattoo was ever drawn - because the clear and the add were both nil.
local Natives = {
  setHeadBlendData  = SetPedHeadBlendData,
  setEyeColor       = _SetPedEyeColor or SetPedEyeColor,
  setFaceFeature     = SetPedFaceFeature,
  setHeadOverlay     = SetPedHeadOverlay,
  numHeadOverlayValues = GetPedHeadOverlayNum,
  setHeadOverlayColor = _SetPedHeadOverlayColor or SetPedHeadOverlayColor,
  setHeadOverlayOpacity = SetPedHeadOverlayOpacity,
  setHairColor       = SetPedHairTint,
  numHairColors      = _GetNumHairColors or GetNumHairColors,
  numMakeupColors    = _GetNumMakeupColors or GetNumMakeupColors,
  -- The hair overlay and the tattoos are FACIAL DECORATIONS: a decal, added
  -- by its collection and its overlay hash. That is what the hair metadata
  -- carries ("HairTattooCollection", "HairTattooOverlay"), and it is why
  -- `AddPedDecorationFromHashes` is the native and not a "set" of anything.
  addPedDecoration = AddPedDecorationFromHashes,
  clearPedDecorations = ClearPedDecorations,
  -- The variant that leaves the scars behind. The ped wears its tattoos as
  -- scars when they are cleared, and the hair overlay is not one of them.
  clearFacialDecorations = ClearPedDecorationsLeaveScars,
  numTattooShopDlcItems = GetNumTattooShopDlcItems,
  hashNameForComponent = GetHashNameForComponent,
  forcedComponentCount = GetShopPedApparelForcedComponentCount,
  getForcedComponent = GetForcedComponent,
}

-- Which face natives this client actually has. Logged once, because the failure
-- mode without it is silent: the menu offers a beard, the slider moves, nothing
-- appears, and there is nothing anywhere to look.
CreateThread(function()
  local missing = {}
  for name, fn in pairs(Natives) do
    if type(fn) ~= 'function' then missing[#missing + 1] = name end
  end
  if #missing > 0 then
    print(('[nifty-world] face natives missing: %s'):format(table.concat(missing, ', ')))
  end
end)

-- The part of an appearance that does NOT include changing the ped model.
--
-- Split out because the creator needs to re-apply face, overlays and colour while
-- the player is still choosing, and calling the full `applyAppearance` for that
-- would run `SetPlayerModel` on every slider nudge - which resets the ped and would
-- throw away the clothing the player just picked, roughly forty times a second.
-- Facial decorations: the hair overlay and the tattoos.
--
-- THEY SHARE ONE CHANNEL, and that is the whole reason this is one function
-- rather than two. `ClearPedDecorations` removes ALL decorations - hair overlay,
-- tattoos, everything - and `AddPedDecorationFromHashes` adds one without
-- touching the others. So applying a second tattoo without clearing would stack
-- it on top of the first, and clearing on every change would erase the hair
-- overlay the player has been wearing since they picked a hairstyle.
--
-- Therefore: clear ONCE, then add everything, every time. There is no partial
-- update and there cannot be one.
--
-- The hair overlay arrives already resolved - collection and preset, both hashes -
-- because resolving it needs natives the world resource has no reason to know
-- about. The creator does that once, when the hairstyle changes.
local function applyDecorations(ped, appearance)
  local n = Natives

  if n.clearPedDecorations then
    n.clearPedDecorations(ped)
  end

  if not n.addPedDecoration then return end

  if type(appearance.hairOverlay) == 'table'
    and appearance.hairOverlay.collection
    and appearance.hairOverlay.preset
  then
    n.addPedDecoration(ped, appearance.hairOverlay.collection, appearance.hairOverlay.preset)
    -- The opacity of the hair overlay. The runtime has no native for it: the
    -- hair overlay is a DECAL, and a decal's opacity belongs to the decal. So
    -- it is drawn at full opacity, and the slider in the panel has no native to
    -- talk to. The value is still stored - a build that grows the native will
    -- use it.
    if n.setHeadOverlayOpacity then
      local opacity = appearance.hairOverlay.opacity
      if type(opacity) ~= 'number' then opacity = 1.0 end
      n.setHeadOverlayOpacity(ped, 10, opacity)
    end
  end

  if type(appearance.tattoos) == 'table' then
    for _, tattoo in ipairs(appearance.tattoos) do
      if tattoo.collection and tattoo.preset then
        -- The collection is a HASH, because the native wants one. Older
        -- appearances stored the collection NAME, and a name handed to a
        -- native that wants a number is a zero - which is not a crash but a
        -- tattoo that silently does not appear.
        local collection = tattoo.collection
        if type(collection) == 'string' then
          collection = joaat(collection)
        end
        n.addPedDecoration(ped, collection, tattoo.preset)
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

-- The texture a drawable actually accepts is NOT asked for here any more.
--
-- It used to be, and the attempt was a no-op: the two natives it used
-- (`GetNumberOfPedComponentTextures`, `GetNumberOfPedPropTextures`) do not
-- exist - the engine's names are `GetNumberOfPedTextureVariations` and
-- `GetNumberOfPedPropTextureVariations` - and both were called behind a
-- `type(...) == 'function'` guard. The guard did its job perfectly: it
-- swallowed the wrong name, the count came back nil, and the texture was
-- passed through unchanged. The engine kept refusing the slot and kept
-- printing, once per frame:
--
--     CPed::SetVariation: Invalid variation (slotId: 10, drawblId: 9, texId: 1)
--
-- `Variation.apply` does the whole job now: it resolves the collection-local
-- drawable to the global one the engine validates, asks for THAT drawable's
-- texture count, and clamps to it. The result is that the texture a slot gets
-- is one the engine accepts.

-- Apply everything EXCEPT the model.
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
      Variation.apply(ped, 'components', tonumber(id),
        slot.collection, slot.drawable, slot.texture)
    end
  end
  if type(appearance.props) == 'table' then
    for id, slot in pairs(appearance.props) do
      Variation.apply(ped, 'props', tonumber(id),
        slot.collection, slot.drawable, slot.texture)
    end
  end

  -- THE PROPS THE APPEARANCE DOES NOT MENTION ARE CLEARED.
  --
  -- The appearance is the whole truth about what the ped wears. A prop anchor
  -- that the appearance leaves out is not "unchanged", it is "not worn" - and
  -- only the props can say that, because a prop is the one thing on a freemode
  -- ped that has an empty state (`ClearPedProp` removes it, and the game draws
  -- the ped without the hat).
  --
  -- Without this, the creator's randomiser left the previous hat on the ped:
  -- it drops a prop slot from the selection, the apply path only ever SETS
  -- the slots that are in the appearance, and the old hat stayed where it was
  -- while the panel said the slot was empty. The character then spawned
  -- without the hat, because the SAVED appearance did not have it - the ped
  -- in the creator and the character in the world were two different people.
  --
  -- The components cannot be cleared this way and are not cleared: a
  -- freemode ped wears a garment in every component slot (the base
  -- collection's drawable 0 is a "Crew T-Shirt", not an empty state), so
  -- there is no empty state to go back to. The randomiser therefore always
  -- fills the component slots.
  for anchor = AppearanceConfig.MIN_COMPONENT_ID, AppearanceConfig.MAX_COMPONENT_ID do
    if not (type(appearance.props) == 'table'
            and appearance.props[tostring(anchor)]) then
      ClearPedProp(ped, anchor)
    end
  end

  applyFace(ped, appearance)

  return ped
end

-- Apply a saved appearance to a ped, model included.
-- Components and props are set per slot; anything the stored data omits is left
-- at the model's default, which is why a partially specified appearance still
-- produces a valid ped.
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

-- The actual spawn sequence, factored out so enterWorld can call it either
-- from the picker callback (first-time spawn) or directly (resume at the
-- last saved position). The fade hides the model switch; without it the camera
-- sits inside the old ped for a frame.
local function doEnterWorldSpawn(x, y, z, heading, appearance, firstName, lastName)
  DoScreenFadeOut(500)
  while not IsScreenFadedOut() do Wait(0) end

  if appearance and appearance.model then
    local model = joaat(appearance.model)
    SetPlayerModel(PlayerId(), model)
    SetModelAsNoLongerNeeded(model)
  end

  applyAppearanceParts(PlayerPedId(), appearance)

  local ped = PlayerPedId()
  SetEntityCoords(ped, x, y, z, false, false, false, false)
  SetEntityHeading(ped, heading or 0.0)

  -- Register the chosen point with Cfx spawnmanager so death respawns
  -- land here too. Removed on playerDisconnected to keep the map's point
  -- list from leaking entries across reconnects.
  --
  -- THE SHAPE MATTERS: `addSpawnPoint` takes ONE table - { x, y, z, heading,
  -- model } - and it validates every field of it. The old call passed five
  -- positional arguments, so the export received a NUMBER where it expected a
  -- table, and `spawn.x` on a number is an error. The error was swallowed by
  -- the export wrapper, so nothing looked broken - the spawn point simply was
  -- never registered, and a player who died respawned at the default point
  -- instead of where they stood.
  characterSpawnIndex = exports.spawnmanager:addSpawnPoint({
    x = x,
    y = y,
    z = z,
    heading = heading or 0.0,
    model = appearance and appearance.model,
  })

  -- Dismiss the FiveM loading overlay before the world fades in.
  ShutdownLoadingScreen()
  DoScreenFadeIn(500)
  while not IsScreenFadedIn() do Wait(0) end

  -- spawnmanager handles respawn on death from here on.
  exports.spawnmanager:setAutoSpawn(true)

  print(('[nifty-world] entered world as %s %s'):format(
    firstName, lastName or ''))

  TriggerEvent('nifty:client:worldReady')
end

-- Hand the ped to the player and drop them into the world.
--
-- Persistence contract: if the character row carries a `position` (saved on
-- every disconnect/autosave), the player resumes there directly. If `position`
-- is null the server falls back to SpawnPoints.default, so the player still
-- lands somewhere valid without being asked.
--
-- The spawn PICKER is gone. It needed a full-screen NUI panel in nifty-core,
-- and a full-screen panel in the base resource composited ABOVE every other
-- resource's CEF frame - it swallowed every click in the character creator.
-- The server already set usePicker=false on this path (sv_main.lua), so the
-- branch below it had no live caller anyway; only the export call survived.
RegisterNetEvent('nifty:client:enterWorld', function(data)
  waitingForWorld = false

  local appearance = data.character.appearance
  local firstName  = data.character.firstName
  local lastName   = data.character.lastName

  -- The server's watchdog is waiting for exactly this: it sent the world
  -- entry through the welcome cutscene and does not know whether it arrived.
  -- Saying so cancels the watchdog - otherwise the player would be moved a
  -- second time a minute later.
  TriggerServerEvent('nifty:server:worldEntered')

  -- data.spawn IS the last known position, or the configured default for a row
  -- whose position was null. The server decides usePicker=false on this path
  -- (sv_main.lua), so there is no branch to take here.
  doEnterWorldSpawn(
    data.spawn.x, data.spawn.y, data.spawn.z,
    data.spawn.heading or 0.0,
    appearance, firstName, lastName
  )
end)

RegisterNetEvent('nifty:client:openCreator', function()
  -- The character row already exists; this is the second half of making it
  -- playable. Held frozen and visible so nobody walks around the city as an
  -- unowned ped, and the creator has to show the player their own face next
  -- to the menu it is about to open.
  --
  -- The data engine init and the NUI open are owned by nifty-creator's
  -- cl_nui.lua handler for the same event; calling the export here too
  -- double-initialised the data and would race the focus broker. Just
  -- prepare the ped and let the creator's own handler do the rest.
  local ped = PlayerPedId()
  FreezeEntityPosition(ped, true)
  SetEntityVisible(ped, true)
end)

RegisterNetEvent('nifty:client:creatorError', function(message)
  print(('[nifty-world] creator refused: %s'):format(tostring(message)))
end)

local function getCurrentAppearance()
  return currentAppearance
end

-- Persist on the way out, opportunistically. ADR-0004: nothing is lost across a
-- restart.
--
-- This is a fast path, not the mechanism. Under OneSync big mode a player who
-- disconnects outside server range may never see this handler run, so the
-- periodic save below is what actually guarantees the appearance survives.
AddEventHandler('playerDisconnected', function()
  if not waitingForWorld then
    TriggerServerEvent('nifty:server:saveCharacter', {
      appearance = getCurrentAppearance(),
    })
  end

  if characterSpawnIndex then
    pcall(function() exports.spawnmanager:removeSpawnPoint(characterSpawnIndex) end)
    characterSpawnIndex = nil
  end
end)

-- Periodic save. The position is what this is for.
--
-- NOT THE APPEARANCE, and that needs saying out loud, because the old comment
-- claimed both. The client does not keep a copy of the appearance it is
-- wearing: `currentAppearance` is set in `applyAppearance`, which nobody calls
-- (the world entry goes through `applyAppearanceParts`), so it was always nil
-- and the autosave always sent nothing.
--
-- Sending it anyway would be WORSE than not sending it. Every path that
-- changes the appearance saves it itself and immediately - the creator, the
-- store, the wardrobe, the hood - and those saves happen on the SERVER. The
-- client's copy would be the one from the world entry, so the autosave would
-- write the OLD appearance back over the new one and take the player's
-- purchase with it.
--
-- The position has no such problem: the server reads it from the ped's actual
-- coordinates, so the client cannot even get it wrong.
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
      TriggerServerEvent('nifty:server:saveCharacter', {})
    end
  end
end)

-- Signal readiness once the client is actually in the world.
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

-- The resolved face natives, for the creator to reuse.
--
-- Exported rather than duplicated on purpose: the whole point of resolving the
-- underscored spellings once is that there is one answer to "which name did we
-- get". A second probe in the creator could answer differently from this one and
-- the two halves of the same feature would disagree.
exports('faceNatives', function()
  return Natives
end)