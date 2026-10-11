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
--- nifty-ui does, but loaded locally via @nifty-ui/... paths in the
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
---   Menu.input(menu, label, {value=, onChange=, placeholder=, maxLength=, description=})
---   Menu.openMenu(_RESOURCE_, menu)   - add to pool, show
---   Menu.pushMenu(_RESOURCE_, menu)   - close current, show new
---   Menu.closeMenu(_RESOURCE_, reason) - close the visible menu
---   Menu.isOpen()                     - any menu visible?
---   Menu.itemsCount(menu)             - #Items on the real menu
---
--- The first arg of openMenu / pushMenu / closeMenu is a resource name in
--- the cross-resource shim; here it is ignored, but accepting the shape
--- keeps the call sites identical.
local _pool = NativeUI.CreatePool()
_pool:MouseControlsEnabled(true)
_pool:ControlDisablingEnabled(true)

local Menu = {}

function Menu.menu(spec)
  spec = spec or {}
  -- dock: 'right' pushes the panel to the right side of the screen so the
  -- player's character stays visible in the middle. 'left' is the GTA
  -- default at X=0. NativeUI's CreateMenu does not honour `dock`, so we
  -- translate it to X.
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
  return m
end

function Menu.separator(menu, label)
  -- NativeUI exposes UIMenuSeparatorItem as a global. Its New() has a
  -- bug in the upstream library where Text/Description are not
  -- parameter names but undef globals, so the label is hardcoded
  -- "N/A" until we set it via :Text().
  local item = UIMenuSeparatorItem.New()
  item:Text(label or '')
  menu:AddItem(item)
end

function Menu.button(menu, label, spec)
  spec = spec or {}
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  if spec.rightLabel then item:RightLabel(tostring(spec.rightLabel)) end
  -- NativeUI's UIMenu:SelectItem fires the per-item Activated(menu, item)
  -- for generic UIMenuItem rows (UIMenu.lua:1027).
  item.Activated = function(_, _) pcall(spec.onSelect) end
  menu:AddItem(item)
end

function Menu.submenu(menu, label, spec)
  spec = spec or {}
  -- We build a UIMenuItem trigger row whose Activated builds and shows
  -- the child menu. The build function is caller code (no proxy in
  -- this resource), so the menu it returns is a real UIMenu with
  -- its metatable intact - we can bind it directly without the
  -- metatable-via-id lookup the cross-resource shim needs.
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
  -- spec.format(value) -> string. Rendered as the right-aligned label on
  -- the row, so "Opacitaet" reads as "42 %" rather than as the raw 42.
  -- Without a format, the raw value is shown.
  if type(spec.format) == 'function' then
    item:RightLabel(spec.format(value))
  end
  -- OnSliderChanged fires on every arrow-key nudge (the "live" path).
  -- OnSliderSelected fires on Enter/click (the "confirm" path).
  -- NativeUI's menu passes only the index to OnSliderSelected, not
  -- (menu, item, index) - we look the value up in our values table.
  item.OnSliderChanged = function(_, _, newIndex)
    local v = values[newIndex] or value
    if type(spec.format) == 'function' then
      item:RightLabel(spec.format(v))
    end
    pcall(spec.onChange, v)
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

function Menu.input(menu, label, spec)
  spec = spec or {}
  -- Text input via FiveM's DisplayOnscreenKeyboard. NativeUI has no
  -- text input widget of its own. The typed value is stored on the
  -- menu as `_input_value`; the caller reads it on click of the
  -- "save" button (closure pattern from promptOutfitName / similar).
  if not menu._input_value then
    menu._input_value = tostring(spec.value or '')
  end
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.Activated = function(_, _)
    DisplayOnscreenKeyboard(true, 'FMMC_KEY_TIP8', '', menu._input_value or '', '', '', '', 64)
    Citizen.CreateThread(function()
      while UpdateOnscreenKeyboard() == 0 do Citizen.Wait(0) end
      if UpdateOnscreenKeyboard() == 1 then
        menu._input_value = tostring(GetOnscreenKeyboardResult() or '')
        pcall(spec.onChange, menu._input_value)
      end
    end)
  end
  menu:AddItem(item)
end

-- Visual colour picker. The row looks like a normal item; activating it
-- expands a `UIMenuColourPanel` underneath that shows the palette as
-- a strip of swatches with a cursor, plus left/right arrows. Clicking
-- a swatch or pressing left/right changes the selection and fires
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
    -- on every change. The library passes (menu, item, panel, colour)
    -- (UIMenuColourPanel.lua:167). We only need the colour.
    item.ActivatedPanel = function(_, _, _, colour)
      pcall(spec.onChange, colour)
    end
  end
  menu:AddItem(item)
end

function Menu.openMenu(_RESOURCE, menu)
  _pool:Add(menu)
  menu:Visible(true)
  return true
end

function Menu.pushMenu(_RESOURCE, menu)
  -- The nifty-ui shim's pushMenu closed the current menu first to mirror
  -- the original in-house framework's "navigate to new menu" behaviour.
  -- We do the same here so back-and-forth navigation works the same way.
  for _, other in ipairs(_pool.Menus) do
    if other.Visible then other.Visible(false) end
  end
  _pool:Add(menu)
  menu:Visible(true)
  return true
end

function Menu.closeMenu(_RESOURCE, _reason)
  -- Close every visible menu. NativeUI's close does not pass a reason
  -- to OnMenuClose, so the reason the shim accepts is dropped here -
  -- callers read the reason from module-local state (e.g. `confirmed`)
  -- the same way they did before.
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

function Menu.itemsCount(menu)
  -- The menu argument is the real UIMenu (no proxy, same resource), so
  -- reading #menu.Items works directly. The cross-resource shim needs
  -- a side-table lookup for the same thing; we do not.
  if type(menu) ~= 'table' or not menu.Items then return 0 end
  return #menu.Items
end

--- Colour palettes for the UIMenuColourPanel picker.
---
--- The game's head-overlay colours are looked up by index in two palettes:
--- the hair palette (`_GetNumHairColors` returns its length) and the
--- makeup palette (`_GetNumMakeupColors`). We hardcode a curated set
--- of the most useful swatches - enough to cover the common range
--- without forcing the player to scroll through every game colour.
--- Extend by appending {R, G, B, A} tables; the panel paginates 8 at
--- a time, so 27 entries is four quick swipes.
local HAIR_PALETTE = {
  { 28,  31,  33,  255 },  --  1 schwarz
  { 39,  42,  44,  255 },  --  2 fast schwarz
  { 49,  46,  44,  255 },  --  3 dunkelbraun
  { 53,  38,  28,  255 },  --  4 espresso
  { 75,  50,  31,  255 },  --  5 dunkles nussbraun
  { 92,  59,  36,  255 },  --  6 kastanie
  { 109, 76,  53,  255 },  --  7 mittelbraun
  { 107, 80,  59,  255 },  --  8 caramel
  { 118, 92,  69,  255 },  --  9 tabak
  { 127, 104, 78,  255 },  -- 10 hellbraun
  { 153, 129, 93,  255 },  -- 11 dunkelblond
  { 167, 147, 105, 255 },  -- 12 aschblond
  { 175, 156, 112, 255 },  -- 13 warmes blond
  { 187, 160, 99,  255 },  -- 14 goldblond
  { 214, 185, 123, 255 },  -- 15 hellblond
  { 218, 195, 142, 255 },  -- 16 platinblond
  { 159, 127, 89,  255 },  -- 17 mausbraun
  { 132, 80,  57,  255 },  -- 18 mahagoni
  { 104, 43,  31,  255 },  -- 19 weinrot
  { 97,  18,  12,  255 },  -- 20 bordeaux
  { 100, 15,  10,  255 },  -- 21 dunkelrot
  { 124, 20,  15,  255 },  -- 22 ziegelrot
  { 160, 46,  25,  255 },  -- 23 rot
  { 182, 75,  40,  255 },  -- 24 kupfer
  { 162, 80,  47,  255 },  -- 25 rotbraun
  { 170, 78,  43,  255 },  -- 26 rostrotdunkel
  { 98,  98,  98,  255 },  -- 27 silbergrau
}

-- The makeup palette uses lighter, more saturated colours than the
-- hair palette. Same indexing shape: append entries to extend.
local MAKEUP_PALETTE = {
  { 240, 200, 195, 255 },  --  1 haut-hell
  { 220, 170, 165, 255 },  --  2 haut-rose
  { 200, 140, 130, 255 },  --  3 haut-pfirsich
  { 180, 110, 100, 255 },  --  4 haut-bronze
  { 255, 220, 210, 255 },  --  5 pfirsich-creme
  { 255, 180, 175, 255 },  --  6 rose
  { 250, 150, 145, 255 },  --  7 altrosa
  { 240, 120, 115, 255 },  --  8 lachs
  { 230, 100, 95,  255 },  --  9 koralle
  { 220, 80,  75,  255 },  -- 10 rot-hell
  { 200, 60,  55,  255 },  -- 11 rot-mittel
  { 180, 40,  35,  255 },  -- 12 rot-dunkel
  { 255, 200, 50,  255 },  -- 13 sonnengelb
  { 240, 170, 30,  255 },  -- 14 gold
  { 220, 140, 20,  255 },  -- 15 bernstein
  { 190, 110, 15,  255 },  -- 16 bronze
  { 150, 80,  10,  255 },  -- 17 kupfer-dunkel
  { 100, 200, 100, 255 },  -- 18 hellgruen
  { 60,  160, 60,  255 },  -- 19 gruen
  { 30,  120, 30,  255 },  -- 20 dunkelgruen
  { 100, 180, 220, 255 },  -- 21 himmelblau
  { 60,  140, 200, 255 },  -- 22 meerblau
  { 30,  100, 180, 255 },  -- 23 koenigsblau
  { 150, 100, 200, 255 },  -- 24 flieder
  { 120, 60,  170, 255 },  -- 25 lila
  { 80,  20,  140, 255 },  -- 26 dunkellila
  { 240, 240, 240, 255 },  -- 27 weiss-zart
}

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

--- One overlay: style, opacity, and its two colours.
local function buildOverlayMenu(id)
  local label = OVERLAY_LABELS[id] or ('Overlay ' .. id)
  local current = face.overlays[tostring(id)] or {
    style = 0, opacity = 1.0, colourType = 1, colour = 0, secondColour = 0,
  }

  local maxStyle = overlayStyleCount(id)
  local menu = Menu.menu({ title = label, dock = 'right' })

  -- "Kein" as a button rather than as slider position 0.
  --
  -- The game switches an overlay off with style 255, and 255 is deliberately
  -- outside the stored range here - a saved 255 would be state the player cannot
  -- see or undo. Style 0 at zero opacity is the same result and is a real value
  -- the sliders can express. This is why the label list below is read one entry
  -- LATER than the native style: its first entry is that off-state, not style 0.
  Menu.button(menu, 'Kein', {
    description = 'Dieses Merkmal ausschalten.',
    onSelect = function()
      face.overlays[tostring(id)] = {
        style = 0, opacity = 0.0, colourType = 1, colour = 0, secondColour = 0,
      }
      refresh()
      Menu.pushMenu(RESOURCE, buildOverlayMenu(id))
    end,
  })

  Menu.separator(menu, 'Stil')

  Menu.slider(menu, 'Stil', {
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
  Menu.slider(menu, 'Deckkraft', {
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

  Menu.separator(menu, 'Farbe')

  -- Palette 0 is a fixed grey and has no indices to choose; only 1 and 2 do.
  -- Each row is a UIMenuItem with a UIMenuColourPanel - the player sees a
  -- strip of swatches and clicks one instead of dragging a slider to "27".
  -- The value is the 1-based swatch index the panel reports on every
  -- change, which we store as the 0-based overlay colour.
  for _, entry in ipairs({
    { colourType = 1, label = 'Haarfarben',  palette = HAIR_PALETTE },
    { colourType = 2, label = 'Make-up-Farben', palette = MAKEUP_PALETTE },
  }) do
    local colourType = entry.colourType
    local palette = entry.palette
    local value = (current.colourType == colourType) and (current.colour + 1) or 1
    if value < 1 then value = 1 end
    if value > #palette then value = #palette end

    Menu.colourPicker(menu, entry.label, {
      palette = palette,
      panelTitle = entry.label,
      value = value,
      onChange = function(colour)
        local live = face.overlays[tostring(id)] or {}
        face.overlays[tostring(id)] = {
          style = live.style or 0,
          opacity = live.opacity or 1.0,
          colourType = colourType,
          colour = colour - 1,
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
  local menu = Menu.menu({
    title = 'Eltern',
    subtitle = parentsSummary(),
    dock = 'right',
  })

  -- The heritage window draws the two parent face portraits and a small
  -- resemblance / skin-tone bar in the panel header. It's a `UIMenuWindow`
  -- subclass; the library draws it between the title and the first row
  -- every frame. Updating it is just `heritage:Index(mom, dad)`.
  local heritage = NativeUI.CreateHeritageWindow(face.headBlend.mother, face.headBlend.father)
  menu:AddWindow(heritage)

  Menu.separator(menu, 'Praesets')

  Menu.slider(menu, 'Mutter', {
    min = 0, max = MOTHER_COUNT - 1, step = 1, value = face.headBlend.mother,
    format = function(value) return Labels.MOTHER(value) end,
    onChange = function(value)
      face.headBlend.mother = value
      -- The window shows only mom and dad (third person has no portrait),
      -- so re-index with both values when either changes.
      heritage:Index(face.headBlend.mother, face.headBlend.father)
      refresh()
      Menu.pushMenu(RESOURCE, buildParentsMenu())
    end,
  })

  Menu.slider(menu, 'Vater', {
    min = 0, max = FATHER_COUNT - 1, step = 1, value = face.headBlend.father,
    format = function(value) return Labels.FATHER(value) end,
    onChange = function(value)
      face.headBlend.father = value
      heritage:Index(face.headBlend.mother, face.headBlend.father)
      refresh()
      Menu.pushMenu(RESOURCE, buildParentsMenu())
    end,
  })

  Menu.slider(menu, 'Dritte Person', {
    -- The whole preset range, not just the mother block. That is the point of a
    -- third face: it can be whoever, including a preset the "mother" list also
    -- contains, and the engine does not care which list a name came from.
    min = 0, max = AppearanceConfig.MAX_HEADBLEND_PRESET, step = 1, value = face.headBlend.third,
    format = function(value) return ('Person %d'):format(value + 1) end,
    onChange = function(value)
      face.headBlend.third = value
      refresh()
      Menu.pushMenu(RESOURCE, buildParentsMenu())
    end,
  })

  Menu.separator(menu, 'Anteile')

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
    Menu.slider(menu, weight.label, {
      min = 0, max = 100, step = 1, value = math.floor((face.headBlend[key] or 0.0) * 100 + 0.5),
      format = function(value) return ('%d'):format(value) end,
      onChange = function(value)
        face.headBlend[key] = value / 100
        refresh()
        Menu.pushMenu(RESOURCE, buildParentsMenu())
      end,
    })
  end

  Menu.separator(menu, 'Hautton')

  Menu.slider(menu, 'Hautton', {
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
  Menu.separator(menu, 'Schnellwahl')
  for _, preset in ipairs({
    { label = 'Nur Mutter', w = { 1.0, 0.0, 0.0 } },
    { label = 'Nur Vater', w = { 0.0, 1.0, 0.0 } },
    { label = 'Nur dritte Person', w = { 0.0, 0.0, 1.0 } },
    { label = 'Eltern gleich', w = { 0.5, 0.5, 0.0 } },
    { label = 'Alle drei gleich', w = { 1 / 3, 1 / 3, 1 / 3 } },
  }) do
    local weightsToSet = preset.w
    Menu.button(menu, preset.label, {
      description = 'Anteile setzen.',
      onSelect = function()
        face.headBlend.motherWeight = weightsToSet[1]
        face.headBlend.fatherWeight = weightsToSet[2]
        face.headBlend.thirdWeight = weightsToSet[3]
        refresh()
        Menu.pushMenu(RESOURCE, buildParentsMenu())
      end,
    })
  end

  return menu
end

--- Eye colour: the game's thirty-two, in the engine's own order.
local function buildEyeColourMenu()
  local menu = Menu.menu({ title = 'Augenfarbe', dock = 'right' })

  Menu.slider(menu, 'Farbe', {
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
  local menu = Menu.menu({
    title = 'Gesichtsform',
    subtitle = 'Zwanzig Schieberegler.',
    dock = 'right',
  })

  for id = 0, AppearanceConfig.MAX_FACE_FEATURE do
    local value = face.features[tostring(id)] or 0.0

    Menu.slider(menu, Labels.FEATURES[id + 1] or ('Merkmal %d'):format(id), {
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
--- Visual swatch picker instead of an opaque index slider.
local function buildHairColourMenu()
  local menu = Menu.menu({ title = 'Haarfarbe', dock = 'right' })

  local function clamp(v) if v < 1 then return 1 end if v > #HAIR_PALETTE then return #HAIR_PALETTE end return v end

  Menu.colourPicker(menu, 'Hauptfarbe', {
    palette = HAIR_PALETTE,
    panelTitle = 'Hauptfarbe',
    value = clamp((face.hairColour.primary or 0) + 1),
    onChange = function(colour)
      face.hairColour.primary = colour - 1
      refresh()
    end,
  })

  Menu.colourPicker(menu, 'Strähnen', {
    palette = HAIR_PALETTE,
    panelTitle = 'Strähnen',
    value = clamp((face.hairColour.highlight or 0) + 1),
    onChange = function(colour)
      face.hairColour.highlight = colour - 1
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

  local menu = Menu.menu({
    title = currentName and ('%s - %s'):format(label, currentName) or label,
    subtitle = #currentTags > 0 and ('Merkmale: ' .. table.concat(currentTags, ', ')) or nil,
    -- Section bar updates to the slot name (e.g. "Brow 1 / 11") so the
    -- player knows which submenu they are in. The exact "1" is a
    -- placeholder for the slot index in the creator's order, not
    -- the slot id; tracking the precise index is polish.
    section = { name = label, current = 1, total = 11 },
    dock = 'right',
  })

  local labels = {}
  for i, opt in ipairs(options) do
    labels[i] = (opt.name == '') and 'Standard' or opt.name
  end

  Menu.select(menu, 'Kollektion', {
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
      Menu.pushMenu(RESOURCE, buildSlotMenu(kind, id))
    end,
  })

  Menu.slider(menu, 'Modell', {
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

  Menu.slider(menu, 'Textur', {
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
  local menu = Menu.menu({
    title    = 'Charakter erstellen',
    subtitle = 'Aussehen - Name und Stammdaten stehen bereits fest.',
    dock     = 'right',
    -- Section bar data: shown as "Features 1 / 11" in the dark strip
    -- under the gradient header. The creator's top-level menu is step 1
    -- of 11 (Features submenu, then the eleven submenus it opens).
    -- Submenus carry their own section data; see buildSlotMenu.
    section  = { name = 'Features', current = 1, total = 11 },
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
    Menu.separator(menu, 'Modell')
    for _, entry in ipairs({ { 'mp_m_freemode_01', 'Maennlich' },
                             { 'mp_f_freemode_01', 'Weiblich' } }) do
      Menu.button(menu, entry[2], {
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
          applyDecorations()          Menu.pushMenu(RESOURCE, buildRootMenu())
        end,
      })
    end
  end

  Menu.separator(menu, 'Kleidung')
  -- Iterate the component IDs the actual model exposes, not a hardcoded
  -- COMPONENT_ORDER. The original list had a 12 that the mp_m_freemode_01
  -- model does not expose (12 component slots, IDs 0-11), so 1 in 12 submenus
  -- silently never appeared. Sort the discovered IDs so the menu order is
  -- stable.
  local componentIds = {}
  for id in pairs(slots.components) do componentIds[#componentIds + 1] = id end
  table.sort(componentIds)
  for _, id in ipairs(componentIds) do
    local options = slots.components[id]
    Menu.submenu(menu, COMPONENT_LABELS[id] or ('Slot ' .. id), {
      description = ('Slot %d - %d Kollektionen'):format(id, #options),
      build = function() return buildSlotMenu('components', id) end,
    })
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

  Menu.separator(menu, 'Gesicht')
  Menu.submenu(menu, 'Eltern', {
    description = 'Vater, Mutter und die beiden Mischungen.',
    build = buildParentsMenu,
  })

  Menu.submenu(menu, 'Augenfarbe', {
    description = 'Eine von dreissigzwei.',
    build = buildEyeColourMenu,
  })

  Menu.separator(menu, 'Merkmale')

  for id = AppearanceConfig.MIN_OVERLAY_ID, AppearanceConfig.MAX_OVERLAY_ID do
    Menu.submenu(menu, OVERLAY_LABELS[id] or ('Overlay ' .. id), {
      description = 'Stil, Deckkraft und Farbe.',
      build = function() return buildOverlayMenu(id) end,
    })
  end

  Menu.submenu(menu, 'Haarfarbe', {
    description = 'Hauptfarbe und Strähnen.',
    build = buildHairColourMenu,
  })

  Menu.submenu(menu, 'Gesichtsform', {
    description = 'Die zwanzig Gesichtsschieberegler.',
    build = buildFaceMenu,
  })

  -- Tattoos, grouped by the body part they go on. The hair overlay is NOT here:
  -- the game ties exactly one decal to each hairstyle, so picking the hair picks
  -- the overlay. A list to choose from would offer a combination the game has no
  -- way to draw.
  local tattooZones = GameData.tattooZones()
  if #tattooZones > 0 then
    Menu.separator(menu, 'Tattoos')
    for _, zoneId in ipairs(tattooZones) do
      Menu.submenu(menu, ZONE_LABELS[zoneId] or ('Zone ' .. zoneId), {
        description = ('%d Tattoo(s)'):format(#GameData.tattoosByZone(zoneId)),
        build = function() return buildTattooMenu(zoneId) end,
      })
    end
  end

  Menu.separator(menu, 'Aktionen')

  Menu.button(menu, 'Zufallsaufzug', {
    description = 'Zufaellige Kleidung. A/D dreht die Kamera.',
    onSelect = function() randomise() end,
  })

  Menu.button(menu, 'Zuruecksetzen', {
    description = 'Alle Auswaehle verwerfen und das Modell neu laden.',
    onSelect = function() reset() end,
  })

  Menu.button(menu, 'Fertig', {
    description = 'Aussehen speichern und die Welt betreten.',
    onSelect = function() submit() end,
  })

  Menu.button(menu, 'Abbrechen', {
    description = 'Verlassen. Beim naechsten Verbinden geht es hier weiter.',
    onSelect = function() cancel() end,
  })

  -- menu.items in this diagnostic used to read the proxy-deep-copy
  -- of the menu handle, which has an empty Items table regardless of
  -- what was added. Use the shim's itemsCount helper, which looks
  -- the real menu up by id and reports the live count.
  print(('[nifty-creator] buildRootMenu: exit, items=%d'):format(Menu.itemsCount(menu)))
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
-- this resource. nifty-ui runs a parallel render thread for its own
-- pool (used by wardrobe, store, spawn) - two pools, two threads, no
-- interference because they draw to separate UIMenu instances.
Citizen.CreateThread(function()
  while true do
    _pool:ProcessMenus()
    Citizen.Wait(0)
  end
end)