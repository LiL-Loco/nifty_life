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

--- Local menu surface.
---
--- The menu draws directly to the screen with GTA natives (DrawSprite,
--- DrawText, DrawRect) and never touches NUI focus, so the focus broker
--- is irrelevant for it. We use the same NativeUI-Lua-Reloaded library
--- nifty-ui vendors, but loaded locally via @nifty-ui/... paths in the
--- manifest. Within this resource the export-proxy quirks (drop-first-arg,
--- deep-copy-return) do not apply, so the builders can use the menu
--- argument as-is and the menu can keep its metatable.
---
--- API shape matches the call sites below:
---   Menu.menu({title=, subtitle=, dock=, onClose=})  -> UIMenu
---   Menu.separator(menu, label)
---   Menu.button(menu, label, spec)
---   Menu.submenu(menu, label, {build=, description=, disabled=})
---   Menu.slider(menu, label, {min=, max=, step=, value=, onChange=, onSelect=, description=, disabled=})
---   Menu.select(menu, label, {items=, index=, onChange=, onSelect=, description=, disabled=})
---   Menu.openMenu(_RESOURCE_, menu)   - add to pool, show
---   Menu.pushMenu(_RESOURCE_, menu)   - close current, show new
---   Menu.closeMenu(_RESOURCE_, reason) - close the visible menu
---   Menu.isOpen()                     - any menu visible?
---
--- The first arg of openMenu / pushMenu / closeMenu is a resource name in
--- the cross-resource shim; here it is ignored, but accepting the shape
--- keeps the call sites identical to the previous shim-based version.

-- NUI bone-projection: a subset of GTA's facial bones that the NUI
-- positions as draggable dots over the camera viewport. The mapping
-- boneName -> feature id lives in the NUI (it pairs drag direction
-- with the axis of the relevant grid panel).
local FACE_BONE_NAMES = {
  'skel_l_cheek', 'skel_r_cheek', 'skel_l_eyeball', 'skel_r_eyeball',
  'skel_l_lip_lower_corner', 'skel_r_lip_lower_corner',
  'skel_l_eyebrow_01', 'skel_l_eyebrow_02', 'skel_l_eyebrow_03',
  'skel_r_eyebrow_01', 'skel_r_eyebrow_02', 'skel_r_eyebrow_03',
  'skel_l_nose_01', 'skel_l_nose_02', 'skel_r_nose_01', 'skel_r_nose_02',
  'skel_l_jawline_root', 'skel_r_jawline_root',
  'skel_l_chin_01', 'skel_l_chin_02', 'skel_l_chin_03',
  'skel_r_chin_01', 'skel_r_chin_02', 'skel_r_chin_03',
}

-- 96x96 transparent PNG placeholder. The NUI uses this when the
-- live-render is not available; replaced with a real head-blend
-- screenshot in V2.
local SILHOUETTE_PLACEHOLDER_BASE64 = ''

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
--
-- slotOf is defined further down (it depends on `selection` being initialised
-- with the structure the gamedata module builds up). To break the
-- forward-reference cycle without making `selection` global, we declare
-- a stub here that the real definition later overwrites in place.
local slotOf
-- slotOf is a closure-captured reference here. Lua binds the upvalue
-- at function-definition time; if slotOf is not a local in scope at
-- that point, the lookup becomes a global, which is always nil. The
-- real definition is further down (it depends on `selection` which is
-- initialised after this point), so we forward-declare slotOf as a
-- local here. Without this line, GameData.savedSlot() would call
-- nil and the gamedata module's map builder would crash.
local slotOf
GameData.savedSlot = function(kind, id)
  return slotOf(kind, id)
end

-- Forward declarations. The functions defined further down are
-- referenced by `refresh`, the submit / cancel / reset handlers, and
-- the exports. A `local function` is only visible FROM ITS OWN LINE
-- ONWARD - declaring them after their first use would capture a global
-- nil instead. slotOf is also forward-declared above (just before
-- GameData.savedSlot) so the savedSlot closure's upvalue is bound to
-- a local.
local randomise
local randomiseAll
local reset
local submit
local cancel
local closeCreator
local refresh
local zoomCamera
local camFov
local CAM_FOV_MIN
local CAM_FOV_MAX
local CAM_FOV_STEP
local resolveHairOverlay
local applyDecorations
local buildTattooMenu
local openRoot

local creatorOpen = false
local currentModel = 'mp_m_freemode_01'

--- Reverse map of AppearanceConfig.PED_MODELS, which is keyed by model name and
--- valued by gender ('male' / 'female' / 'nonbinary'). The openCreator lookup
--- wants gender -> model, so we flip the table once at load. Any other code that
--- needs model -> gender still reads AppearanceConfig.PED_MODELS directly.
local PED_MODEL_FOR_GENDER = {}
for model, gender in pairs(AppearanceConfig.PED_MODELS) do
  PED_MODEL_FOR_GENDER[gender] = model
end

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
-- GTA component IDs (PV_COMP_*). 0..4 are obvious; 5..11 are the ones
-- that get confused. The mapping is fixed by the engine, so a wrong
-- index addresses the wrong component - the label can move, the
-- index cannot. 5 hand=backpack, 6 feet=shoes, 7 teef=parachute,
-- 8 accs=accessories, 9 task=armor, 10 decl=emblems, 11 jbib=jacket.
-- GTA only has slots 0..11 (PV_COMP_MAX = 11). Anything above that
-- would be the engine reading garbage; we trust the engine to never
-- hand us one.
local COMPONENT_LABELS = {
  [0]  = 'Kopf',
  [1]  = 'Gesicht',
  [2]  = 'Haare',
  [3]  = 'Oberteil',
  [4]  = 'Hose',
  [5]  = 'Tasche',
  [6]  = 'Schuhe',
  [7]  = 'Fallschirm',
  [8]  = 'Accessoires',
  [9]  = 'Ruestung',
  [10] = 'Abzeichen',
  [11] = 'Jacke',
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

--- Re-spawn the ped on its model, which resets it to that model's defaults. Used on
--- open and on Zurücksetzen.
---
--- Changing the model invalidates the old ped handle, so every later
--- `PlayerPedId()` in this file must be re-fetched rather than taken from a cache.
---
--- Three layers before SetPlayerModel. The third is the one that was
--- missing: even after \`joaat\` resolves the name and \`IsModelInCdimage\`
--- confirms the asset is registered, the model is NOT in the streaming
--- system until \`RequestModel\` runs AND finishes loading. Calling
--- SetPlayerModel before \`HasModelLoaded\` returns true is a hard client
--- crash on most FXServer builds - the model is not yet in memory.
---
--- 1. \`joaat(name)\` returns 0 for an unregistered name. Typo / obsolete.
--- 2. \`IsModelInCdimage(hash)\` confirms the asset is in the content
---    data, just not yet loaded into memory.
--- 3. \`RequestModel(hash)\` + a short blocking wait on
---    \`HasModelLoaded(hash)\` actually pulls the model into memory.
--- A 5s timeout on the wait bails out if the streaming system refuses
--- to load (network stall, sandbox), so the creator never hangs.
---
--- The creator UI stays usable in every failure mode - the camera, the
--- menu, the slot discovery - just without the model preview.
local function respawnModel()
  local hash = joaat(currentModel)
  if not hash or hash == 0 then
    print(('[%s] respawnModel: model "%s" not registered, skipping SetPlayerModel'):format(RESOURCE, tostring(currentModel)))
    return PlayerPedId()
  end
  if not IsModelInCdimage(hash) then
    print(('[%s] respawnModel: model "%s" (0x%x) not in cdimage, skipping SetPlayerModel'):format(RESOURCE, currentModel, hash))
    return PlayerPedId()
  end

  RequestModel(hash)
  local deadline = GetGameTimer() + 5000
  while not HasModelLoaded(hash) do
    Wait(0)
    if GetGameTimer() > deadline then
      print(('[%s] respawnModel: model "%s" (0x%x) failed to load in 5s, skipping SetPlayerModel'):format(RESOURCE, currentModel, hash))
      return PlayerPedId()
    end
  end

  SetPlayerModel(PlayerId(), hash)
  SetModelAsNoLongerNeeded(hash)
  return PlayerPedId()
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

-- Skin cam: tight face closeup with a small lerp in/out.
-- Mirrors lbg-char's CreateSkinCam. Activated when the player enters
-- a category menu (face features, hair, etc.) and dismissed on return
-- to the root.
local skinCam = nil

-- Skin-cam coordinates. The player is parked at CreatorScene, so the
-- skin cam is placed a short distance in front of the head, looking back.
-- The head bone is at +0.65 Z relative to the ped origin; aim there.
local function atSkin(distance, height, fov)
  local scene = CreatorScene
  local headingRad = scene.heading * math.pi / 180.0
  local dirX = math.cos(headingRad)
  local dirY = math.sin(headingRad)
  local camX = scene.x + dirX * distance
  local camY = scene.y + dirY * distance
  local camZ = scene.z + height
  return CreateCamWithParams(
    'DEFAULT_SCRIPTED_CAMERA',
    camX, camY, camZ,
    0.0, 0.0, (scene.heading or 0.0) + 180.0,
    fov, false, 0
  )
end

-- Assigns to the forward declaration at the top of the file, NOT a new local:
-- Menu.menu() calls this before we reach this line. See the note there.
function showSkinCam(kind)
  -- kind: 'face' = tight head closeup, 'body' = working close-up
  local spec = (kind == 'face')
    and { dist = 0.6, h = 0.65, fov = 18.0 }
    or  { dist = 2.0, h = 1.4,  fov = 35.0 }
  if skinCam then
    -- Lerp to the new skin-cam position.
    local next = atSkin(spec.dist, spec.h, spec.fov)
    PointCamAtEntity(next, PlayerPedId(), 0.0, 0.65, 0.0, true)
    SetCamActiveWithInterp(next, skinCam, 250, true, true)
    DestroyCam(skinCam, false)
    skinCam = next
  else
    skinCam = atSkin(spec.dist, spec.h, spec.fov)
    PointCamAtEntity(skinCam, PlayerPedId(), 0.0, 0.65, 0.0, true)
    if creatorCam then
      SetCamActiveWithInterp(skinCam, creatorCam, 250, true, true)
    else
      SetCamActive(skinCam, true)
      RenderScriptCams(true, false, 2000, true, true)
    end
    -- The render thread drives creatorCam; once skinCam is active we
    -- treat the body close-up as paused and the player uses Q/E / edges
    -- to frame the face.
    creatorCam = skinCam
  end
end

local function hideSkinCam()
  if not skinCam then return end
  DestroyCam(skinCam, false)
  skinCam = nil
end

-- Zoom in / out, in FOV steps. Reached from the root menu rather than a key —
-- see the note there on why the arrow keys were unusable. Assigned rather than
-- `local function` because buildRootMenu, far above, calls it through the
-- forward declaration.
zoomCamera = function(direction)
  if not creatorCam then return end
  camFov = camFov - (CAM_FOV_STEP * direction)
  if camFov < CAM_FOV_MIN then camFov = CAM_FOV_MIN end
  if camFov > CAM_FOV_MAX then camFov = CAM_FOV_MAX end
  SetCamFov(creatorCam, camFov)
end

local function startCamera()
  local scene = CreatorScene
  local headingRad = scene.heading * math.pi / 180.0
  local dirX = math.cos(headingRad)
  local dirY = math.sin(headingRad)

  -- Three-stage flyover to match the GTA Online entry cinematic:
  -- far/high overview -> mid-range -> close-up. Each stage is a
  -- separate scripted cam; SetCamActiveWithInterp blends them so the
  -- cut between cameras is not visible. Total ~2.4s, then the menu
  -- opens (the third stage's position is the working menu camera).
  -- The three-stage flyover (far overview -> mid -> close-up, with the menu
  -- opening only after the last interpolation) was removed on 2026-10-12 at
  -- the owner's request. The working camera is placed directly and the menu
  -- opens on it.
  --
  -- The screen is still held black by nifty-core's pre-welcome hook, so the
  -- fade-in stays here, and firing is still disabled so a player cannot shoot
  -- themselves while posing.

  DoScreenFadeIn(500)
  DisablePlayerFiring(PlayerId(), true)

  creatorCam = CreateCamWithParams(
    'DEFAULT_SCRIPTED_CAMERA',
    scene.x + dirX * 2.0,
    scene.y + dirY * 2.0,
    scene.z + 1.4,
    -5.0, 0.0, (scene.heading or 0.0),
    35.0, false, 0
  )
  PointCamAtEntity(creatorCam, PlayerPedId(), 0.0, 0.0, 0.0, true)
  SetCamActive(creatorCam, true)
  RenderScriptCams(creatorCam, true, false, 0)

  openRoot()
end

local function stopCamera()
  hideSkinCam()
  if creatorCam then
    RenderScriptCams(creatorCam, false, false, 0)
    DestroyCam(creatorCam, true)
    creatorCam = nil
  end
  DisablePlayerFiring(PlayerId(), false)
end

--- Camera control is in the menu render thread (the other Citizen.CreateThread
--- near the bottom of the file). Q / E turn the camera around the
--- player; up / down arrow changes the FOV. The previous orbit-style
--- thread (A/D yaw, W/S pitch, Q/E distance) was removed when the user
--- asked for the simpler Q/E + arrow scheme - two threads reading the
--- same keys would fight each other on every frame.

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
  [11] = 'Körperpickel',
  [12] = 'Körperpickel (additiv)',
}

--- Face sliders 0..19. The engine gives them no names worth shipping; the player
--- sees a number, which is what every creator shows anyway.
local FEATURE_SLIDER_MIN = -1.0
local FEATURE_SLIDER_MAX = 1.0

--- The hair colour palette (used by the colour picker on the hair row).
local HAIR_PALETTE = {
  { 28,  31,  33,  255 },  { 39,  42,  44,  255 },  { 49,  46,  44,  255 },
  { 53,  38,  28,  255 },  { 75,  50,  31,  255 },  { 92,  59,  36,  255 },
  { 109, 76,  53,  255 },  { 107, 80,  59,  255 },  { 118, 92,  69,  255 },
  { 127, 104, 78,  255 },  { 153, 129, 93,  255 },  { 167, 147, 105, 255 },
  { 175, 156, 112, 255 },  { 187, 160, 99,  255 },  { 214, 185, 123, 255 },
  { 218, 195, 142, 255 },  { 159, 127, 89,  255 },  { 132, 80,  57,  255 },
  { 104, 43,  31,  255 },  { 97,  18,  12,  255 },  { 100, 15,  10,  255 },
  { 124, 20,  15,  255 },  { 160, 46,  25,  255 },  { 182, 75,  40,  255 },
  { 162, 80,  47,  255 },  { 170, 78,  43,  255 },  { 98,  98,  98,  255 },
}

--- Shared colour-channel builder for hair colour panels.
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
    and { collection = collection, preset = preset, opacity = face.hairOverlay and face.hairOverlay.opacity or 1.0 }
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

--- Removed: colourCount() / overlayStyleCount(). The NUI uses
--- AppearanceConfig.MAX_OVERLAY_STYLE directly.

--- Removed: colourCount(). buildOverlayMenu and buildHairColourMenu
--- now use #HAIR_PALETTE / #MAKEUP_PALETTE directly, and OVERLAY_PALETTES
--- for the per-overlay palette list. No engine lookup needed.

--- colourCount() definition removed in favour of the static palette
--- sizes baked into HAIR_PALETTE / MAKEUP_PALETTE at the top of the file.


-- ---------------------------------------------------------------- actions

-- openRoot was the entry point for the legacy NativeUI root menu. The NUI
-- driver (cl_nui.lua) now opens the root panel directly via `action: 'open'`,
-- so openRoot is a no-op kept for API compatibility. If a future caller wants
-- to re-trigger the root panel from the Lua side, they can call the NUI
-- directly; this function intentionally does nothing.
openRoot = function()
  -- no-op: NUI is the source of truth for what panel is shown.
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
        end
      end
    end
  end

end

--- Roll every choice the creator exposes: outfit, face features, overlays,
--- hair colour, eye colour, parents and weights, skin tone. Tattoos are
--- left alone - the player has usually picked them by hand.
randomiseAll = function()
  -- Outfit
  selection = { components = {}, props = {} }
  local dressProps = (math.random(1, 4) == 1)
  for kind, options in pairs(slots) do
    for id, list in pairs(options) do
      if (kind == 'props') == dressProps or math.random(1, 3) ~= 1 then
        local chosen = list[math.random(#list)]
        if chosen then
          selection[kind][tostring(id)] = {
            collection = chosen.name,
            drawable   = math.random(0, chosen.drawables - 1),
            texture    = math.random(0, chosen.textures - 1),
          }
        end
      end
    end
  end

  -- Face features: three-weight distribution, mostly mild with a few extremes.
  face.features = {}
  for id = 0, AppearanceConfig.MAX_FACE_FEATURE do
    local r = math.random()
    local v
    if r < 0.7 then v = (math.random() - 0.5) * 0.6
    elseif r < 0.9 then v = (math.random() - 0.5) * 1.6
    else v = (math.random() - 0.5) * 2.0 end
    if math.abs(v) < 0.05 then face.features[tostring(id)] = nil
    else face.features[tostring(id)] = v end
  end

  -- Overlays
  face.overlays = {}
  for id = AppearanceConfig.MIN_OVERLAY_ID, AppearanceConfig.MAX_OVERLAY_ID do
    if math.random(1, 2) == 1 then
      face.overlays[tostring(id)] = {
        style = 0, opacity = 0.0, colourType = 1, colour = 0, secondColour = 0,
      }
    else
      local maxStyle = overlayStyleCount(id)
      local palettes = OVERLAY_PALETTES[id]
      local colourType = 1
      local palette = HAIR_PALETTE
      if palettes and palettes[1] then
        colourType = palettes[1][1]
        palette = palettes[1][3]
      end
      face.overlays[tostring(id)] = {
        style = math.random(0, maxStyle),
        opacity = 0.4 + math.random() * 0.6,
        colourType = colourType,
        colour = math.random(0, #palette - 1),
        secondColour = 0,
      }
    end
  end

  face.hairColour = {
    primary = math.random(0, #HAIR_PALETTE - 1),
    highlight = (math.random(1, 3) <= 1) and math.random(0, #HAIR_PALETTE - 1) or 0,
  }
  face.eyeColour = math.random(0, REALISTIC_EYE_COLOUR_MAX)

  -- Parents and weights, renormalised to a proper ratio.
  local mw = math.random()
  local fw = math.random()
  local tw = math.random() * 0.2
  local wsum = mw + fw + tw
  if wsum > 0 then mw, fw, tw = mw / wsum, fw / wsum, tw / wsum end
  face.headBlend = {
    mother = math.random(0, MOTHER_COUNT - 1),
    father = math.random(0, FATHER_COUNT - 1),
    third  = math.random(0, AppearanceConfig.MAX_HEADBLEND_PRESET),
    motherWeight = mw,
    fatherWeight = fw,
    thirdWeight  = tw,
    skinTone = math.random(),
  }

  refresh()
  applyDecorations()
  resolveHairOverlay()
  applyDecorations()

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
  Menu.closeMenu(RESOURCE, reason or 'closed')
end

exports('openCreator', function(data)
  if creatorOpen then return end
  creatorOpen = true

  -- Dismiss the FiveM loading overlay the instant the character creator
  -- appears on screen. Without this the spinner persists indefinitely.
  ShutdownLoadingScreen()

  -- The model comes from the gender the SERVER sent, not from a picker. A player
  -- does not choose a ped model; the character has one, the website recorded which,
  -- and offering a free choice here would be offering a choice the server silently
  -- overrides.
  local gender = (type(data) == 'table' and data.gender) or 'male'
  characterGender = gender
  local derived = PED_MODEL_FOR_GENDER[gender]

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
  print(('[%s] openCreator: parked player at scene.x=%.2f y=%.2f z=%.2f heading=%.2f'):format(RESOURCE, scene.x, scene.y, scene.z, scene.heading))

  respawnModel()
  discoverSlots()
  print(('[%s] openCreator: post-discoverSlots components=%d props=%d'):format(
    RESOURCE,
    slots.components and (function() local n=0; for _ in pairs(slots.components) do n=n+1 end; return n end)() or 0,
    slots.props and (function() local n=0; for _ in pairs(slots.props) do n=n+1 end; return n end)() or 0))
  startCamera()
  openRoot()
end)

exports('closeCreator', function(reason)
  closeCreator(reason or 'closed')
end)

exports('isCreatorOpen', function() return creatorOpen end)

-- =================================================================
-- NUI BRIDGE EXPORTS
-- =================================================================
-- These exports are consumed by client/cl_nui.lua. They are thin
-- adapters that call into the existing private helpers (setFeature,
-- setSlot, etc.) and return the new state for the NUI to consume.
-- They are added without removing the legacy NativeUI surface;
-- removal happens in a later PR.
-- =================================================================

-- State snapshot. The NUI keeps its own copy of this for fast
-- render. Returns the bare tables the NUI needs; engine internals
-- (slots, hairOverlayState, etc.) are included.
exports('getState', function()
  return {
    currentModel     = currentModel,
    characterGender  = characterGender,
    scene            = CreatorScene,
    selection        = selection,
    face             = face,
    slots            = slots,
    labels           = Labels,
    palettes         = {
      HAIR_PALETTE     = HAIR_PALETTE,
      MAKEUP_PALETTE   = MAKEUP_PALETTE,
      OVERLAY_PALETTES = OVERLAY_PALETTES,
    },
    faceGroups       = {
      FACE_1D = FACE_1D_GROUPS,
      FACE_2D = FACE_2D_GROUPS,
    },
    parentNames      = {
      mother = Labels.MOTHER_NAMES,
      father = Labels.FATHER_NAMES,
    },
    componentLabels  = COMPONENT_LABELS,
    propLabels       = PROP_LABELS,
    overlayLabels    = OVERLAY_LABELS,
    zoneLabels       = ZONE_LABELS,
    maxTexture       = AppearanceConfig and AppearanceConfig.MAX_TEXTURE or 80,
    hairOverlayState = hairOverlayState,
    modelIsUndecided = modelIsUndecided,
    skinCam          = skinCam and 'face' or 'body',
  }
end)

exports('setFeature', function(id, value)
  if type(id) ~= 'number' then return end
  -- Sparse: a face with all zeros round-trips identically to a face
  -- with no entries. Mirror the existing setFeature logic from
  -- buildFaceMenu.
  if value == nil or math.abs(value) < 0.001 then
    face.features[tostring(id)] = nil
  else
    face.features[tostring(id)] = math.max(-1.0, math.min(1.0, value))
  end
  refresh()
end)

exports('setSlot', function(kind, id, slot)
  if type(kind) ~= 'string' or type(id) ~= 'number' or type(slot) ~= 'table' then return end
  selection[kind][tostring(id)] = {
    collection = slot.collection,
    drawable   = tonumber(slot.drawable) or 0,
    texture    = tonumber(slot.texture) or 0,
  }
  refresh()
end)

exports('setOverlay', function(id, overlay)
  if type(id) ~= 'number' or type(overlay) ~= 'table' then return end
  face.overlays[tostring(id)] = {
    style        = tonumber(overlay.style) or 0,
    opacity      = math.max(0, math.min(1, tonumber(overlay.opacity) or 0)),
    colourType   = tonumber(overlay.colourType) or 1,
    colour       = tonumber(overlay.colour) or 0,
    secondColour = tonumber(overlay.secondColour) or 0,
  }
  refresh()
end)

exports('setHairColour', function(channel, index)
  if type(channel) ~= 'string' or type(index) ~= 'number' then return end
  if channel ~= 'primary' and channel ~= 'highlight' then return end
  face.hairColour[channel] = index
  -- Native call mirrors the old per-channel OnListChanged path.
  SetPedHairColor(PlayerPedId(), face.hairColour.primary or 0, face.hairColour.highlight or 0)
  refresh()
end)

exports('setHairOverlayOpacity', function(opacity)
  if type(opacity) ~= 'number' then return end
  if not face.hairOverlay then
    face.hairOverlay = { collection = 0, preset = 0, opacity = 1.0 }
  end
  face.hairOverlay.opacity = math.max(0, math.min(1, opacity))
  resolveHairOverlay()
  refresh()
end)

exports('setEyeColour', function(index)
  if type(index) ~= 'number' then return end
  face.eyeColour = index
  if type(SetPedEyeColor) == 'function' then
    SetPedEyeColor(PlayerPedId(), index)
  end
  refresh()
end)

exports('setHeadBlend', function(patch)
  if type(patch) ~= 'table' then return end
  for k, v in pairs(patch) do
    face.headBlend[k] = v
  end
  refresh()
end)

exports('camYaw', function(delta)
  if type(delta) ~= 'number' or not creatorCam then return end
  local ok, cx, cy, cz = pcall(GetCamCoord, creatorCam)
  if not ok or type(cx) ~= 'number' then return end
  local ped = PlayerPedId()
  local head = GetEntityCoords(ped)
  local dx, dy = cx - head.x, cy - head.y
  local rad = math.atan2(dy, dx) + math.rad(delta)
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 0.01 then dist = 0.6 end
  SetCamCoord(creatorCam, head.x + math.cos(rad) * dist, head.y + math.sin(rad) * dist, cz)
  PointCamAtEntity(creatorCam, ped, 0.0, 0.65, 0.0, true)
end)

exports('zoomCamera', function(direction)
  zoomCamera(direction)
end)

exports('pickModel', function(model)
  if type(model) ~= 'string' then return end
  currentModel = model
  characterGender = (model == 'mp_f_freemode_01') and 'female' or 'male'
  modelIsUndecided = false
  respawnModel()
  discoverSlots()
  resolveHairOverlay()
  applyDecorations()
  refresh()
end)

exports('pickTattoo', function(zoneId, collection, preset)
  if type(zoneId) ~= 'number' or type(collection) ~= 'string' or type(preset) ~= 'number' then return end
  local kept = {}
  for _, other in ipairs(face.tattoos) do
    if other.zoneId ~= zoneId then kept[#kept + 1] = other end
  end
  if #kept < AppearanceConfig.MAX_TATTOOS then
    kept[#kept + 1] = { collection = collection, preset = preset, zoneId = zoneId }
    face.tattoos = kept
    applyDecorations()
  end
  refresh()
end)

exports('removeTattoo', function(zoneId)
  if type(zoneId) ~= 'number' then return end
  local kept = {}
  for _, other in ipairs(face.tattoos) do
    if other.zoneId ~= zoneId then kept[#kept + 1] = other end
  end
  face.tattoos = kept
  applyDecorations()
  refresh()
end)

-- The NUI requests per-overlay palette swap. Overlay 4 (Makeup) has
-- two palettes; the menu rebuilds itself when the player picks
-- the other. Mirror the path in buildOverlayMenu lines 1268-1283.
exports('swapOverlayPalette', function(id, paletteIndex)
  if type(id) ~= 'number' or type(paletteIndex) ~= 'number' then return end
  local palettes = OVERLAY_PALETTES[id]
  if not palettes or #palettes < 2 then return end
  local entry = palettes[math.max(1, math.min(#palettes, paletteIndex))]
  local cur = face.overlays[tostring(id)] or { style = 0, opacity = 1.0, colour = 0, secondColour = 0 }
  cur.colourType = entry[1]
  cur.colour = 0
  cur.secondColour = 0
  face.overlays[tostring(id)] = cur
  refresh()
end)

-- Lazy fetches. The NUI requests these on first expand of a submenu.
exports('getTattooZones', function()
  if not GameData or type(GameData.tattooZones) ~= 'function' then return {} end
  return GameData.tattooZones()
end)

exports('getTattoosByZone', function(zoneId)
  if not GameData or type(GameData.tattoosByZone) ~= 'function' then return {} end
  if type(zoneId) ~= 'number' then return {} end
  return GameData.tattoosByZone(zoneId)
end)

-- Item-name prefetch for a slot. Returns a table
-- { drawables = N, textures = M, names = { [drawable] = { [texture] = 'Localized' } } }
-- for the first collection of the requested slot. The NUI uses this
-- to label Modell/Ausfuehrung rows with their real German name from
-- the engine data, instead of "Modell N" / "Ausfuehrung N".
exports('getItemNames', function(kind, id)
  if type(id) ~= 'number' then return nil end
  local isProp = (kind == 'props')
  if not isProp and kind ~= 'components' then return nil end
  local slot = (state.slots[kind] or {})[tostring(id)]
  if not slot or #slot == 0 then return nil end
  local option = slot[1]
  local drawables = option.drawables or 0
  local textures = math.max(1, option.textures or 0)
  local out = { drawables = drawables, textures = textures, names = {} }
  for d = 0, drawables - 1 do
    out.names[d] = {}
    for t = 0, textures - 1 do
      local n = GameData.itemName(isProp, id, option.name, d, t, drawables)
      if n then out.names[d][t] = n end
    end
  end
  return out
end)

-- Bone-projection stub: returns an empty list until the project is
-- complete. Each entry would be { name = 'left_cheek', x = 0.42, y = 0.71 }
-- in 0..1 normalised screen coords. The NUI positions gold dots
-- over the camera viewport using these coords.
exports('projectFaceBones', function()
  if not creatorCam then return {} end
  local ped = PlayerPedId()
  if not ped or ped == 0 then return {} end
  local out = {}
  for _, boneName in ipairs(FACE_BONE_NAMES) do
    local boneIdx = GetEntityBoneIndexByName(ped, boneName)
    if boneIdx and boneIdx ~= -1 then
      local wx, wy, wz = GetWorldPositionOfEntityBone(ped, boneIdx)
      if wx and wy then
        local sx, sy = GetScreenCoordFromWorldCoord(wx, wy, wz)
        if sx and sy then out[#out + 1] = { name = boneName, x = sx, y = sy } end
      end
    end
  end
  return out
end)

-- Parent-portrait stub. V1: SVG silhouette encoded as base64 data
-- URI, so the NUI can render it without an image file. V2 swaps
-- this for a TakeScreenshot of a hidden ped.
exports('captureParentPortrait', function(slot)
  if slot ~= 'mother' and slot ~= 'father' then return '' end
  -- 96x96 transparent placeholder PNG. Real implementation spawns a
  -- hidden clone, sets head blend to the chosen preset, screenshots,
  -- and returns base64. The placeholder keeps the NUI happy.
  return SILHOUETTE_PLACEHOLDER_BASE64
end)

-- Skin-cam switcher; re-uses the existing private function.
exports('showSkinCam', function(kind)
  if kind ~= 'face' and kind ~= 'body' then return end
  showSkinCam(kind)
end)

-- ---------------------------------------------------------------- results

RegisterNetEvent('nifty:client:enterWorld', function()
  closeCreator('submitted')
end)

RegisterNetEvent('nifty:client:creatorError', function(message)
  -- The creator deliberately stays open: the player has to be able to press Fertig
  -- again, and closing on an error would turn "try once more" into "start over".
  print(('[%s] creator refused: %s'):format(RESOURCE, tostring(message)))
end)
-- ---------------------------------------------------------------- render thread
--
-- NativeUI menus need ProcessControl / ProcessMouse / Draw every frame.
-- MenuPool:ProcessMenus() runs all three in the documented order. The
-- lbg-char reference uses the same single-line pattern.
--
-- This thread is the only place the menu library's render loop runs in
-- this resource. nifty-ui runs a parallel thread for its own pool (used
-- by wardrobe, store, spawn) - two pools, two threads, no interference
-- because they draw to separate UIMenu instances.
-- The creator's working camera. startCamera() captures it; we read
-- it through the module-level creatorCam global so the thread sees
-- the right cam without a separate tracking variable.
-- Turn and zoom state for the working camera. Yaw is the heading the
-- player is looking at (degrees, GTA's right-handed convention); each Q
-- or E press adds or subtracts exactly one degree. Zoom is the FOV;
-- smaller = closer, larger = further. Both clamped.
local camYaw = 0.0
-- Assigned, not declared: zoomCamera is defined ABOVE here and reads all four,
-- so they are the forward declarations made near the top of the file. Declaring
-- them `local` again at this line would shadow them and zoomCamera would reach
-- for globals — the same trap as showSkinCam.
camFov = 50.0
CAM_FOV_MIN   = 15.0
CAM_FOV_MAX   = 75.0
CAM_FOV_STEP  = 12.0  -- FOV delta per menu press
-- CAM_EDGE_DEG_PER_SEC went with the mouse-edge auto-rotation. See the note at
-- the place it used to run.

-- Mouse lock + camera turn + zoom, all in the same render tick that
-- already drives the menu. Q / E turn the camera around the player; up
-- / down zoom in and out. The cursor is constrained to the visible
-- menu's drawn rectangle so it cannot wander off into the world and
-- accidentally interact with something the menu does not control.

