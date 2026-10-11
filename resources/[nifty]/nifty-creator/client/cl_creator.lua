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
local _pool = NativeUI.CreatePool()
_pool:MouseControlsEnabled(true)
_pool:ControlDisablingEnabled(true)

local Menu = {}

function Menu.menu(spec)
  spec = spec or {}
  -- dock: 'right' pushes the panel to the right side of the screen so the
  -- player's character stays visible in the middle. NativeUI's CreateMenu
  -- does not honour `dock`, so we translate it to X.
  local x = (spec.dock == 'right') and 1300 or 0
  local m = NativeUI.CreateMenu(
    spec.title or '',
    spec.subtitle or '',
    x, 0,
    'commonmenu', 'interaction_bgd',
    0,
    255, 255, 255, 255
  )
  if type(spec.onClose) == 'function' then
    m.OnMenuClose = function(_) pcall(spec.onClose) end
  end
  -- Mouse at the screen edge rotates the gameplay camera by default in
  -- NativeUI; we want the camera to stay where the Q/E turn and the
  -- face/body switch put it. Disabling this also lets the mouse
  -- stay outside the menu without dragging the world around.
  m.Settings.MouseEdgeEnabled = false
  return m
end

function Menu.separator(menu, label)
  -- MrMathias154's fork does not ship UIMenuSeparatorItem. We approximate
  -- it with a disabled UIMenuItem whose label acts as the section heading.
  -- Visually a grayed-out row rather than a thin line, but it groups the
  -- following items clearly.
  local text = (label and label ~= '') and label or '—'
  local item = NativeUI.CreateItem(text, '')
  item:Enabled(false)
  menu:AddItem(item)
end

function Menu.button(menu, label, spec)
  spec = spec or {}
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  -- NativeUI's UIMenu:SelectItem fires the per-item Activated(menu, item)
  -- for generic UIMenuItem rows (UIMenu.lua:1027).
  item.Activated = function(_, _) pcall(spec.onSelect) end
  menu:AddItem(item)
end

function Menu.submenu(menu, label, spec)
  spec = spec or {}
  -- A submenu is a button whose Activated builds and shows a child UIMenu.
  -- The build function is caller code - no proxy in this resource, so
  -- the menu it returns is a real UIMenu with its metatable intact.
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.Activated = function(_, _)
    if not spec.build then return end
    local child = spec.build()
    if not child or type(child) ~= 'table' then return end
    menu:BindMenuToItem(child, item)
    _pool:Add(child)
    child:Visible(true)
  end
  menu:AddItem(item)
end

function Menu.slider(menu, label, spec)
  spec = spec or {}
  local min = tonumber(spec.min) or 0
  local max = tonumber(spec.max) or 100
  local step = tonumber(spec.step) or 1
  local value = math.floor(((tonumber(spec.value) or min) - min) / step + 0.5) * step + min
  -- NativeUI's UIMenuSliderHeritageItem uses an indexed list, not a
  -- numeric range. We build the synthetic index list of size
  -- (max-min)/step+1 so OnSliderChanged delivers a numeric value.
  local values = {}
  for i = min, max, step do values[#values + 1] = i end
  local index = math.floor((value - min) / step) + 1
  if index < 1 then index = 1 end
  if index > #values then index = #values end
  local item = NativeUI.CreateSliderHeritageItem(
    label or '',
    index, #values,
    spec.description or '',
    { R = 57, G = 119, B = 200, A = 255 },
    { R = 4,  G = 32,  B = 57,  A = 255 }
  )
  if spec.disabled then item:Enabled(false) end
  item.OnSliderChanged = function(_, _, newIndex)
    pcall(spec.onChange, values[newIndex] or value)
  end
  item.OnSliderSelected = function(newIndex)
    pcall(spec.onSelect, values[newIndex] or value)
  end
  menu:AddItem(item)
end

function Menu.select(menu, label, spec)
  spec = spec or {}
  local items = spec.items or {}
  local index = tonumber(spec.index) or 1
  if index < 1 then index = 1 end
  if index > #items then index = math.max(1, #items) end
  local item = NativeUI.CreateListItem(label or '', items, index, spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.OnListChanged = function(_, _, newIndex)
    pcall(spec.onChange, newIndex, items[newIndex])
  end
  item.OnListSelected = function(_, _, newIndex)
    pcall(spec.onSelect, newIndex, items[newIndex])
  end
  menu:AddItem(item)
end

-- Visual colour picker. The row looks like a normal item; activating it
-- expands a UIMenuColourPanel underneath that shows the palette as a
-- strip of swatches with a cursor, plus left/right arrows. Clicking a
-- swatch or pressing left/right changes the selection and fires
-- onChange with the new 1-based index.
--
-- spec: {palette=table of {R,G,B,A}, value=initial 1-based index,
--        panelTitle=optional label inside the panel,
--        onChange=function(colour_1based), description=, disabled=}
function Menu.colourPicker(menu, label, spec)
  spec = spec or {}
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  if type(spec.palette) == 'table' and #spec.palette > 0 then
    local panel = NativeUI.CreateColourPanel(spec.panelTitle or label or 'Farbe', spec.palette)
    -- Set the initial selection WITHOUT firing onChange. The library's
    -- CurrentSelection(value, PreventUpdate) skips UpdateParent when
    -- PreventUpdate is truthy - that is what would otherwise fire the
    -- parent's ActivatedPanel and run the caller's onChange during
    -- construction.
    local initial = tonumber(spec.value) or 1
    if initial < 1 then initial = 1 end
    if initial > #spec.palette then initial = #spec.palette end
    panel:CurrentSelection(initial, true)
    item:AddPanel(panel)
    -- ActivatedPanel is the per-item callback the colour panel calls
    -- on every change. The library passes (menu, item, panel, colour).
    item.ActivatedPanel = function(_, _, _, colour)
      pcall(spec.onChange, colour)
    end
  end
  menu:AddItem(item)
end

-- Visual 1D/2D grid panel. The row looks like a normal item; activating
-- it expands a UIMenuGridPanel / HorizontalOneLine / VerticalOneLine with
-- a 2D / 1D-horizontal / 1D-vertical range indicator and a movable
-- cursor. Arrows or mouse drag move the cursor; every move fires
-- onChange with the new normalised position.
--
-- spec.kind: 'horizontal' (default) | 'vertical' | 'grid'
-- spec.x, spec.y: initial 0..1 cursor position (clamped)
-- spec.left, spec.right, spec.top, spec.bottom: panel direction labels
-- spec.onChange: function(position) - position is {X=0..1} (horizontal),
--                {Y=0..1} (vertical), or {X=0..1, Y=0..1} (grid).
function Menu.gridPanel(menu, label, spec)
  spec = spec or {}
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  local kind = spec.kind or 'horizontal'
  local x = math.max(0, math.min(1, tonumber(spec.x) or 0.5))
  local y = math.max(0, math.min(1, tonumber(spec.y) or 0.5))
  local panel
  if kind == 'grid' then
    panel = NativeUI.CreateGridPanel(
      spec.top or 'Hoch', spec.left or 'Schmal',
      spec.right or 'Breit', spec.bottom or 'Niedrig',
      x, y
    )
  elseif kind == 'vertical' then
    -- Vertical: only top/bottom matter; left/right are placeholders.
    panel = NativeUI.CreateGridPanel(
      spec.top or 'Hoch', '', '', spec.bottom or 'Niedrig',
      0.5, y
    )
  else
    -- Horizontal: only left/right matter; top/bottom are placeholders.
    panel = NativeUI.CreateGridPanel(
      '', spec.left or 'Schmal', spec.right or 'Breit', '',
      x, 0.5
    )
  end
  item:AddPanel(panel)
  item.ActivatedPanel = function(_, _, _, position)
    pcall(spec.onChange, position)
  end
  menu:AddItem(item)
end

function Menu.openMenu(_RESOURCE, menu)
  _pool:Add(menu)
  menu:Visible(true)
  return true
end

function Menu.pushMenu(_RESOURCE, menu)
  for _, other in ipairs(_pool.Menus) do
    if other.Visible then other.Visible(false) end
  end
  _pool:Add(menu)
  menu:Visible(true)
  return true
end

function Menu.closeMenu(_RESOURCE, _reason)
  for _, other in ipairs(_pool.Menus) do
    if other.Visible then other.Visible(false) end
  end
end

function Menu.isOpen()
  for _, other in ipairs(_pool.Menus) do
    if other.Visible then return true end
  end
  return false
end

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

-- Forward declarations. The root menu's rows reference these by closure, and a
-- `local function` is only visible FROM ITS OWN LINE ONWARD - declaring them after
-- `buildRootMenu` would capture a global nil instead, and every row would fail the
-- moment it was pressed. Read top to bottom: a definition must precede its use.
-- slotOf is also forward-declared above (just before GameData.savedSlot)
-- so the savedSlot closure's upvalue is bound to a local.
local buildSlotMenu
local randomise
local randomiseAll
local reset
local submit
local cancel
local buildRootMenu
local closeCreator
local refresh
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
  local headingRad = scene.heading * math.pi / 180.0
  local dirX = math.cos(headingRad)
  local dirY = math.sin(headingRad)

  -- Three-stage flyover to match the GTA Online entry cinematic:
  -- far/high overview -> mid-range -> close-up. Each stage is a
  -- separate scripted cam; SetCamActiveWithInterp blends them so the
  -- cut between cameras is not visible. Total ~2.4s, then the menu
  -- opens (the third stage's position is the working menu camera).
  local function at(distance, height, fov, pitch, yawDelta)
    return CreateCamWithParams(
      'DEFAULT_SCRIPTED_CAMERA',
      scene.x + dirX * distance,
      scene.y + dirY * distance,
      scene.z + height,
      pitch, 0.0, (scene.heading or 0.0) - yawDelta,
      fov, false, 0
    )
  end

  local far = at(scene.camRadius, scene.camHeight, scene.camFarFov, -85.0, 90.0)
  creatorCam = far
  RenderScriptCams(far, true, false, 0)

  -- The screen was held black by nifty-core's pre-welcome hook, which
  -- parked the player at the creator scene before this fires. Fade in
  -- NOW (over the cinematic) so the player sees the flyover start rather
  -- than having the menu pop on a fully-revealed stage.
  DoScreenFadeIn(500)

  -- Firing off so a player cannot shoot themselves while posing.
  DisablePlayerFiring(PlayerId(), true)

  -- Stage 2: mid-range, after the overview settles.
  SetTimeout(scene.camMove, function()
    local mid = at(scene.camRadius * 0.4, scene.camNearZ, scene.camNearFov, -25.0, 60.0)
    PointCamAtCoord(mid, scene.x, scene.y, scene.z + 0.5)
    SetCamActiveWithInterp(mid, far, scene.camInterp, true, true)
    creatorCam = mid

    -- Stage 3: close-up, the working menu camera. After the close-up
    -- finishes its interpolation, open the menu so the player sees
    -- the character from the close-up angle as soon as the menu is
    -- drawn, not from a blank screen.
    SetTimeout(scene.camSettle, function()
      local close = at(2.0, 1.4, 35.0, -5.0, scene.heading - 0.0)
      PointCamAtEntity(close, PlayerPedId(), 0.0, 0.0, 0.0, true)
      SetCamActiveWithInterp(close, mid, 600, true, true)
      creatorCam = close
      openRoot()
    end)
  end)
end

local function stopCamera()
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

--- The makeup colour palette (used by the colour picker on the makeup row).
local MAKEUP_PALETTE = {
  { 240, 200, 195, 255 },  { 220, 170, 165, 255 },  { 200, 140, 130, 255 },
  { 180, 110, 100, 255 },  { 255, 220, 210, 255 },  { 255, 180, 175, 255 },
  { 250, 150, 145, 255 },  { 240, 120, 115, 255 },  { 230, 100, 95,  255 },
  { 220, 80,  75,  255 },  { 200, 60,  55,  255 },  { 180, 40,  35,  255 },
  { 255, 200, 50,  255 },  { 240, 170, 30,  255 },  { 220, 140, 20,  255 },
  { 190, 110, 15,  255 },  { 150, 80,  10,  255 },  { 100, 200, 100, 255 },
  { 60,  160, 60,  255 },  { 30,  120, 30,  255 },  { 100, 180, 220, 255 },
  { 60,  140, 200, 255 },  { 30,  100, 180, 255 },  { 150, 100, 200, 255 },
  { 120, 60,  170, 255 },  { 80,  20,  140, 255 },  { 240, 240, 240, 255 },
}

--- Per-overlay colour-palette table. GTA's _SetPedHeadOverlayColor takes a
--- colourType per overlay: 1 = hair palette, 2 = makeup palette. Most
--- overlays only support one of the two; only Makeup (id 4) supports both.
--- Overlays with no colour at all (blemishes, ageing, complexion, moles, body
--- blemishes) are absent from this table - the Farbe section is omitted.
local OVERLAY_PALETTES = {
  [1]  = { { 1, 'Haarfarbe',     HAIR_PALETTE   } },  -- Bart
  [2]  = { { 1, 'Haarfarbe',     HAIR_PALETTE   } },  -- Augenbrauen
  [4]  = {                                       -- Makeup
    { 1, 'Haarfarbe',     HAIR_PALETTE   },
    { 2, 'Make-up-Farbe', MAKEUP_PALETTE },
  },
  [5]  = { { 2, 'Make-up-Farbe', MAKEUP_PALETTE } },  -- Rouge
  [7]  = { { 1, 'Haarfarbe',     HAIR_PALETTE   } },  -- Sonnenbrand
  [8]  = { { 2, 'Make-up-Farbe', MAKEUP_PALETTE } },  -- Lippenstift
  [10] = { { 1, 'Haarfarbe',     HAIR_PALETTE   } },  -- Brustbehaarung
}

--- Face-feature groups. Each entry pairs two face-feature indices so a single
--- 2D grid panel controls both at once (X = first feature, Y = second).
local FACE_2D_GROUPS = {
  { title = 'Nasenspitze', top = 'Spitz',  bottom = 'Flach',  left = 'Kurz',  right = 'Lang',  xId = 2, yId = 1 },
  { title = 'Augenbrauen', top = 'Hoch',   bottom = 'Tief',   left = 'Flach', right = 'Tief',  xId = 7, yId = 6 },
  { title = 'Wangen',      top = 'Hoch',   bottom = 'Tief',   left = 'Schmal', right = 'Breit', xId = 9, yId = 8 },
  { title = 'Kiefer',      top = 'Tief',   bottom = 'Hervor', left = 'Schmal', right = 'Breit', xId = 13, yId = 14 },
  { title = 'Kinn',        top = 'Hervor', bottom = 'Flach',  left = 'Schmal', right = 'Breit', xId = 17, yId = 15 },
}

--- Face-feature indices that get a 1D horizontal grid panel.
local FACE_1D_GROUPS = {
  { id = 0,  title = 'Nasenbreite',      left = 'Schmal', right = 'Breit' },
  { id = 3,  title = 'Nasenbeinhöhe',   left = 'Tief',   right = 'Hoch'  },
  { id = 4,  title = 'Nasenspitze-Tiefe', left = 'Stumpf', right = 'Spitz' },
  { id = 5,  title = 'Nasenbein-Drehung', left = 'Links', right = 'Rechts' },
  { id = 10, title = 'Wangenspalt',      left = 'Schmal', right = 'Breit' },
  { id = 11, title = 'Augenöffnung',    left = 'Eng',    right = 'Weit'  },
  { id = 12, title = 'Lippendicke',      left = 'Dünn',  right = 'Dick'  },
  { id = 16, title = 'Kinn-Tiefe',       left = 'Flach',  right = 'Hervor' },
  { id = 18, title = 'Kinn-Loch',        left = 'Klein',  right = 'Gross' },
  { id = 19, title = 'Hals-Dicke',       left = 'Dünn',  right = 'Dick'  },
}

--- The 9 realistic eye-colour indices in the GTA palette.
local REALISTIC_EYE_COLOUR_MAX = 8

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
end--- Removed: colourCount(). buildOverlayMenu and buildHairColourMenu
--- now use #HAIR_PALETTE / #MAKEUP_PALETTE directly, and OVERLAY_PALETTES
--- for the per-overlay palette list. No engine lookup needed.

--- colourCount() definition removed in favour of the static palette
--- sizes baked into HAIR_PALETTE / MAKEUP_PALETTE at the top of the file.

--- One overlay: style, opacity, and its two colours.
local function buildOverlayMenu(id)
  -- lbg-char pattern: one CreateListItem per overlay, with style names
  -- as entries. Index 1 is "Keins" (disable: opacity 0). Index 2+ maps to
  -- the engine's style index 0..N. A NativeUI.CreateColourPanel is
  -- attached when the overlay accepts a colour, and a percentage panel
  -- for opacity. The list item's OnListChanged reads both panel values
  -- and the style index, and applies them via SetPedHeadOverlay /
  -- SetPedHeadOverlayColor.
  local label = OVERLAY_LABELS[id] or ('Overlay ' .. id)
  local current = face.overlays[tostring(id)] or {
    style = 0, opacity = 1.0, colourType = 1, colour = 0, secondColour = 0,
  }
  local maxStyle = overlayStyleCount(id)

  local menu = NativeUI.CreateMenu(
    label, 'Stil, Deckkraft und Farbe.', 1300, 0,
    'commonmenu', 'interaction_bgd', 0, 255, 255, 255, 255
  )

  -- The list: index 1 is the off-state, 2..N+1 are the real styles.
  -- OnListChanged gets the 1-based list index.
  local styles = { 'Keins' }
  for i = 0, maxStyle do
    styles[i + 2] = Labels.overlayStyle(id, i + 1)
  end

  -- Pick a reasonable starting list index. A "no overlay" state means
  -- either opacity 0 or style 0 + opacity 0; we land on "Keins" (index 1).
  -- A real style maps to index 2 + style.
  local startIndex = (current.opacity and current.opacity > 0.01) and (current.style + 2) or 1
  if startIndex < 1 then startIndex = 1 end
  if startIndex > #styles then startIndex = #styles end

  local styleItem = NativeUI.CreateListItem(label, styles, startIndex,
    'Stil waehlen. "Keins" schaltet das Merkmal aus.')

  -- Opacity: lbg-char attaches a CreatePercentagePanel alongside the
  -- colour panel. 0% to 100%, integer percent. The value list is
  -- {"0%", "1%", ..., "100%"} so the player sees the percentage.
  local opacityList = {}
  for i = 0, 1000 do opacityList[i + 1] = (i * 0.1 .. '%') end
  local opacityItem = NativeUI.CreateSliderItem('Deckkraft', opacityList,
    math.floor(math.clamp((current.opacity or 1.0) * 1000, 0, 1000)) + 1,
    'Deckkraft in Prozent (0% = aus).', true)
  styleItem:AddPanel(opacityItem)

  -- Colour panel for overlays the engine accepts a colour for. The
  -- current value is clamped into the matching palette; if the stored
  -- colourType is unknown, default to the first palette's first entry.
  local palettes = OVERLAY_PALETTES[id]
  if palettes then
    -- Pick the active palette + index from the current state.
    local activeEntry = palettes[1]
    for _, entry in ipairs(palettes) do
      if entry[1] == current.colourType then activeEntry = entry end
    end
    local activePalette = activeEntry[3]
    local colourIndex = math.floor((current.colour or 0)) + 1
    if colourIndex < 1 then colourIndex = 1 end
    if colourIndex > #activePalette then colourIndex = #activePalette end
    local colourItem = NativeUI.CreateColourPanel(activeEntry[2], activePalette)
    colourItem:CurrentSelection(colourIndex, true)
    styleItem:AddPanel(colourItem)
  end

  -- The lbg-char style: a single OnListChanged on the item reads the
  -- current list index AND the attached panel values, and applies the
  -- whole overlay state in one go. No menu rebuild, no engine calls
  -- scattered across three handlers.
  styleItem.OnListChanged = function(_parent, _item, index)
    if index == 1 then
      -- "Keins" — disable the overlay (style 0, opacity 0, no colour).
      face.overlays[tostring(id)] = {
        style = 0, opacity = 0.0, colourType = 1, colour = 0, secondColour = 0,
      }
    else
      local live = face.overlays[tostring(id)] or {}
      local styleValue = index - 2
      local colourType = (palettes and palettes[1] and palettes[1][1]) or 1
      local colourValue = 0
      if palettes then
        -- Find the panel for the current selection. UIMenuListItem keeps
        -- its attached panels under .Panels; the colour panel's value
        -- is what we want.
        local liveItem = styleItem
        local livePanels = liveItem.Panels
        if livePanels and livePanels[1] then
          -- The colour panel is whichever entry in OVERLAY_PALETTES matches
          -- colourType. All current overlays have a single colour panel.
          colourValue = livePanels[1]:CurrentSelection() - 1
        end
      end
      local opacity = opacityItem:CurrentSelection() / 1000
      face.overlays[tostring(id)] = {
        style = styleValue,
        opacity = opacity,
        colourType = colourType,
        colour = colourValue,
        secondColour = live.secondColour or 0,
      }
    end
    refresh()
  end

  menu:AddItem(styleItem)
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
  -- lbg-char pattern: build the menu and its items directly through
  -- the NativeUI factory calls, wire the events on the menu object
  -- itself (OnListChange, OnSliderChange) rather than per-item, and
  -- update the heritage window in real time. No Menu.pushMenu rebuild
  -- on every change - the only reason the old code rebuilt was to
  -- refresh the subtitle (parentsSummary). The subtitle is set on the
  -- menu once here; subsequent weight changes do not need it.

  local menu = NativeUI.CreateMenu(
    'Eltern', parentsSummary(), 1300, 0,
    'commonmenu', 'interaction_bgd', 0,
    255, 255, 255, 255
  )

  -- Heritage window: the two parent face portraits in the panel header.
  -- heritage:Index(mom, dad) updates the previews.
  local heritage = NativeUI.CreateHeritageWindow(face.headBlend.mother, face.headBlend.father)
  menu:AddWindow(heritage)

  -- The slider's value list, shared by Resemblance and Skin Tone. 101
  -- entries (0.00 to 1.00 in 0.01 steps) for finer granularity than the
  -- 11-entry 0.0..1.0 list. Each entry is a string the library displays
  -- in the bar; the index 1..N is what the OnSliderChange callback sees.
  local ZtO = {}
  for i = 1, 101 do ZtO[i] = ('%.2f'):format((i - 1) / 100) end

  -- 1-based item lists: UIMenuListItem is 1-based, the engine is 0-based.
  -- We carry the same array the engine wants and let OnListChange
  -- convert via index - 1.
  local momItems, dadItems, thirdItems = {}, {}, {}
  for i = 0, MOTHER_COUNT - 1 do momItems[i + 1] = Labels.MOTHER(i) end
  for i = 0, FATHER_COUNT - 1 do dadItems[i + 1] = Labels.FATHER(i) end
  -- Third person: the engine accepts any of the 47 presets as the
  -- third slot; lbg-char lifts the same name list the in-game creator
  -- shows. We expose it through Labels.THIRDPERSON (1-based) and map
  -- to the engine's 0-based index in OnListChanged.
  for i = 1, math.min(#Labels.THIRDPERSON, AppearanceConfig.MAX_HEADBLEND_PRESET + 1) do
    thirdItems[i] = Labels.THIRDPERSON[i]
  end

  local momItem = NativeUI.CreateListItem('Mutter', momItems, (face.headBlend.mother or 0) + 1, 'Wähle die Mutter.')
  local dadItem = NativeUI.CreateListItem('Vater', dadItems, (face.headBlend.father or 0) + 1, 'Wähle den Vater.')
  local thirdItem = NativeUI.CreateListItem('Dritte Person', thirdItems, (face.headBlend.third or 0) + 1,
    'Beliebige weitere Person im Mix.')
  menu:AddItem(momItem)
  menu:AddItem(dadItem)
  menu:AddItem(thirdItem)

  -- One OnListChange for all three list items. The library passes the
  -- item that changed, so we dispatch on identity. Updates the state,
  -- the heritage window, and the engine's head-blend data without a
  -- menu rebuild.
  menu.OnListChange = function(_sender, item, index)
    if item == momItem then
      face.headBlend.mother = index - 1
    elseif item == dadItem then
      face.headBlend.father = index - 1
    elseif item == thirdItem then
      face.headBlend.third = index - 1
    end
    heritage:Index(face.headBlend.mother, face.headBlend.father)
    refresh()
  end

  -- Weights and skin tone: a single OnSliderChange dispatches the index
  -- to the right weight. Slider items use the value-list API (item index
  -- 1..N); we map back to 0..1 via (index - 1) / (N - 1).
  local function frac(index, n) return (index - 1) / (n - 1) end
  local resItem = NativeUI.CreateSliderItem('Ähnlichkeit', ZtO,
    math.floor((face.headBlend.resemblance or 0.5) * 10) + 1,
    'Wie sehr die Merkmale von Mutter oder Vater geprägt sind.', true)

  -- Half-percent granularity on the three weights: 0..100 in 201 steps.
  -- The engine reads the ratio, so storing frac01 keeps the precision;
  -- the right-label shows the percent (0..100, 1 decimal).
  local halfStep = {}
  for i = 0, 1000 do halfStep[i + 1] = ('%.1f%%'):format(i * 0.1) end
  local function halfStepIndex(frac01)
    -- explicit if/else instead of math.clamp: FiveM's runtime Lua
    -- accepts vectors in math.clamp and raises 'number or vector
    -- expected' on a type mismatch, which we hit when frac01 is a
    -- number but the call site accidentally promotes it through a
    -- path that hands math.clamp a vector. Plain clamp here is safer.
    if frac01 < 0 then frac01 = 0 end
    if frac01 > 1 then frac01 = 1 end
    return math.floor(frac01 * 1000) + 1
  end
  local weightDefs = {
    { key = 'motherWeight', label = 'Mutter-Anteil' },
    { key = 'fatherWeight', label = 'Vater-Anteil' },
    { key = 'thirdWeight',  label = 'Anteil dritte Person' },
  }
  local weightMenuItems = {}
  for _, w in ipairs(weightDefs) do
    local item = NativeUI.CreateSliderItem(w.label, halfStep,
      halfStepIndex(face.headBlend[w.key] or 0.0),
      'Anteil an der Mischung. Die drei Werte addieren sich nicht zu 100 - die Engine rechnet mit Verhältnissen.', true)
    weightMenuItems[w.key] = item
    menu:AddItem(item)
  end
  local skinItem = NativeUI.CreateSliderItem('Hautton', ZtO,
    math.floor((face.headBlend.skinTone or 0.5) * 10) + 1,
    'Hautton aus Mutter oder Vater.', true)
  menu:AddItem(skinItem)

  menu.OnSliderChange = function(_sender, item, index)
    if item == resItem then
      face.headBlend.resemblance = frac(index, #ZtO)
    elseif item == weightMenuItems.motherWeight then
      face.headBlend.motherWeight = frac(index, #halfStep)
    elseif item == weightMenuItems.fatherWeight then
      face.headBlend.fatherWeight = frac(index, #halfStep)
    elseif item == weightMenuItems.thirdWeight then
      face.headBlend.thirdWeight = frac(index, #halfStep)
    elseif item == skinItem then
      face.headBlend.skinTone = frac(index, #ZtO)
    end
    refresh()
  end

  -- One-touch weight presets. The slider's OnSliderChange will fire
  -- when :Index() moves the cursor, so the weight values sync through
  -- the regular path - no duplicate state write here.
  for _, preset in ipairs({
    { label = 'Nur Mutter',          w = { 1.0, 0.0, 0.0 } },
    { label = 'Nur Vater',           w = { 0.0, 1.0, 0.0 } },
    { label = 'Nur dritte Person',   w = { 0.0, 0.0, 1.0 } },
    { label = 'Eltern gleich',       w = { 0.5, 0.5, 0.0 } },
    { label = 'Alle drei gleich',    w = { 1 / 3, 1 / 3, 1 / 3 } },
  }) do
    local w = preset.w
    local item = NativeUI.CreateItem(preset.label, 'Anteile setzen.')
    item.Activated = function(_, _)
      weightMenuItems.motherWeight:Index(halfStepIndex(w[1]))
      weightMenuItems.fatherWeight:Index(halfStepIndex(w[2]))
      weightMenuItems.thirdWeight:Index(halfStepIndex(w[3]))
      -- The OnSliderChange handler will fire from the Index() calls and
      -- update face.headBlend.* and refresh. We do not need to do it here.
    end
    menu:AddItem(item)
  end

  return menu
end

--- Eye colour: lbg-char pattern. A single CreateListItem with the 32
--- game colours as entries. The 1-based list index IS the engine colour
--- index. The OnListChanged sets face.eyeColour and pushes to the engine.
local function buildEyeColourMenu()
  local menu = NativeUI.CreateMenu(
    'Augenfarbe', 'Eine von zweiunddreissig Farben.', 1300, 0,
    'commonmenu', 'interaction_bgd', 0, 255, 255, 255, 255
  )

  -- Show only the realistic subset: green, emerald, light/ocean blue,
  -- light/dark brown, hazel, dark/light grey. The remaining 23 indices
  -- are eye-shadow tints and monster eyes (Lizard, Alien, Zombie, ...)
  -- and do not belong in a normal character creator. The full 32 are
  -- still reachable through admin commands; this menu just does not
  -- offer them.
  local realisticCount = REALISTIC_EYE_COLOUR_MAX + 1
  local realisticEyes = {}
  for i = 1, realisticCount do realisticEyes[i] = Labels.EYE_COLOURS[i] end

  local eyeItem = NativeUI.CreateListItem('Augenfarbe', realisticEyes,
    math.min((face.eyeColour or 0) + 1, realisticCount),
    ('Waehle die Augenfarbe. %d realistische Farben (Grün, Smaragd, Blau, Braun, Hazel, Grau).'):format(realisticCount))

  eyeItem.OnListChanged = function(_parent, _item, index)
    face.eyeColour = index - 1
    SetPedEyeColor(PlayerPedId(), face.eyeColour, 0, 1)
    refresh()
  end

  menu:AddItem(eyeItem)
  return menu
end

--- Face features: twenty grid panels. Two-axis face anatomy features
--- share a 2D grid (X = one feature, Y = the other); the rest get a 1D
--- horizontal panel. The cursor position is normalised 0..1; the onChange
--- handler maps it to the engine's -1..1 range.
local function buildFaceMenu()
  -- Grid panels instead of sliders. 2D features (a pair of related
  -- features) get a full 4-direction panel; 1D features (a single
  -- axis) get a horizontal panel. The cursor position is normalised
  -- 0..1; the onChange handler maps it to the engine's -1..1 range.
  local menu = NativeUI.CreateMenu(
    'Gesichtsform', 'Ziehen, um das Gesicht zu formen.', 1300, 0,
    'commonmenu', 'interaction_bgd', 0, 255, 255, 255, 255
  )

  local function setFeature(id, value)
    -- Sparse: an untouched feature is not stored. A ped whose stored
    -- face is full of zeros and a ped whose stored face has no entries
    -- are the same ped, but only one of them round-trips through the
    -- database identically.
    if math.abs(value) < 0.001 then
      face.features[tostring(id)] = nil
    else
      face.features[tostring(id)] = value
    end
  end

  -- Snap the engine's continuous 0..1 cursor to a 0.01 grid. 201 positions
  -- across -1.0..1.0 (0.01 each) is much finer than 21 (0.05) - matches
  -- the 100-step slider precision elsewhere. math.floor((x*2 - 1) * 100
  -- + 0.5) / 100 rounds to the nearest 0.01; the same expression lives
  -- in both the 2D and 1D branches.
  local function toFeature(posX)
    local v = (posX or 0.5) * 2 - 1
    return math.floor(v * 100 + 0.5) / 100
  end

  -- A feature with only two options (value is -1.0 or +1.0) is rendered
  -- as a single horizontal row, not a 2D grid. This keeps tiny two-option
  -- features from appearing as mostly-empty grids.
  local function isBinaryFeature(id)
    local v = face.features[tostring(id)]
    return (v or 0.0) <= -0.99 or (v or 0.0) >= 0.99
  end

  for _, g in ipairs(FACE_2D_GROUPS) do
    local xv = face.features[tostring(g.xId)] or 0.0
    local yv = face.features[tostring(g.yId)] or 0.0
    if isBinaryFeature(g.xId) or isBinaryFeature(g.yId) then
      -- At least one axis has only two options: render both as 1D rows.
      if not isBinaryFeature(g.xId) then
        Menu.gridPanel(menu, g.title, {
          kind = 'horizontal',
          left = g.left, right = g.right,
          x = (xv + 1) / 2,
          onChange = function(pos)
            setFeature(g.xId, toFeature(pos.X))
            refresh()
          end,
        })
      end
      if not isBinaryFeature(g.yId) then
        Menu.gridPanel(menu, g.title, {
          kind = 'horizontal',
          left = g.top, right = g.bottom,
          x = (yv + 1) / 2,
          onChange = function(pos)
            setFeature(g.yId, toFeature(pos.X))
            refresh()
          end,
        })
      end
    else
      Menu.gridPanel(menu, g.title, {
        kind = 'grid',
        top = g.top, bottom = g.bottom, left = g.left, right = g.right,
        x = (xv + 1) / 2, y = (yv + 1) / 2,
        onChange = function(pos)
          setFeature(g.xId, toFeature(pos.X))
          setFeature(g.yId, toFeature(pos.Y))
          refresh()
        end,
      })
    end
  end

  for _, g in ipairs(FACE_1D_GROUPS) do
    local v = face.features[tostring(g.id)] or 0.0
    Menu.gridPanel(menu, g.title, {
      kind = 'horizontal',
      left = g.left, right = g.right,
      x = (v + 1) / 2,
      onChange = function(pos)
        setFeature(g.id, toFeature(pos.X))
        refresh()
      end,
    })
  end

  return menu
end

--- Hair colour: primary and highlight, both from the hair palette.
local function buildHairColourMenu()
  -- lbg-char pattern. A list item per colour channel (primary, highlight).
  -- A NativeUI.CreateColourPanel is attached to each; the OnListChanged
  -- reads the panel's current selection. The list entry names (1..N) are
  -- placeholder labels for the colour index; the panel is what carries
  -- the colour value, not the list.
  local menu = NativeUI.CreateMenu(
    'Haarfarbe', 'Hauptfarbe und Strähnen aus der Haar-Palette.', 1300, 0,
    'commonmenu', 'interaction_bgd', 0, 255, 255, 255, 255
  )

  local function makeChannel(label, currentIndex)
    local max = #HAIR_PALETTE
    local value = math.max(0, math.min(max, currentIndex or 0)) + 1
    local placeholders = {}
    for i = 1, max do placeholders[i] = (i .. '.') end
    local item = NativeUI.CreateListItem(label, placeholders, value, '')
    local panel = NativeUI.CreateColourPanel(label, HAIR_PALETTE)
    panel:CurrentSelection(value, true)
    item:AddPanel(panel)
    return item
  end

  local primaryItem = makeChannel('Hauptfarbe', face.hairColour.primary)
  local highlightItem = makeChannel('Strähnen', face.hairColour.highlight)

  primaryItem.OnListChanged = function(_p, _i, _idx)
    face.hairColour.primary = primaryItem.Panels[1]:CurrentSelection() - 1
    SetPedHairColor(PlayerPedId(), face.hairColour.primary, face.hairColour.highlight or 0)
    refresh()
  end
  highlightItem.OnListChanged = function(_p, _i, _idx)
    face.hairColour.highlight = highlightItem.Panels[1]:CurrentSelection() - 1
    SetPedHairColor(PlayerPedId(), face.hairColour.primary or 0, face.hairColour.highlight)
    refresh()
  end

  menu:AddItem(primaryItem)
  menu:AddItem(highlightItem)
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

  local menu = Menu.menu({
    title = ZONE_LABELS[zoneId] or ('Zone ' .. zoneId),
    subtitle = ('%d Tattoo(s)'):format(#tattoos),
    dock = 'right',
  })

  Menu.button(menu, 'Keins', {
    description = 'Alle Tattoos dieser Zone entfernen.',
    onSelect = function()
      local kept = {}
      for _, tattoo in ipairs(face.tattoos) do
        if tattoo.zoneId ~= zoneId then kept[#kept + 1] = tattoo end
      end
      face.tattoos = kept
      applyDecorations()
      Menu.pushMenu(RESOURCE, buildRootMenu())
    end,
  })

  Menu.separator(menu, ZONE_LABELS[zoneId] or ('Zone ' .. zoneId))

  for _, tattoo in ipairs(tattoos) do
    local entry = tattoo
    Menu.button(menu, entry.name, {
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

        Menu.pushMenu(RESOURCE, buildRootMenu())
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

  -- Use the first collection that has data. The Kollektion list is gone
  -- (lbg-char pattern: just Modell and Ausführung, no DLC picker), and
  -- the engine accepts any drawable/texture index in [0, count) regardless
  -- of which collection it nominally belongs to. A drawable past the
  -- first collection's count is still a valid integer to the engine.
  local option = options[1]
  local drawable = (current and tonumber(current.drawable)) or 0
  local texture = (current and tonumber(current.texture)) or 0
  if drawable >= option.drawables then drawable = option.drawables - 1 end
  if drawable < 0 then drawable = 0 end
  if texture >= option.textures then texture = option.textures - 1 end
  if texture < 0 then texture = 0 end

  local label = isProp
    and (PROP_LABELS[id] or ('Prop ' .. id))
    or  (COMPONENT_LABELS[id] or ('Slot ' .. id))

  local function nameFor(drawableId, textureId)
    return GameData.itemName(isProp, id, option.name, drawableId, textureId, option.drawables)
  end

  local menu = Menu.menu({
    title = label,
    -- Section bar updates to the slot name. 11 is the number of
    -- populated component slots the engine has; 12 is the placeholder.
    section = { name = label, current = 1, total = 11 },
    dock = 'right',
  })

  -- Modell: one list item per drawable. Entry labels are the item
  -- names from the data; the few slots that have no names fall back
  -- to a numbered placeholder so the list is never blank.
  local modelLabels = {}
  for d = 0, option.drawables - 1 do
    local n = nameFor(d, texture)
    modelLabels[d + 1] = n or ('Modell %d'):format(d)
  end
  Menu.select(menu, 'Modell', {
    items = modelLabels,
    index = drawable + 1,
    onChange = function(i)
      local live = slotOf(kind, id) or {}
      setSlot(kind, id, {
        collection = option.name,
        drawable   = i - 1,
        texture    = tonumber(live.texture) or 0,
      })
    end,
  })

  -- Ausführung: one list item per texture. Same naming convention.
  local texLabels = {}
  for t = 0, option.textures - 1 do
    local n = nameFor(drawable, t)
    texLabels[t + 1] = n or ('Ausfuehrung %d'):format(t)
  end
  Menu.select(menu, 'Ausführung', {
    items = texLabels,
    index = texture + 1,
    onChange = function(i)
      local live = slotOf(kind, id) or {}
      setSlot(kind, id, {
        collection = option.name,
        drawable   = tonumber(live.drawable) or 0,
        texture    = i - 1,
      })
    end,
  })

  return menu
end

--- The root menu: one row per available slot, then the actions.
--- Category containers. The root menu lists six of them; each opens
--- a submenu that holds the items for that category. The build
--- functions exist so a submenu can lazy-build the right items, and
--- so an openRoot (Escape from a category) lands back at the root.

local function buildHeritageCategoryMenu()
  local menu = Menu.menu({ title = 'Heritage', dock = 'right' })
  Menu.submenu(menu, 'Eltern', {
    description = 'Vater, Mutter und die Mischungen daraus.',
    build = buildParentsMenu,
  })
  Menu.submenu(menu, 'Augenfarbe', {
    description = 'Eine von neun realistischen Farben.',
    build = buildEyeColourMenu,
  })
  return menu
end

local function buildFaceFeaturesCategoryMenu()
  return buildFaceMenu()
end

local function buildHairCategoryMenu()
  local menu = Menu.menu({ title = 'Haare', dock = 'right' })
  local hairSlot = slots.components[2]
  if hairSlot then
    Menu.submenu(menu, 'Frisur', {
      description = ('Slot 2 - %d Kollektionen'):format(#hairSlot),
      build = function() return buildSlotMenu('components', 2) end,
    })
  end
  Menu.submenu(menu, 'Haarfarbe', {
    description = 'Hauptfarbe und Strähnen.',
    build = buildHairColourMenu,
  })
  return menu
end

local function buildMakeupCategoryMenu()
  local menu = Menu.menu({ title = 'Makeup', dock = 'right' })
  for id = AppearanceConfig.MIN_OVERLAY_ID, 9 do
    Menu.submenu(menu, OVERLAY_LABELS[id] or ('Overlay ' .. id), {
      description = 'Stil, Deckkraft und Farbe.',
      build = function() return buildOverlayMenu(id) end,
    })
  end
  return menu
end

local function buildOutfitCategoryMenu()
  local menu = Menu.menu({ title = 'Outfit', dock = 'right' })

  Menu.separator(menu, 'Kleidung')
  local componentIds = {}
  for id in pairs(slots.components) do componentIds[#componentIds + 1] = id end
  table.sort(componentIds)
  for _, id in ipairs(componentIds) do
    if id ~= 2 then  -- slot 2 is hair, in the Haare category
      Menu.submenu(menu, COMPONENT_LABELS[id] or ('Slot ' .. id), {
        description = ('Slot %d - %d Kollektionen'):format(id, #slots.components[id]),
        build = function() return buildSlotMenu('components', id) end,
      })
    end
  end

  local propIds = propIdsSorted()
  if #propIds > 0 then
    Menu.separator(menu, 'Accessoires')
    for _, id in ipairs(propIds) do
      Menu.submenu(menu, PROP_LABELS[id] or ('Prop ' .. id), {
        description = ('Prop %d - %d Kollektionen'):format(id, #slots.props[id]),
        build = function() return buildSlotMenu('props', id) end,
      })
    end
  end

  -- Body overlays sit in Outfit, not Makeup, because they decorate the
  -- body, not the face. The hair overlay is NOT here - the game ties
  -- exactly one decal to each hairstyle, so picking the hair picks the
  -- overlay. A list to choose from would offer a combination the game
  -- has no way to draw.
  for id = 10, AppearanceConfig.MAX_OVERLAY_ID do
    Menu.submenu(menu, OVERLAY_LABELS[id] or ('Overlay ' .. id), {
      description = 'Stil und Deckkraft.',
      build = function() return buildOverlayMenu(id) end,
    })
  end

  return menu
end

local function buildTattooCategoryMenu()
  local menu = Menu.menu({ title = 'Tattoos', dock = 'right' })
  local tattooZones = GameData.tattooZones()
  for _, zoneId in ipairs(tattooZones) do
    Menu.submenu(menu, ZONE_LABELS[zoneId] or ('Zone ' .. zoneId), {
      description = ('%d Tattoo(s)'):format(#GameData.tattoosByZone(zoneId)),
      build = function() return buildTattooMenu(zoneId) end,
    })
  end
  return menu
end

--- The root menu: six category buttons, then the actions.
buildRootMenu = function()
  local menu = Menu.menu({
    title    = 'Charakter erstellen',
    subtitle = 'Aussehen - Name und Stammdaten stehen bereits fest.',
    dock     = 'right',
    section  = { name = 'Uebersicht', current = 1, total = 6 },
    onClose  = function(reason)
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
    Menu.separator(menu, 'Modell')
    for _, entry in ipairs({ { 'mp_m_freemode_01', 'Männlich' },
                             { 'mp_f_freemode_01', 'Weiblich' } }) do
      Menu.button(menu, entry[2], {
        description = 'Freemode-Modell wählen.',
        onSelect = function()
          currentModel = entry[1]
          modelIsUndecided = false
          characterGender = (entry[1] == 'mp_f_freemode_01') and 'female' or 'male'
          GameData.setGender(characterGender)
          respawnModel()
          discoverSlots()
          resolveHairOverlay()
          applyDecorations()          Menu.pushMenu(RESOURCE, buildRootMenu())
        end,
      })
    end
  end

  Menu.separator(menu, 'Kategorien')

  Menu.submenu(menu, 'Heritage', {
    description = 'Eltern und Augenfarbe.',
    build = buildHeritageCategoryMenu,
  })
  Menu.submenu(menu, 'Gesichtszüge', {
    description = 'Nasen, Wangen, Kinn, Brauen, ...',
    build = buildFaceFeaturesCategoryMenu,
  })
  Menu.submenu(menu, 'Haare', {
    description = 'Frisur und Haarfarbe.',
    build = buildHairCategoryMenu,
  })
  Menu.submenu(menu, 'Makeup', {
    description = 'Bart, Augenbrauen, Makeup, Lippenstift, ...',
    build = buildMakeupCategoryMenu,
  })
  Menu.submenu(menu, 'Tattoos', {
    description = 'Nach Koerperzone gruppiert.',
    build = buildTattooCategoryMenu,
  })
  Menu.submenu(menu, 'Outfit', {
    description = 'Kleidung, Accessoires, Koerper-Overlays.',
    build = buildOutfitCategoryMenu,
  })

  Menu.separator(menu, 'Aktionen')

  Menu.button(menu, 'Zufallsaufzug', {
    description = 'Zufaellige Kleidung. A/D dreht die Kamera.',
    onSelect = function() randomise() end,
  })

  Menu.button(menu, 'Zufallschar', {
    description = 'Outfit, Gesicht, Haare, Eltern - alles auf einmal.',
    onSelect = function() randomiseAll() end,
  })

  Menu.button(menu, 'Zurücksetzen', {
    description = 'Alle Auswähle verwerfen und das Modell neu laden.',
    onSelect = function() reset() end,
  })

  Menu.button(menu, 'Fertig', {
    description = 'Aussehen speichern und die Welt betreten.',
    onSelect = function() submit() end,
  })

  Menu.button(menu, 'Abbrechen', {
    description = 'Verlassen. Beim nächsten Verbinden geht es hier weiter.',
    onSelect = function() cancel() end,
  })

  print(('[nifty-creator] buildRootMenu: exit, items=%d'):format(#menu.Items))
  return menu
end

-- ---------------------------------------------------------------- actions

openRoot = function()
  if Menu.openMenu(RESOURCE, buildRootMenu()) then return end

  -- The single-line 'focus is held elsewhere' message used to conflate three
  -- different causes (Focus held by something else, the menu framework
  -- thinks another menu is open, or the new menu itself is empty). Print
  -- the actual two states so the next log is unambiguous.
  local holder = exports['nifty-core']:holder() or 'nil'
  local current = Menu.isOpen() and 'a menu is open' or 'no menu open'
  print(('[%s] could not open the creator menu - holder=%s, %s'):format(RESOURCE, holder, current))
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

  if Menu.isOpen() then Menu.pushMenu(RESOURCE, buildRootMenu()) end
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

  if Menu.isOpen() then Menu.pushMenu(RESOURCE, buildRootMenu()) end
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

  if Menu.isOpen() then Menu.pushMenu(RESOURCE, buildRootMenu()) end
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
local camFov = 50.0
local CAM_FOV_MIN   = 15.0
local CAM_FOV_MAX   = 75.0
local CAM_FOV_STEP  = 12.0  -- FOV delta per arrow press
local CAM_EDGE_DEG_PER_SEC = 45.0  -- slow auto-rotate when cursor is at screen edge

-- Mouse lock + camera turn + zoom, all in the same render tick that
-- already drives the menu. Q / E turn the camera around the player; up
-- / down zoom in and out. The cursor is constrained to the visible
-- menu's drawn rectangle so it cannot wander off into the world and
-- accidentally interact with something the menu does not control.
Citizen.CreateThread(function()
  while true do
    _pool:ProcessMenus()

    -- Q and E close the active menu by default: NativeUI's
    -- ControlDisablingEnabled only blocks a hardcoded list of
    -- menu actions, and 47/38 (CONTEXT_SECONDARY / CONTEXT) are
    -- not in it. Disable them while a menu is open so the camera
    -- Q / E handler in the same thread is the only thing those
    -- keys do.
    if Menu.isOpen() then
      DisableControlAction(0, 47, true)  -- Q
      DisableControlAction(0, 38, true)  -- E
    end

    if creatorCam then
      -- Q / E yaw turn in 1-degree steps per keypress. Q is
      -- INPUT_CONTEXT_SECONDARY (control 47), E is INPUT_CONTEXT (38).
      -- NativeUI's ControlDisablingEnabled blocks the engine's own Q / E
      -- handling, so we read IsDisabledControlJustPressed ourselves -
      -- one-shot per press, not the held-state IsPressed. A held Q used
      -- to spin at 90 deg/s; the user wanted 1-degree steps so a single
      -- tap = exactly 1 degree of rotation.
      if IsDisabledControlJustPressed(0, 47) then camYaw = camYaw - 1.0 end  -- Q
      if IsDisabledControlJustPressed(0, 38) then camYaw = camYaw + 1.0 end  -- E
      if IsDisabledControlJustPressed(0, 47) or IsDisabledControlJustPressed(0, 38) then
        local ok, cx, cy, cz = pcall(GetCamCoord, creatorCam)
        if not ok or type(cx) ~= 'number' or type(cy) ~= 'number' or type(cz) ~= 'number' then
          -- The camera handle is stale (creator was restarted, scene
          -- camera destroyed, etc.). Drop the handle so the next loop
          -- tick no-ops and the user opens a fresh camera via start.
          creatorCam = nil
        else
          local rad = math.rad(camYaw)
          SetCamCoord(creatorCam,
            cx + math.sin(rad) * 1.0,
            cy + math.cos(rad) * 1.0,
            cz)
          PointCamAtCoord(creatorCam, cx, cy, cz)
        end
      end

      -- Mouse edge: when the cursor is at the left or right screen edge,
      -- rotate the camera slowly so the player can frame the shot hands-free.
      -- GetControlNormal returns 0..1 (normalized). Speed increases the
      -- closer the cursor gets to the extreme edge.
      do
        local EDGE_ZONE = 0.015  -- 1.5% from each edge triggers rotation
        local ok2, cx2, cy2, cz2 = pcall(GetCamCoord, creatorCam)
        if ok2 and type(cx2) == 'number' then
          local normX = GetControlNormal(0, 239)  -- INPUT_CURSOR_X
          local edgeSpeed = 0.0
          if normX < EDGE_ZONE then
            local t = 1.0 - (normX / EDGE_ZONE)  -- 0 at edge, 1 at inner boundary
            edgeSpeed = -CAM_EDGE_DEG_PER_SEC * t
          elseif normX > (1.0 - EDGE_ZONE) then
            local t = (normX - (1.0 - EDGE_ZONE)) / EDGE_ZONE  -- 0 at inner boundary, 1 at edge
            edgeSpeed = CAM_EDGE_DEG_PER_SEC * t
          end
          if edgeSpeed ~= 0.0 then
            local targetYaw = camYaw + edgeSpeed * 0.016  -- 60 fps frame
            -- Lerp toward target so the camera glides rather than jumps.
            camYaw = camYaw + (targetYaw - camYaw) * 0.08
            local rad = math.rad(camYaw)
            SetCamCoord(creatorCam,
              cx2 + math.sin(rad) * 0.001,
              cy2 + math.cos(rad) * 0.001,
              cz2)
            PointCamAtCoord(creatorCam, cx2, cy2, cz2)
          end
        end
      end

      -- Up / down FOV zoom. One-shot per key press, not held; the player
      -- taps to step in or out. Hold-to-zoom would overshoot on slower
      -- frames. Arrow up is INPUT_FRONTEND_UP (27), down is
      -- INPUT_FRONTEND_DOWN (28).
      if IsDisabledControlJustPressed(0, 27) then
        camFov = math.max(CAM_FOV_MIN, camFov - CAM_FOV_STEP)
        SetCamFov(creatorCam, camFov)
      end
      if IsDisabledControlJustPressed(0, 28) then
        camFov = math.min(CAM_FOV_MAX, camFov + CAM_FOV_STEP)
        SetCamFov(creatorCam, camFov)
      end
    end

    -- Mouse lock. The visible menu (if any) defines a draw rectangle
    -- from (menu.Position.X, menu.Position.Y) of width menu.Width and
    -- height menu.Height. We snap the cursor back inside whenever it
    -- crosses the border.
    --
    -- GetCursorPos / SetCursorPos are not always present in the runtime
    -- (depends on the FiveM build). Wrap them in pcall so a missing
    -- native falls back to a no-op rather than crashing the render
    -- thread. When they are available the cursor is constrained to the
    -- visible menu; when they are not, the cursor is free.
    if Menu.isOpen() then
      local ok, cursorX, cursorY = pcall(GetCursorPos)
      if ok and type(cursorX) == 'number' and type(cursorY) == 'number' then
        for _, m in ipairs(_pool.Menus) do
          if m.Visible then
            local rectX = m.Position.X
            local rectY = m.Position.Y
            local rectW = m.Width
            local rectH = m.Height
            local margin = 2
            if cursorX < rectX + margin then
              pcall(SetCursorPos, rectX + margin, cursorY)
            elseif cursorX > rectX + rectW - margin then
              pcall(SetCursorPos, rectX + rectW - margin, cursorY)
            end
            if cursorY < rectY + margin then
              pcall(SetCursorPos, cursorX, rectY + margin)
            elseif cursorY > rectY + rectH - margin then
              pcall(SetCursorPos, cursorX, rectY + rectH - margin)
            end
          end
        end
      end
    end

    Citizen.Wait(0)
  end
end)
