--- Character creator (ADR-0017, ADR-0023).
---
--- Appearance only. Name, gender, date of birth and birthplace are entered on the
--- WEBSITE through create_character_from_web (migration 021) - the character row
--- already exists by the time this opens. `appearance IS NULL` is what said the
--- creator was needed.
---
--- THE INTERFACE IS THE MENU FRAMEWORK. This resource has no `ui_page` and draws
--- nothing of its own; it borrows the single menu surface from `nifty-ui` through
--- exports. Two reasons, and both are load-bearing:
---
---   * One CEF browser, one focus owner. A second `ui_page` here would put two
---     browsers behind one global `SetNuiFocus` and the player would steer a menu
---     they cannot see.
---   * The menu docks to the RIGHT of the screen, which leaves the middle free. A
---     native GTA menu cannot do that, and a character creator that covers its own
---     subject is not a character creator.
---
--- WHAT THIS FILE DECIDES: nothing. Every collection it offers comes from
--- AppearanceConfig, which lives in nifty-core and is loaded by both sides - so the
--- allowlist the UI offers is the allowlist the server validates against, because
--- there is only one (ADR-0017). The server additionally derives the ped model from
--- the stored gender and refuses the client's own idea of it.

local RESOURCE = GetCurrentResourceName()

--- The menu framework. Same resource as the focus broker; one call opens a menu
--- and takes the keyboard with it.
local Menu = exports['nifty-ui']

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
local applyHairOverlay

local creatorOpen = false
local currentModel = 'mp_m_freemode_01'

--- True when the stored gender has no single freemode model attached to it
--- (`nonbinary`). Then the player picks, because there is nothing to derive.
local modelIsUndecided = false

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

--- Store a pick and show it on the ped immediately.
local function setSlot(kind, id, slot)
  selection[kind][tostring(id)] = slot
  refresh()

  -- A hair overlay rides ON TOP of a hairstyle, so changing the hair moves the
  -- surface it was painted on. Re-applying it here means the overlay follows the
  -- hair automatically instead of the player finding that it vanished.
  if kind == 'components' and tonumber(id) == 2 then
    applyHairOverlay()
  end
end

--- The current pick for a slot, or nil.
local function slotOf(kind, id)
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

--- Clear first: the game keeps facial decorations, so a second overlay would
--- stack on the first instead of replacing it.
--- Assigned rather than `local function` - `setSlot` calls this, and it is
--- declared below that caller.
applyHairOverlay = function()
  local n = natives()
  local ped = PlayerPedId()

  if n.clearPedDecorations then n.clearPedDecorations(ped) end

  local chosen = face.hairOverlay
  if not chosen then return end

  local map = hairOverlayMap or {}
  local preset = chosen.preset or presetForCurrentHair(ped)

  if not preset or not map[preset] then
    print(('[%s] hair overlay preset %s has no collection in the shop map - not applying'):format(
      RESOURCE, tostring(preset)))
    return
  end

  if not n.setFacialDecoration then
    print(('[%s] _SetPedFacialDecoration is missing - no overlay applied'):format(RESOURCE))
    return
  end

  -- Clear first: the game keeps facial decorations, so a second overlay would
  -- stack on the first instead of replacing it.
  if n.clearFacialDecorations then n.clearFacialDecorations(ped) end
  n.setFacialDecoration(ped, map[preset], preset)
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

  Menu:slider(menu, 'Stil', {
    min = 0, max = maxStyle, step = 1, value = math.min(current.style, maxStyle),
    format = function(value) return ('%d / %d'):format(value, maxStyle) end,
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

--- Face features: twenty sliders, each -1.0..1.0.
local function buildFaceMenu()
  local menu = Menu:menu({
    title = 'Gesichtsform',
    subtitle = 'Zwanzig Schieberegler.',
    dock = 'right',
  })

  for id = 0, AppearanceConfig.MAX_FACE_FEATURE do
    local value = face.features[tostring(id)] or 0.0

    Menu:slider(menu, ('Merkmal %d'):format(id), {
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

--- The hair overlay, behind the probe.
---
--- The row is only added when `probeHairOverlays` found presets. A player should
--- never see a menu entry that silently does nothing - and if the map could not be
--- built, the log says exactly why.
local function buildHairOverlayMenu()
  local menu = Menu:menu({
    title = 'Hair Overlay',
    subtitle = 'Legt eine Gesichtstatoo-Schicht ueber die Frisur.',
    dock = 'right',
  })

  Menu:button(menu, 'Keins', {
    description = 'Overlay entfernen.',
    onSelect = function()
      face.hairOverlay = nil
      applyHairOverlay()
      Menu:pushMenu(RESOURCE, buildRootMenu())
    end,
  })

  for i, preset in ipairs(hairOverlayPresets) do
    local chosen = preset
    Menu:button(menu, ('Overlay %d'):format(i), {
      description = ('Collection %s'):format(tostring(hairOverlayMap[chosen])),
      onSelect = function()
        face.hairOverlay = { preset = chosen }
        applyHairOverlay()
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

  local menu = Menu:menu({ title = label, dock = 'right' })

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
    format = function(value) return ('%d / %d'):format(value, option.drawables - 1) end,
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
    format = function(value) return ('%d / %d'):format(value, option.textures - 1) end,
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
          respawnModel()
          discoverSlots()
          Menu:pushMenu(RESOURCE, buildRootMenu())
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

  -- Added only when the probe found something. The player never sees a row that
  -- cannot work, and the reason it is missing is in the log rather than nowhere.
  if probeHairOverlays() == 'available' then
    Menu:submenu(menu, 'Hair Overlay', {
      description = 'Overlay ueber der Frisur.',
      build = buildHairOverlayMenu,
    })
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

  local n = natives()
  if n.clearPedDecorations then n.clearPedDecorations(PlayerPedId()) end

  respawnModel()
  discoverSlots()

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
  local derived = AppearanceConfig.PED_MODELS[gender]

  modelIsUndecided = (derived == nil)
  currentModel = derived or 'mp_m_freemode_01'
  selection = { components = {}, props = {} }
  face.features = {}
  face.overlays = {}
  face.hairColour = { primary = 0, highlight = 0 }
  face.hairOverlay = nil

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