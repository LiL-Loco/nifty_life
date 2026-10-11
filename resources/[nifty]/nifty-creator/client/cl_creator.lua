--[[
  Character creator (ADR-0017, ADR-0023).

  Appearance only. Name, gender, date of birth and birthplace are entered on the
  WEBSITE through create_character_from_web (migration 021) - the character row
  already exists by the time this opens. `appearance IS NULL` is what said the
  creator was needed.

  THE INTERFACE IS THE MENU FRAMEWORK. This resource has no `ui_page` and draws
  nothing of its own; it borrows the single menu surface from `nifty-ui` through
  exports. Two reasons, and both are load-bearing:

    * One CEF browser, one focus owner. A second `ui_page` here would put two
      browsers behind one global `SetNuiFocus` and the player would steer a menu
      they cannot see.
    * The menu docks to the RIGHT of the screen, which leaves the middle free. A
      native GTA menu cannot do that, and a character creator that covers its own
      subject is not a character creator.

  WHAT THIS FILE DECIDES: nothing. Every collection it offers comes from
  AppearanceConfig, which lives in nifty-core and is loaded by both sides - so the
  allowlist the UI offers is the allowlist the server validates against, because
  there is only one (ADR-0017). The server additionally derives the ped model from
  the stored gender and refuses the client's own idea of it.
]]

local RESOURCE = GetCurrentResourceName()

--- The menu framework. Same resource as the focus broker; one call opens a menu
--- and takes the keyboard with it.
local Menu = exports['nifty-ui']

--- Our own German display labels, and the vendored item data.
---
--- Both are globals set by the two scripts listed above this one in the manifest.
--- Load order is the whole reason they are two files and not one: cl_creator
--- reads them, so they have to exist before it runs.
local Labels = Labels
local GameData = GameData

--- The map builder needs to know what the ped is wearing so it can put it back.
--- It cannot read that back from the engine portably, so it is told - by the only
--- code that knows, which is this one.
GameData.savedSlot = function(kind, id)
  return slotOf(kind, id)
end

-- Forward declarations. The root menu's rows reference these by closure, and a
-- `local function` is only visible FROM ITS OWN LINE ONWARD - declaring them after
-- `buildRootMenu` would capture a global nil instead, and every row would fail the
-- moment it was pressed. Read top to bottom: a definition must precede its use.
local buildSlotMenu
local randomise
local reset
local submit
local cancel
local buildRootMenu
local closeCreator
local refresh
local resolveHairOverlay
local applyDecorations
local buildTattooMenu
local slotOf

local creatorOpen = false
local currentModel = 'mp_m_freemode_01'

--- True when the stored gender has no single freemode model attached to it
--- (`nonbinary`). Then the player picks, because there is nothing to derive.
local modelIsUndecided = false

--- Which ped the current look belongs to. Set at open, read by the item data
--- loader: every name table, tag table and torso map is split by gender, and so
--- is the global index mapping.
local characterGender = 'male'

--- What the player has picked so far, in the exact shape the server validates:
---   { components = { ['3'] = { collection=, drawable=, texture= } }, props = {} }
---
--- Accumulated rather than replaced, so moving away from a slot and coming back
--- shows what was chosen there instead of resetting it.
local selection = { components = {}, props = {} }

--- The slot ids this ped actually has, measured once per model:
---   slots = { components = { [3] = { { name=, drawables=, textures= }, ... } } }
local slots = { components = {}, props = {} }

--- German labels for the freemode component ids.
---
--- DISPLAY ONLY. The id is the truth; these strings are what the player reads, and a
--- wrong label here is a cosmetic bug, never a stored value. They exist because the
--- alternative is a menu that says "Slot 3" and leaves the player guessing.
local COMPONENT_LABELS = {
  [0]  = 'Kopf',
  [1]  = 'Gesicht',
  [2]  = 'Haare',
  [3]  = 'Oberteil',
  [4]  = 'Hose',
  [5]  = 'Schuhe',
  [6]  = 'Handschuhe',
  [7]  = 'Accessoires',
  [8]  = 'Unterhemd',
  [9]  = 'Jacke',
  [10] = 'Shirt',
  [11] = 'Tasche',
  [12] = 'Hose (2)',
}

local PROP_LABELS = {
  [0] = 'Kopfbedeckung',
  [1] = 'Brille',
  [2] = 'Ohrring',
  [6] = 'Schmuck',
  [7] = 'Uhr',
}

--- Component ids in the order they are listed. A hand-written order rather than a
--- sort of the keys, because it is the order a player reads a body top to bottom.
local COMPONENT_ORDER = { 3, 4, 5, 6, 8, 9, 10, 11, 12, 0, 1, 2 }

--- Collections in a STABLE order.
---
--- `AppearanceConfig.ALLOWED_COLLECTIONS` is a set, so `pairs()` over it yields a
--- different order every session. Harmless for validation, hostile for a menu: the
--- same collection would sit in a different row on the next login, and a player who
--- learned "Farbe ist die dritte" would be wrong.
local COLLECTION_NAMES = (function()
  local names = {}
  for name in pairs(AppearanceConfig.ALLOWED_COLLECTIONS) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end)()

-- --------------------------------------------------------------- discovery

--- What one slot offers for the current ped: every permitted collection with at
--- least one drawable, plus its drawable and texture counts.
---
--- These are the collection natives, which are CLIENT-ONLY (see appearance_config).
--- The server cannot ask the engine what exists and therefore cannot invent this
--- list - it can only check that the numbers a client sends sit inside its bounds.
local function slotOptions(ped, id, isProp)
  local out = {}

  for _, name in ipairs(COLLECTION_NAMES) do
    local drawables, textures

    if isProp then
      drawables = GetNumberOfPedCollectionPropDrawableVariations(ped, id, name)
      textures  = GetNumberOfPedCollectionPropTextureVariations(ped, id, name)
    else
      drawables = GetNumberOfPedCollectionDrawableVariations(ped, id, name)
      textures  = GetNumberOfPedCollectionTextureVariations(ped, id, name)
    end

    if drawables > 0 then
      out[#out + 1] = {
        name      = name,
        drawables = drawables,
        -- A collection can legitimately report zero textures and is still a usable
        -- drawable, so the count is floored at 1 rather than producing a slider
        -- whose maximum sits below its minimum.
        textures  = math.max(1, textures or 0),
      }
    end
  end

  return out
end

--- Measure the whole ped. Once per model, not once per menu: a few hundred native
--- calls, and the answer cannot change while the process lives.
---
--- The maxima are reported because `AppearanceConfig.MAX_DRAWABLE` /
--- `MAX_TEXTURE` are the server's only defence against a nonsense index, and they
--- were written as estimates. This is where the real numbers come from - and the
--- warning below exists so that a bound which is too tight says so at BOOT instead
--- of surfacing hours later as a player who cannot save a hat that is visibly on
--- their head.
local function discoverSlots()
  local ped = PlayerPedId()
  local maxDrawables, maxTextures = 0, 0

  for _, kind in ipairs({ 'components', 'props' }) do
    local isProp = (kind == 'props')
    slots[kind] = {}

    for id = AppearanceConfig.MIN_COMPONENT_ID, AppearanceConfig.MAX_COMPONENT_ID do
      local options = slotOptions(ped, id, isProp)
      if #options > 0 then
        slots[kind][id] = options
      end

      for _, option in ipairs(options) do
        if option.drawables > maxDrawables then maxDrawables = option.drawables end
        if option.textures > maxTextures then maxTextures = option.textures end
      end
    end
  end

  local components, props = 0, 0
  for _ in pairs(slots.components) do components = components + 1 end
  for _ in pairs(slots.props) do props = props + 1 end

  print(('[%s] %s: %d component slots, %d prop slots; highest drawable %d, highest texture %d'):format(
    RESOURCE, currentModel, components, props, maxDrawables, maxTextures))

  if maxDrawables > AppearanceConfig.MAX_DRAWABLE or maxTextures > AppearanceConfig.MAX_TEXTURE then
    print(('[%s] WARNING AppearanceConfig is too tight - the server will refuse saves. ' ..
      'Drawables reach %d (bound %d), textures reach %d (bound %d). Raise MAX_DRAWABLE / ' ..
      'MAX_TEXTURE to at least those values, or the creator will reject legitimate clothing.'):format(
      RESOURCE, maxDrawables, AppearanceConfig.MAX_DRAWABLE,
      maxTextures, AppearanceConfig.MAX_TEXTURE))
  end
end

--- Prop ids sorted, so the accessory rows do not move between sessions.
local function propIdsSorted()
  local ids = {}
  for id in pairs(slots.props) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- ------------------------------------------------------------------ apply

local function applySlot(ped, kind, id, slot)
  if kind == 'components' then
    SetPedCollectionPreloadVariationData(ped, id, slot.collection, slot.drawable, slot.texture, 0)
    SetPedCollectionComponentVariation(ped, id, slot.collection, slot.drawable, slot.texture, 0)
  else
    SetPedCollectionPreloadPropData(ped, id, slot.collection, slot.drawable, slot.texture, true)
    SetPedCollectionPropIndex(ped, id, slot.collection, slot.drawable, slot.texture, false)
  end
end

--- Re-spawn the ped on its model, which resets it to that model's defaults. Used on
--- open and on Zurücksetzen.
---
--- Changing the model invalidates the old ped handle, so every later
--- `PlayerPedId()` in this file must be re-fetched rather than taken from a cache.
local function respawnModel()
  local hash = joaat(currentModel)
  SetPlayerModel(PlayerId(), hash)
  SetModelAsNoLongerNeeded(hash)
  return PlayerPedId()
end

--- Put the torso that fits under the current top on slot 3.
---
--- Without this a leather jacket is drawn over whatever torso happened to be there
--- and the player watches their own character clip through itself while choosing a
--- face. That is the single ugliest thing in a freemode creator.
---
--- The data speaks GLOBAL indices and this project stores collection-local ones
--- (ADR-0017), so the global torso is looked back up in slot 3's own map and
--- stored as the local coordinates the database uses. One storage format, not two.
---
--- A top with no torso data returns nil, and then slot 3 is left alone. Forcing a
--- default there would quietly take away the player's own choice of shirt.
local function applyBestTorso()
  local top = slotOf('components', 11)
  if not top then return end

  -- The drawable count of the SELECTED collection, not of the first one. The
  -- global index map is built a whole collection at a time, and building it with
  -- the wrong count produces a map that only knows index 0 - which then looks
  -- exactly like "this item has no name".
  local count = 1
  for _, option in ipairs(slots.components[11] or {}) do
    if option.name == top.collection then count = option.drawables break end
  end

  local globalDrawable, globalTexture = GameData.bestTorso(
    top.collection, top.drawable, top.texture, count)

  if not globalDrawable then return end

  local options = slots.components[3]
  if not options then return end

  local started = GetGameTimer()

  for _, option in ipairs(options) do
    local drawable = GameData.localForGlobal('components', 3, globalDrawable, option.name, option.drawables)
    if drawable then
      local texture = tonumber(globalTexture) or 0
      if texture >= option.textures then texture = option.textures - 1 end
      if texture < 0 then texture = 0 end

      selection.components['3'] = {
        collection = option.name,
        drawable   = drawable,
        texture    = texture,
      }
      print(('[%s] best torso %d -> slot 3 collection "%s" drawable %d (%d ms)'):format(
        RESOURCE, globalDrawable, option.name, drawable, GetGameTimer() - started))
      return
    end
  end

  print(('[%s] best torso %d found no matching collection-local drawable on slot 3 - slot left alone'):format(
    RESOURCE, globalDrawable))
end

--- Store a pick and show it on the ped immediately.
local function setSlot(kind, id, slot)
  selection[kind][tostring(id)] = slot

  -- A top drags its torso with it. Done BEFORE the refresh, so the torso and the
  -- top arrive in the same frame instead of the player seeing the clipping for a
  -- moment and then watching it fix itself.
  if kind == 'components' and tonumber(id) == 11 then
    applyBestTorso()
  end

  refresh()

  -- A hair overlay rides ON TOP of a hairstyle, so changing the hair moves the
  -- surface it was painted on. Re-resolving it here means the overlay follows the
  -- hair automatically instead of the player finding that it vanished.
  if kind == 'components' and tonumber(id) == 2 then
    resolveHairOverlay()
    applyDecorations()
  end
end

--- The current pick for a slot, or nil.
slotOf = function(kind, id)
  return selection[kind][tostring(id)]
end

-- ----------------------------------------------------------------- camera

local creatorCam = nil
local camYaw = 0.0
local camPitch = 0.0
local camRadius = 2.6

local function startCamera()
  local scene = CreatorScene

  camYaw = scene.heading
  camPitch = scene.camPitch
  camRadius = scene.camRadius

  local cam = CreateCamWithParams(
    'DEFAULT_SCRIPTED_CAMERA',
    scene.x, scene.y + scene.camHeight, scene.z + 1.4,
    0.0, 0.0, 0.0, 50.0, false, 0
  )

  creatorCam = cam
  RenderScriptCams(cam, true, false, 0)
  FreezeCamPosition(cam, false)

  -- Firing off so a player cannot shoot themselves while posing.
  DisablePlayerFiring(PlayerId(), true)
end

local function stopCamera()
  if creatorCam then
    RenderScriptCams(creatorCam, false, false, 0)
    DestroyCam(creatorCam, true)
    creatorCam = nil
  end
  DisablePlayerFiring(PlayerId(), false)
end

--- Orbit with A/D and W/S, zoom with Q/E.
---
--- KEYS, NOT THE MOUSE. The menu framework owns the keyboard while a menu is open
--- and uses the ARROWS, but the old camera read the mouse - the same axis a slider
--- row drags along. The two fought and the camera won every time the player was
--- adjusting a texture. WASD/Q/E are free while a menu is up and are what a player
--- already expects to turn a character with.
CreateThread(function()
  while true do
    if creatorOpen and creatorCam then
      Wait(0)

      -- 32/33 = A/D, 22/23 = W/S, 14/15 = Q/E.
      local yaw = 0.0
      if IsDisabledControlPressed(0, 32) then yaw = yaw - 1.6 end
      if IsDisabledControlPressed(0, 33) then yaw = yaw + 1.6 end
      camYaw = camYaw + yaw

      local pitch = 0.0
      if IsDisabledControlPressed(0, 22) then pitch = pitch - 0.6 end
      if IsDisabledControlPressed(0, 23) then pitch = pitch + 0.6 end
      camPitch = math.max(-35.0, math.min(25.0, camPitch + pitch))

      local zoom = 0.0
      if IsDisabledControlPressed(0, 14) then zoom = zoom + 0.05 end
      if IsDisabledControlPressed(0, 15) then zoom = zoom - 0.05 end
      camRadius = math.max(1.4, math.min(5.0, camRadius + zoom))

      local scene = CreatorScene
      local x = scene.x + math.sin(math.rad(camYaw)) * camRadius
      local y = scene.y + math.cos(math.rad(camYaw)) * camRadius
      local z = scene.z + 1.4 + math.sin(math.rad(camPitch)) * camRadius

      SetCamCoord(creatorCam, x, y, z)
      PointCamAtCoord(creatorCam, scene.x, scene.y, scene.z + 0.95, 0.9)
    else
      Wait(250)
    end
  end
end)

--- German labels for the thirteen head overlays, in the game's own order.
---
--- The ids come from the engine, not from here - these are what the player reads.
local OVERLAY_LABELS = {
  [0]  = 'Pickel',
  [1]  = 'Bart',
  [2]  = 'Augenbrauen',
  [3]  = 'Alterung',
  [4]  = 'Make-up',
  [5]  = 'Röte',
  [6]  = 'Teint',
  [7]  = 'Sonnenschaden',
  [8]  = 'Lippenstift',
  [9]  = 'Muttermale',
  [10] = 'Brustbehaarung',
  [11] = 'Koerperpickel',
  [12] = 'Koerperpickel (additiv)',
}

--- Face sliders 0..19. The engine gives them no names worth shipping; the player
--- sees a number, which is what every creator shows anyway.
local FEATURE_SLIDER_MIN = -1.0
local FEATURE_SLIDER_MAX = 1.0

--- Face sliders, head overlays, hair colour and the hair overlay decoration.
local face = {
  features = {},
  overlays = {},
  hairColour = { primary = 0, highlight = 0 },
  hairOverlay = nil,
  tattoos = {},
  eyeColour = 0,
  headBlend = { father = 0, mother = 21, resemblance = 0.0, skinTone = 0.0 },
}

--- The whole appearance as the creator currently sees it.
local function appearanceNow()
  return {
    model        = currentModel,
    components   = selection.components,
    props        = selection.props,
    faceFeatures = face.features,
    overlays     = face.overlays,
    hairColour   = face.hairColour,
    hairOverlay  = face.hairOverlay,
    tattoos      = face.tattoos,
    eyeColour    = face.eyeColour,
    headBlend    = face.headBlend,
  }
end

--- Push everything except the model onto the ped.
---
--- Goes through nifty-world rather than setting natives here, because nifty-world
--- owns the single implementation and, more importantly, the single answer to which
--- spelling of a native this client has. A second probe in this resource could
--- resolve differently and the creator would fight the world.
---
--- Assigned, not `local function`: `setSlot` above calls this, and a `local`
--- function declared further down is a DIFFERENT variable as far as setSlot is
--- concerned - the call would go to a global nil.
refresh = function()
  exports['nifty-world']:applyAppearanceParts(PlayerPedId(), appearanceNow())
end

--- ------------------------------------------------------------- hair overlays

--- The face natives, resolved once by nifty-world. Fetched at use, not at load:
--- an export called while the other resource is still starting returns nil, and
--- indexing nil at load time would take this whole file down.
local function natives()
  return exports['nifty-world']:faceNatives() or {}
end

--- 'unchecked' | 'available' | 'unavailable:<reason>'
local hairOverlayState = 'unchecked'

--- preset hash -> collection hash, for every tattoo-shop item in the
--- `hairOverlay` update group.
local hairOverlayMap = nil

--- The overlay presets, in a stable order, so the menu rows do not move between
--- sessions.
local hairOverlayPresets = nil

--- Build the preset -> collection map from the tattoo shop.
---
--- THE UNCERTAIN PART, and the reason this is behind a probe. GTA exposes the
--- tattoo shop items through `GET_TATTOO_SHOP_DLC_ITEM_DATA`, whose third argument
--- is a POINTER to a three-field struct. Lua cannot build that pointer. FiveM ships
--- a C# helper, `GetTattooCollectionData`, that wraps it - but nothing in the
--- documentation says whether that helper is reachable from Lua, and calling a
--- name that turns out not to exist is a nil-call error at runtime rather than a
--- compile error.
---
--- So: probe, and if the map cannot be built, say so in the log and leave the menu
--- row out. A feature that is missing and a feature that is silently broken look
--- identical to a player, and only the first is acceptable.
local function probeHairOverlays()
  if hairOverlayState ~= 'unchecked' then return hairOverlayState end

  local n = natives()
  local function missing(reason)
    hairOverlayState = 'unavailable:' .. reason
    print(('[%s] hair overlays unavailable - %s'):format(RESOURCE, reason))
    return hairOverlayState
  end

  if type(n.numTattooShopDlcItems) ~= 'function' then
    return missing('GetNumTattooShopDlcItems is not available in this runtime')
  end
  if type(n.tattooCollectionData) ~= 'function' then
    return missing('GetTattooCollectionData is not callable from Lua here')
  end

  -- Character index 3 is male, 4 is female. Not our own numbering.
  local characterIndex = (currentModel == 'mp_f_freemode_01') and 4 or 3

  local ok, count = pcall(n.numTattooShopDlcItems, characterIndex)
  if not ok or type(count) ~= 'number' then
    return missing('the tattoo shop item count did not come back as a number')
  end
  if count <= 0 then
    return missing(('the tattoo shop reports %d items'):format(count))
  end

  local map = {}
  local groupHash = joaat('hairOverlay')

  for i = 0, count - 1 do
    local got, data = pcall(n.tattooCollectionData, characterIndex, i)
    if got and type(data) == 'table' and data.preset and data.collection then
      -- `updateGroup` is a uint in some builds and a string in others. Both are
      -- accepted, because whichever this build hands back is the one it uses to
      -- group the shop.
      local group = data.updateGroup
      if group == groupHash or group == 'hairOverlay' or tostring(group) == 'hairOverlay' then
        map[data.preset] = data.collection
      end
    end
  end

  local presets = {}
  for preset in pairs(map) do presets[#presets + 1] = preset end
  if #presets == 0 then
    return missing(('none of the %d shop items belong to the hairOverlay group'):format(count))
  end
  table.sort(presets)

  hairOverlayMap = map
  hairOverlayPresets = presets
  hairOverlayState = 'available'

  print(('[%s] hair overlays: %d presets across %d shop items'):format(
    RESOURCE, #presets, count))

  return hairOverlayState
end

--- The decal preset the game ties to the hairstyle currently on the ped.
---
--- The hairstyle is read back with `GetPedDrawableVariation`, which reports the
--- GLOBAL index the engine actually applied. Going through
--- `GET_HASH_NAME_FOR_COMPONENT` with that is deliberate: the creator stores
--- collection-local drawables, and passing one of those to a native that expects
--- a global one would silently ask about a different hairstyle.
local function presetForCurrentHair(ped)
  local n = natives()
  if type(n.hashNameForComponent) ~= 'function' then return nil end
  if type(n.forcedComponentCount) ~= 'function' then return nil end
  if type(n.getForcedComponent) ~= 'function' then return nil end

  local okHash, hash = pcall(n.hashNameForComponent, ped, 2, GetPedDrawableVariation(ped, 2), 0)
  if not okHash or type(hash) ~= 'number' or hash == 0 then return nil end

  local okCount, count = pcall(n.forcedComponentCount, hash)
  if not okCount or type(count) ~= 'number' then return nil end

  for i = 0, count - 1 do
    -- Out-pointer parameters in FiveM Lua are the least documented corner of the
    -- runtime, so the call is wrapped and its return values read. If this build
    -- hands them back as arguments instead, the probe below finds nothing and the
    -- feature degrades to "no overlay" rather than to an error.
    local ok, fHash, fIndex, fType = pcall(n.getForcedComponent, hash, i, 0, 0, 0)
    if ok and type(fHash) == 'number' and fHash ~= 0 then
      -- Type 10 is the decal component, which is what carries hair overlays.
      if fType == 10 or (fType == nil and hairOverlayMap and hairOverlayMap[fHash]) then
        return fHash
      end
    end
  end

  return nil
end

--- The hair overlay, resolved to hashes and stored.
---
--- IT IS NOT A MENU ROW, and that is a correction of the earlier design. The game
--- ties one specific decal to each hairstyle - that is what the forced-component
--- table below is walking - so offering a list of eighty overlays to pick from
--- would be offering the player a choice the game itself does not have, and the
--- wrong pair simply draws nothing. Picking a hairstyle picks its overlay.
---
--- The stored value is `{ collection, preset }`, both hashes, NOT the hairstyle.
--- That matters on login: nifty-world re-applies a stored appearance without
--- knowing which ped model was picked, and asking the engine again there would
--- mean duplicating a probe whose out-pointer parameters are the least documented
--- corner of the runtime. Resolve once, here, where the uncertainty already lives.
resolveHairOverlay = function()
  if probeHairOverlays() ~= 'available' then
    face.hairOverlay = nil
    return
  end

  local preset = presetForCurrentHair(PlayerPedId())
  local collection = preset and hairOverlayMap and hairOverlayMap[preset] or nil

  face.hairOverlay = (preset and collection)
    and { collection = collection, preset = preset }
    or  nil
end

--- Re-apply everything that shares the facial-decoration channel.
---
--- The clearing and the native calls live in nifty-world, because the engine has
--- ONE channel for the hair overlay and the tattoos, and applying a tattoo on its
--- own would wipe the overlay the player has been wearing since they picked a
--- hairstyle. This only decides WHAT the set is.
applyDecorations = function()
  refresh()
end

-- ------------------------------------------------------------------ menus

--- How many styles an overlay has, bounded.
---
--- `GetNumHeadOverlayValues` is the real count. It is clamped to the configured
--- bound anyway, because the engine count is per-ped and the stored value will be
--- validated against the bound on the server - offering a slider the server would
--- refuse is worse than offering a slightly shorter one.
local function overlayStyleCount(id)
  local n = natives()
  if type(n.numHeadOverlayValues) ~= 'function' then return 1 end

  local ok, count = pcall(n.numHeadOverlayValues, id)
  if not ok or type(count) ~= 'number' or count <= 0 then return 1 end

  return math.min(count - 1, AppearanceConfig.MAX_OVERLAY_STYLE)
end

--- How many colours a palette holds, bounded. 1 = hair palette, 2 = makeup.
local function colourCount(colourType)
  local n = natives()
  local fn = (colourType == 2) and n.numMakeupColors or n.numHairColors
  if type(fn) ~= 'function' then return AppearanceConfig.MAX_OVERLAY_COLOUR + 1 end

  local ok, count = pcall(fn)
  if not ok or type(count) ~= 'number' or count <= 0 then
    return AppearanceConfig.MAX_OVERLAY_COLOUR + 1
  end

  return math.min(count - 1, AppearanceConfig.MAX_OVERLAY_COLOUR)
end

--- One overlay: style, opacity, and its two colours.
local function buildOverlayMenu(id)
  local label = OVERLAY_LABELS[id] or ('Overlay ' .. id)
  local current = face.overlays[tostring(id)] or {
    style = 0, opacity = 1.0, colourType = 1, colour = 0, secondColour = 0,
  }

  local maxStyle = overlayStyleCount(id)
  local menu = Menu:menu({ title = label, dock = 'right' })

  -- "Kein" as a button rather than as slider position 0.
  --
  -- The game switches an overlay off with style 255, and 255 is deliberately
  -- outside the stored range here - a saved 255 would be state the player cannot
  -- see or undo. Style 0 at zero opacity is the same result and is a real value
  -- the sliders can express. This is why the label list below is read one entry
  -- LATER than the native style: its first entry is that off-state, not style 0.
  Menu:button(menu, 'Kein', {
    description = 'Dieses Merkmal ausschalten.',
    onSelect = function()
      face.overlays[tostring(id)] = {
        style = 0, opacity = 0.0, colourType = 1, colour = 0, secondColour = 0,
      }
      refresh()
      Menu:pushMenu(RESOURCE, buildOverlayMenu(id))
    end,
  })

  Menu:separator(menu, 'Stil')

  Menu:slider(menu, 'Stil', {
    min = 0, max = maxStyle, step = 1, value = math.min(current.style, maxStyle),
    format = function(value)
      -- One entry later, because the list starts with the off-state.
      return Labels.overlayStyle(id, value + 1)
    end,
    onChange = function(value)
      face.overlays[tostring(id)] = {
        style = value,
        opacity = tonumber(face.overlays[tostring(id)] and face.overlays[tostring(id)].opacity) or 1.0,
        colourType = tonumber(face.overlays[tostring(id)] and face.overlays[tostring(id)].colourType) or 1,
        colour = tonumber(face.overlays[tostring(id)] and face.overlays[tostring(id)].colour) or 0,
        secondColour = tonumber(face.overlays[tostring(id)] and face.overlays[tostring(id)].secondColour) or 0,
      }
      refresh()
    end,
  })

  -- Opacity in percent, because the native takes 0.0..1.0 and a slider that shows
  -- "0.42" for a beard reads as a fault rather than as a setting.
  Menu:slider(menu, 'Deckkraft', {
    min = 0, max = 100, step = 1, value = math.floor((current.opacity or 1.0) * 100 + 0.5),
    format = function(value) return ('%d %%'):format(value) end,
    onChange = function(value)
      local live = face.overlays[tostring(id)] or {}
      face.overlays[tostring(id)] = {
        style = live.style or 0,
        opacity = value / 100,
        colourType = live.colourType or 1,
        colour = live.colour or 0,
        secondColour = live.secondColour or 0,
      }
      refresh()
    end,
  })

  Menu:separator(menu, 'Farbe')

  -- Palette 0 is a fixed grey and has no indices to choose; only 1 and 2 do.
  for _, entry in ipairs({ { 1, 'Haarfarben' }, { 2, 'Make-up-Farben' } }) do
    local colourType = entry[1]
    local max = colourCount(colourType)
    local value = (current.colourType == colourType) and current.colour or 0

    Menu:slider(menu, entry[2], {
      min = 0, max = max, step = 1, value = math.min(value, max),
      format = function(v) return ('%d / %d'):format(v, max) end,
      onChange = function(v)
        local live = face.overlays[tostring(id)] or {}
        face.overlays[tostring(id)] = {
          style = live.style or 0,
          opacity = live.opacity or 1.0,
          colourType = colourType,
          colour = v,
          secondColour = live.secondColour or 0,
        }
        refresh()
      end,
    })
  end

  return menu
end

--- How the three weights will actually come out as a face.
---
--- The sliders do not have to add up to a hundred, so without this the player
--- cannot tell that 40/40/40 is already a perfectly balanced face. The arithmetic
--- mirrors the one in nifty-world on purpose - same formula, two places, and if
--- they ever disagree it will be because one of them was changed alone.
local function parentsSummary()
  local wm = tonumber(face.headBlend.motherWeight) or 0.5
  local wf = tonumber(face.headBlend.fatherWeight) or 0.5
  local wc = tonumber(face.headBlend.thirdWeight) or 0.0
  local total = wm + wf + wc

  if total <= 0 then
    return 'Alle Anteile auf null - es bleibt ein neutrales Gesicht.'
  end

  return ('Ergebnis: Mutter %d %%, Vater %d %%, dritte Person %d %%'):format(
    math.floor((wm / total) * 100 + 0.5),
    math.floor((wf / total) * 100 + 0.5),
    math.floor((wc / total) * 100 + 0.5))
end

--- Parents and the three blends (`SetPedHeadBlendData`).
---
--- The engine names these presets with numbers and nothing else. Third-party
--- menus turn them into English first names, which tells a German player nothing
--- and is not even true - two of the twenty-four "fathers" are the same face.
--- "Vater 7" is honest about what it is.
---
--- Defaults are mother 21 / father 0 / both mixes 0.0, which is the freemode
--- default the game itself starts from.
local FATHER_COUNT = 21
local MOTHER_COUNT = 22

local function buildParentsMenu()
  local menu = Menu:menu({
    title = 'Eltern',
    subtitle = parentsSummary(),
    dock = 'right',
  })

  Menu:separator(menu, 'Praesets')

  Menu:slider(menu, 'Mutter', {
    min = 0, max = MOTHER_COUNT - 1, step = 1, value = face.headBlend.mother,
    format = function(value) return Labels.MOTHER(value) end,
    onChange = function(value)
      face.headBlend.mother = value
      refresh()
      Menu:pushMenu(RESOURCE, buildParentsMenu())
    end,
  })

  Menu:slider(menu, 'Vater', {
    min = 0, max = FATHER_COUNT - 1, step = 1, value = face.headBlend.father,
    format = function(value) return Labels.FATHER(value) end,
    onChange = function(value)
      face.headBlend.father = value
      refresh()
      Menu:pushMenu(RESOURCE, buildParentsMenu())
    end,
  })

  Menu:slider(menu, 'Dritte Person', {
    -- The whole preset range, not just the mother block. That is the point of a
    -- third face: it can be whoever, including a preset the "mother" list also
    -- contains, and the engine does not care which list a name came from.
    min = 0, max = AppearanceConfig.MAX_HEADBLEND_PRESET, step = 1, value = face.headBlend.third,
    format = function(value) return ('Person %d'):format(value + 1) end,
    onChange = function(value)
      face.headBlend.third = value
      refresh()
      Menu:pushMenu(RESOURCE, buildParentsMenu())
    end,
  })

  Menu:separator(menu, 'Anteile')

  -- THREE weights, not one resemblance slider.
  --
  -- They are percentages that do NOT have to add up to a hundred: the native
  -- works with ratios, so 33/33/33 and 66/66/66 are the same face. The subtitle
  -- shows the proportions the engine will actually produce, because a player who
  -- set 40/40/40 has no way to know it is a perfectly balanced face without being
  -- told.
  local weights = {
    { key = 'motherWeight', label = 'Mutter-Anteil' },
    { key = 'fatherWeight', label = 'Vater-Anteil' },
    { key = 'thirdWeight',  label = 'Anteil dritte Person' },
  }

  for _, weight in ipairs(weights) do
    local key = weight.key
    Menu:slider(menu, weight.label, {
      min = 0, max = 100, step = 1, value = math.floor((face.headBlend[key] or 0.0) * 100 + 0.5),
      format = function(value) return ('%d'):format(value) end,
      onChange = function(value)
        face.headBlend[key] = value / 100
        refresh()
        Menu:pushMenu(RESOURCE, buildParentsMenu())
      end,
    })
  end

  Menu:separator(menu, 'Hautton')

  Menu:slider(menu, 'Hautton', {
    min = 0, max = 100, step = 1, value = math.floor((face.headBlend.skinTone or 0.5) * 100 + 0.5),
    format = function(value) return ('%d %%'):format(value) end,
    onChange = function(value)
      face.headBlend.skinTone = value / 100
      refresh()
    end,
  })

  -- One-touch presets for the shapes players actually ask for. Without these,
  -- "give me a face that is a bit of everyone" means dragging three sliders and
  -- watching a number that is not the number they are setting.
  Menu:separator(menu, 'Schnellwahl')
  for _, preset in ipairs({
    { label = 'Nur Mutter', w = { 1.0, 0.0, 0.0 } },
    { label = 'Nur Vater', w = { 0.0, 1.0, 0.0 } },
    { label = 'Nur dritte Person', w = { 0.0, 0.0, 1.0 } },
    { label = 'Eltern gleich', w = { 0.5, 0.5, 0.0 } },
    { label = 'Alle drei gleich', w = { 1 / 3, 1 / 3, 1 / 3 } },
  }) do
    local weightsToSet = preset.w
    Menu:button(menu, preset.label, {
      description = 'Anteile setzen.',
      onSelect = function()
        face.headBlend.motherWeight = weightsToSet[1]
        face.headBlend.fatherWeight = weightsToSet[2]
        face.headBlend.thirdWeight = weightsToSet[3]
        refresh()
        Menu:pushMenu(RESOURCE, buildParentsMenu())
      end,
    })
  end

  return menu
end

--- Eye colour: the game's thirty-two, in the engine's own order.
local function buildEyeColourMenu()
  local menu = Menu:menu({ title = 'Augenfarbe', dock = 'right' })

  Menu:slider(menu, 'Farbe', {
    min = 0, max = AppearanceConfig.MAX_EYE_COLOUR, step = 1, value = face.eyeColour or 0,
    format = function(value)
      return Labels.EYE_COLOURS[value + 1] or ('Farbe %d'):format(value)
    end,
    onChange = function(value)
      face.eyeColour = value
      refresh()
    end,
  })

  return menu
end

--- Face features: twenty sliders, each -1.0..1.0.
local function buildFaceMenu()
  local menu = Menu:menu({
    title = 'Gesichtsform',
    subtitle = 'Zwanzig Schieberegler.',
    dock = 'right',
  })

  for id = 0, AppearanceConfig.MAX_FACE_FEATURE do
    local value = face.features[tostring(id)] or 0.0

    Menu:slider(menu, Labels.FEATURES[id + 1] or ('Merkmal %d'):format(id), {
      min = FEATURE_SLIDER_MIN, max = FEATURE_SLIDER_MAX, step = 0.05, value = value,
      format = function(v) return ('%+.2f'):format(v) end,
      onChange = function(v)
        -- Sparse: an untouched slider is not stored. A ped whose stored face is
        -- full of zeros and a ped whose stored face has no entries are the same
        -- ped, but only one of them round-trips through the database identically.
        if math.abs(v) < 0.001 then
          face.features[tostring(id)] = nil
        else
          face.features[tostring(id)] = v
        end
        refresh()
      end,
    })
  end

  return menu
end

--- Hair colour: primary and highlight, both from the hair palette.
local function buildHairColourMenu()
  local menu = Menu:menu({ title = 'Haarfarbe', dock = 'right' })
  local max = colourCount(1)

  Menu:slider(menu, 'Hauptfarbe', {
    min = 0, max = max, step = 1, value = math.min(face.hairColour.primary, max),
    format = function(v) return ('%d / %d'):format(v, max) end,
    onChange = function(v)
      face.hairColour.primary = v
      refresh()
    end,
  })

  Menu:slider(menu, 'Strähnen', {
    min = 0, max = max, step = 1, value = math.min(face.hairColour.highlight, max),
    format = function(v) return ('%d / %d'):format(v, max) end,
    onChange = function(v)
      face.hairColour.highlight = v
      refresh()
    end,
  })

  return menu
end

--- One zone's tattoos.
---
--- Grouped by body part because that is how a player thinks about where a tattoo
--- goes, and because the data says so: every entry carries a zone. The alternative
--- is one list of 775 rows per gender, which is not a menu.
local ZONE_LABELS = {
  [0] = 'Torso',
  [1] = 'Kopf und Hals',
  [2] = 'Linker Arm',
  [3] = 'Rechter Arm',
  [4] = 'Linkes Bein',
  [5] = 'Rechtes Bein',
}

buildTattooMenu = function(zoneId)
  local tattoos = GameData.tattoosByZone(zoneId)
  if #tattoos == 0 then return nil end

  local menu = Menu:menu({
    title = ZONE_LABELS[zoneId] or ('Zone ' .. zoneId),
    subtitle = ('%d Tattoo(s)'):format(#tattoos),
    dock = 'right',
  })

  Menu:button(menu, 'Keins', {
    description = 'Alle Tattoos dieser Zone entfernen.',
    onSelect = function()
      local kept = {}
      for _, tattoo in ipairs(face.tattoos) do
        if tattoo.zoneId ~= zoneId then kept[#kept + 1] = tattoo end
      end
      face.tattoos = kept
      applyDecorations()
      Menu:pushMenu(RESOURCE, buildRootMenu())
    end,
  })

  Menu:separator(menu, ZONE_LABELS[zoneId] or ('Zone ' .. zoneId))

  for _, tattoo in ipairs(tattoos) do
    local entry = tattoo
    Menu:button(menu, entry.name, {
      description = entry.collection,
      onSelect = function()
        -- ONE PER ZONE, not one per collection. Two tattoos on the same arm
        -- compete for the same skin and the second is invisible, so letting the
        -- player pick another one in the same place would look like a menu that
        -- does not work. The stored entry keeps its zone precisely so this
        -- decision can be made on the client, where the data is.
        local kept = {}
        for _, other in ipairs(face.tattoos) do
          if other.zoneId ~= zoneId then kept[#kept + 1] = other end
        end

        if #kept < AppearanceConfig.MAX_TATTOOS then
          kept[#kept + 1] = {
            collection = entry.collection,
            preset = entry.preset,
            zoneId = zoneId,
          }
          face.tattoos = kept
          applyDecorations()
        end

        Menu:pushMenu(RESOURCE, buildRootMenu())
      end,
    })
  end

  return menu
end

--- The submenu for one slot: which collection, which drawable, which texture.
buildSlotMenu = function(kind, id)
  local options = slots[kind][id]
  if not options or #options == 0 then return nil end

  local isProp = (kind == 'props')
  local current = slotOf(kind, id)

  -- Where the player currently stands, resolved against the CURRENT options. A
  -- stored collection this ped does not have - a DLC that is not installed, a
  -- model swap - falls back to the first option rather than to nothing.
  local index = 1
  for i, option in ipairs(options) do
    if current and current.collection == option.name then
      index = i
      break
    end
  end

  local option = options[index]
  local drawable = (current and tonumber(current.drawable)) or 0
  local texture = (current and tonumber(current.texture)) or 0

  if drawable >= option.drawables then drawable = option.drawables - 1 end
  if drawable < 0 then drawable = 0 end
  if texture >= option.textures then texture = option.textures - 1 end
  if texture < 0 then texture = 0 end

  local label = isProp
    and (PROP_LABELS[id] or ('Prop ' .. id))
    or  (COMPONENT_LABELS[id] or ('Slot ' .. id))

  -- The real item name, if this slot and this ped have one. Slots 0, 9, 10 and 12
  -- never do - those are not items the game ever sold - and a component the data
  -- has no table for must show a number rather than an empty menu row.
  local kind = isProp and 'props' or 'components'
  local function nameFor(drawableId, textureId)
    return GameData.itemName(isProp, id, option.name, drawableId, textureId, option.drawables)
  end

  local currentName = nameFor(drawable, texture)
  local currentTags = GameData.itemTags(isProp, id, option.name, drawable, texture, option.drawables)

  local menu = Menu:menu({
    title = currentName and ('%s - %s'):format(label, currentName) or label,
    subtitle = #currentTags > 0 and ('Merkmale: ' .. table.concat(currentTags, ', ')) or nil,
    dock = 'right',
  })

  local labels = {}
  for i, opt in ipairs(options) do
    labels[i] = (opt.name == '') and 'Standard' or opt.name
  end

  Menu:select(menu, 'Kollektion', {
    items       = labels,
    index       = index,
    description = 'Gibt an, welche DLC die Kleidung liefert.',
    onChange    = function(chosen)
      local picked = options[chosen]
      if not picked then return end

      -- Changing the collection invalidates drawable AND texture: both counts are
      -- per collection, so a drawable that is index 12 in one DLC can be index 3
      -- in the next. Keeping the old numbers would store a combination that never
      -- existed - and the server would accept it, because both are in range.
      local live = slotOf(kind, id) or {}
      setSlot(kind, id, {
        collection = picked.name,
        drawable   = math.min(tonumber(live.drawable) or 0, picked.drawables - 1),
        texture    = math.min(tonumber(live.texture) or 0, picked.textures - 1),
      })

      -- Re-present with the new bounds. Without it the two sliders keep the old
      -- maximum and a drawable past the end of the new collection is reachable.
      Menu:pushMenu(RESOURCE, buildSlotMenu(kind, id))
    end,
  })

  Menu:slider(menu, 'Modell', {
    min = 0, max = option.drawables - 1, step = 1, value = drawable,
    format = function(value)
      -- The name of the item under the cursor, not the number it happens to have.
      -- A slider that says "Brown Leather Fur Jacket" and one that says "311" are
      -- the same control, and only one of them tells a player what they picked.
      return nameFor(value, texture) or ('%d / %d'):format(value, option.drawables - 1)
    end,
    onChange = function(value)
      local live = slotOf(kind, id) or {}
      setSlot(kind, id, {
        collection = option.name,
        drawable   = value,
        texture    = tonumber(live.texture) or 0,
      })
    end,
  })

  Menu:slider(menu, 'Textur', {
    min = 0, max = option.textures - 1, step = 1, value = texture,
    format = function(value)
      -- The texture is a COLOUR VARIATION, not a fabric index - "Tan" against
      -- "Brown". So the name of the exact variation is the useful label here, not
      -- on the drawable row above.
      return nameFor(drawable, value) or ('%d / %d'):format(value, option.textures - 1)
    end,
    onChange = function(value)
      local live = slotOf(kind, id) or {}
      setSlot(kind, id, {
        collection = option.name,
        drawable   = tonumber(live.drawable) or 0,
        texture    = value,
      })
    end,
  })

  return menu
end

--- The root menu: one row per available slot, then the actions.
buildRootMenu = function()
  local menu = Menu:menu({
    title    = 'Charakter erstellen',
    subtitle = 'Aussehen - Name und Stammdaten stehen bereits fest.',
    dock     = 'right',
    onClose  = function(reason)
      -- Escape or Backspace at the root is the same event as pressing Abbrechen.
      -- Leaving the ped frozen with no menu and no way out is not a state anybody
      -- should be able to reach, so the dismissal is answered by the same net event.
      -- 'submitted' is the one reason that means something else.
      if reason ~= 'submitted' and reason ~= 'cancelled' then
        print(('[%s] creator menu dismissed (%s) - cancelling'):format(RESOURCE, tostring(reason)))
        TriggerServerEvent('nifty:server:cancelCreator')
      end
    end,
  })

  -- Only a gender with no model attached gets a picker. `nonbinary` is one, and
  -- inventing a body for it here would be the server deciding something the player
  -- is entitled to say about themselves.
  if modelIsUndecided then
    Menu:separator(menu, 'Modell')
    for _, entry in ipairs({ { 'mp_m_freemode_01', 'Maennlich' },
                             { 'mp_f_freemode_01', 'Weiblich' } }) do
      Menu:button(menu, entry[2], {
        description = 'Freemode-Modell waehlen.',
        onSelect = function()
          currentModel = entry[1]
          modelIsUndecided = false
          -- The item data follows the MODEL here, not the recorded gender: the
          -- player chose a body, and a female ped on a "nonbinary" character still
          -- wears the female tables.
          characterGender = (entry[1] == 'mp_f_freemode_01') and 'female' or 'male'
          GameData.setGender(characterGender)
          respawnModel()
          discoverSlots()
          resolveHairOverlay()
          applyDecorations()          Menu:pushMenu(RESOURCE, buildRootMenu())
        end,
      })
    end
  end

  Menu:separator(menu, 'Kleidung')
  for _, id in ipairs(COMPONENT_ORDER) do
    local options = slots.components[id]
    if options then
      Menu:submenu(menu, COMPONENT_LABELS[id] or ('Slot ' .. id), {
        description = ('Slot %d - %d Kollektionen'):format(id, #options),
        build = function() return buildSlotMenu('components', id) end,
      })
    end
  end

  local propIds = propIdsSorted()
  if #propIds > 0 then
    Menu:separator(menu, 'Accessoires')
    for _, id in ipairs(propIds) do
      Menu:submenu(menu, PROP_LABELS[id] or ('Prop ' .. id), {
        description = ('Prop %d - %d Kollektionen'):format(id, #slots.props[id]),
        build = function() return buildSlotMenu('props', id) end,
      })
    end
  end

  Menu:separator(menu, 'Gesicht')
  Menu:submenu(menu, 'Eltern', {
    description = 'Vater, Mutter und die beiden Mischungen.',
    build = buildParentsMenu,
  })

  Menu:submenu(menu, 'Augenfarbe', {
    description = 'Eine von dreissigzwei.',
    build = buildEyeColourMenu,
  })

  Menu:separator(menu, 'Merkmale')

  for id = AppearanceConfig.MIN_OVERLAY_ID, AppearanceConfig.MAX_OVERLAY_ID do
    Menu:submenu(menu, OVERLAY_LABELS[id] or ('Overlay ' .. id), {
      description = 'Stil, Deckkraft und Farbe.',
      build = function() return buildOverlayMenu(id) end,
    })
  end

  Menu:submenu(menu, 'Haarfarbe', {
    description = 'Hauptfarbe und Strähnen.',
    build = buildHairColourMenu,
  })

  Menu:submenu(menu, 'Gesichtsform', {
    description = 'Die zwanzig Gesichtsschieberegler.',
    build = buildFaceMenu,
  })

  -- Tattoos, grouped by the body part they go on. The hair overlay is NOT here:
  -- the game ties exactly one decal to each hairstyle, so picking the hair picks
  -- the overlay. A list to choose from would offer a combination the game has no
  -- way to draw.
  local tattooZones = GameData.tattooZones()
  if #tattooZones > 0 then
    Menu:separator(menu, 'Tattoos')
    for _, zoneId in ipairs(tattooZones) do
      Menu:submenu(menu, ZONE_LABELS[zoneId] or ('Zone ' .. zoneId), {
        description = ('%d Tattoo(s)'):format(#GameData.tattoosByZone(zoneId)),
        build = function() return buildTattooMenu(zoneId) end,
      })
    end
  end

  Menu:separator(menu, 'Aktionen')

  Menu:button(menu, 'Zufallsaufzug', {
    description = 'Zufaellige Kleidung. A/D dreht die Kamera.',
    onSelect = function() randomise() end,
  })

  Menu:button(menu, 'Zuruecksetzen', {
    description = 'Alle Auswaehle verwerfen und das Modell neu laden.',
    onSelect = function() reset() end,
  })

  Menu:button(menu, 'Fertig', {
    description = 'Aussehen speichern und die Welt betreten.',
    onSelect = function() submit() end,
  })

  Menu:button(menu, 'Abbrechen', {
    description = 'Verlassen. Beim naechsten Verbinden geht es hier weiter.',
    onSelect = function() cancel() end,
  })

  return menu
end

-- ---------------------------------------------------------------- actions

local function openRoot()
  if Menu:openMenu(RESOURCE, buildRootMenu()) then return end

  -- Another surface holds the keyboard. The player is standing frozen in the
  -- creator, so the honest thing is to let the server drop them rather than leave
  -- a ped nobody can reach and no explanation for why.
  print(('[%s] could not open the creator menu - focus is held elsewhere'):format(RESOURCE))
  TriggerServerEvent('nifty:server:cancelCreator')
end

randomise = function()
  local ped = PlayerPedId()

  -- Either the clothes or the accessories stay mostly bare, so the result reads as
  -- a person rather than as someone wearing every hat in the game.
  local dressProps = (math.random(1, 4) == 1)

  selection = { components = {}, props = {} }

  for kind, options in pairs(slots) do
    for id, list in pairs(options) do
      if (kind == 'props') == dressProps or math.random(1, 3) ~= 1 then
        local chosen = list[math.random(#list)]
        if chosen then
          local slot = {
            collection = chosen.name,
            drawable   = math.random(0, chosen.drawables - 1),
            texture    = math.random(0, chosen.textures - 1),
          }
          selection[kind][tostring(id)] = slot
          applySlot(ped, kind, id, slot)
        end
      end
    end
  end

  if Menu:isOpen() then Menu:pushMenu(RESOURCE, buildRootMenu()) end
end

reset = function()
  selection = { components = {}, props = {} }
  face.features = {}
  face.overlays = {}
  face.hairColour = { primary = 0, highlight = 0 }
  face.hairOverlay = nil
  face.tattoos = {}
  face.eyeColour = 0
  face.headBlend = { father = 0, mother = 21, third = 21, motherWeight = 0.5, fatherWeight = 0.5, thirdWeight = 0.0, skinTone = 0.5 }

  local n = natives()
  if n.clearPedDecorations then n.clearPedDecorations(PlayerPedId()) end

  respawnModel()
  discoverSlots()

  -- The model changed under the hair overlay. Resolve it again rather than
  -- leaving a preset that belonged to the previous ped on the new one.
  resolveHairOverlay()
  applyDecorations()

  if Menu:isOpen() then Menu:pushMenu(RESOURCE, buildRootMenu()) end
end

submit = function()
  -- Only the appearance goes up. The model travels with it because the server
  -- derives it again and overwrites this value; sending a name, a date of birth or
  -- a gender here would be sending data that has no reader, and data with no reader
  -- is data that will eventually be trusted.
  TriggerServerEvent('nifty:server:finishAppearance', { appearance = appearanceNow() })
end

cancel = function()
  closeCreator('cancelled')
  TriggerServerEvent('nifty:server:cancelCreator')
end

-- ------------------------------------------------------------- open/close

closeCreator = function(reason)
  if not creatorOpen then return end
  creatorOpen = false
  stopCamera()
  Menu:closeMenu(RESOURCE, reason or 'closed')
end

exports('openCreator', function(data)
  if creatorOpen then return end
  creatorOpen = true

  -- The model comes from the gender the SERVER sent, not from a picker. A player
  -- does not choose a ped model; the character has one, the website recorded which,
  -- and offering a free choice here would be offering a choice the server silently
  -- overrides.
  local gender = (type(data) == 'table' and data.gender) or 'male'
  characterGender = gender
  local derived = AppearanceConfig.PED_MODELS[gender]

  modelIsUndecided = (derived == nil)
  currentModel = derived or 'mp_m_freemode_01'

  -- Which ped's items we are looking at. The name tables, the tags and the torso
  -- mappings are all split by gender, and the global index map is per model, so
  -- this has to happen before anything is looked up - not lazily on first use,
  -- which would read a leather jacket's name out of the female table.
  GameData.setGender(characterGender)
  selection = { components = {}, props = {} }
  face.features = {}
  face.overlays = {}
  face.hairColour = { primary = 0, highlight = 0 }
  face.hairOverlay = nil
  face.tattoos = {}
  face.eyeColour = 0
  face.headBlend = { father = 0, mother = 21, third = 21, motherWeight = 0.5, fatherWeight = 0.5, thirdWeight = 0.0, skinTone = 0.5 }

  -- The probe result is per model, so it is re-run when the model changes. A
  -- female ped has its own tattoo shop, and a map built for the male one would
  -- offer presets that do not exist here.
  hairOverlayState = 'unchecked'
  hairOverlayMap = nil
  hairOverlayPresets = nil

  local scene = CreatorScene
  local ped = PlayerPedId()
  SetEntityCoords(ped, scene.x, scene.y, scene.z, false, false, false, false)
  SetEntityHeading(ped, scene.heading)
  FreezeEntityPosition(ped, true)

  respawnModel()
  discoverSlots()
  startCamera()
  openRoot()
end)

exports('closeCreator', function(reason)
  closeCreator(reason or 'closed')
end)

exports('isCreatorOpen', function() return creatorOpen end)

-- ---------------------------------------------------------------- results

RegisterNetEvent('nifty:client:enterWorld', function()
  closeCreator('submitted')
end)

RegisterNetEvent('nifty:client:creatorError', function(message)
  -- The creator deliberately stays open: the player has to be able to press Fertig
  -- again, and closing on an error would turn "try once more" into "start over".
  print(('[%s] creator refused: %s'):format(RESOURCE, tostring(message)))
end)