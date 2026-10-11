-- nifty-ui/client/nifty_wrap.lua
--
-- Bridges the in-house nifty menu API (Menu.menu, Menu.button, ...)
-- to NativeUI-Lua-Reloaded. The call-site shape is unchanged so the
-- five caller files (nifty-creator/cl_creator.lua,
-- nifty-clothing/cl_wardrobe.lua, nifty-clothing/cl_store.lua,
-- nifty-core/cl_spawn.lua, nifty-housing via /wardrobe command) do
-- not need to change.
--
-- NativeUI uses GTA-natives (DrawSprite, DrawText, DrawRect) to draw
-- the menu directly to the screen. There is no NUI, no CEF, and no
-- focus to manage - the player can interact with the menu via keyboard
-- or mouse, but the rest of the game stays interactive behind it. The
-- focus broker at nifty-core/client/cl_focus.lua stays unchanged
-- because chat and phone still need it.
--
-- PROXY QUIRK - THE LAST BUILT MENU PATTERN
--
-- FiveM's exports proxy on this build drops the first user arg of every
-- external call. nifty's call site is `Menu.button(handle, 'Label', spec)`
-- (two user args: the handle and the label). The proxy drops the handle,
-- so the registered function receives `('Label', spec)`. Same for every
-- other builder. The shim keeps a file-local upvalue `LastBuiltMenu`
-- that the `menu` export sets to the most recently created menu. The
-- other builders add their rows to `LastBuiltMenu` instead of the
-- dropped handle. The caller still receives the handle from `Menu.menu`,
-- so callers that store the handle and use it later (e.g. pushMenu)
-- continue to work - the same Lua table is referenced by both the
-- caller's local and `LastBuiltMenu`.
--
-- This is the same pattern the original in-house framework used
-- (LastBuiltMenu fallback - see the commit history). The earlier
-- stripNamespace in the zUI-v2 shim was wrong for the same reason
-- the earlier n_args=1 print shows: the proxy is dropping the handle,
-- not prepending the namespace.
--
-- Render thread: NativeUI menus need MenuPool:ProcessMenus /
-- :ProcessControl / :ProcessMouse / :Draw every frame. We run a single
-- Citizen thread that ticks the global pool. The shim stores the pool
-- in a closure so the menu state survives between calls.

local RESOURCE = GetCurrentResourceName()

-- The library exposes its factory functions as a top-level global table
-- named "NativeUI" (from NativeUI.lua). We grab it once.
local NativeUI = NativeUI

-- Single global MenuPool for the resource. NativeUI menus are not
-- NUI surfaces, so a single pool is fine - it draws every visible
-- menu on the same render thread.
local pool = NativeUI.CreatePool()
pool:MouseControlsEnabled(true)
pool:ControlDisablingEnabled(true)

-- The most recently created UIMenu. The `menu` export writes to this
-- when it builds a new handle; the other builders read from it because
-- the proxy drops the handle arg on every external call. The same
-- value the caller's `local menu = Menu.menu(...)` captures is the same
-- table LastBuiltMenu points to (Lua tables are by-reference), so
-- items added via LastBuiltMenu:AddItem show up in the caller's menu.
local LastBuiltMenu = nil

-- ----- Helpers -----

-- Map a nifty onSelect handler to NativeUI's OnActivated. The
-- NativeUI callback receives (menu, item) - we ignore both and just
-- fire the user's handler. Wrapped in pcall so a Lua error in a
-- caller's handler does not break the menu thread.
local function safeCall(fn, ...)
  if type(fn) == 'function' then
    pcall(fn, ...)
  end
end

-- ----- Builder functions -----
-- Each builder adds an item to LastBuiltMenu. The label / spec / etc.
-- are at args[1..] because the proxy dropped args[0] (the menu).

exports('menu', function(...)
  local spec = ...
  if type(spec) ~= 'table' then spec = {} end
  -- NativeUI's CreateMenu takes (Title, Subtitle, X, Y, TxtDictionary,
  -- TxtName, Heading, R, G, B, A). X=0, Y=0 - the menu renders at the
  -- default GTA-Online position. nifty's "dock" hint has no NativeUI
  -- equivalent; the menu always draws at the same position.
  local m = NativeUI.CreateMenu(
    spec.title or '', spec.subtitle or '',
    0, 0,
    'commonmenu', 'interaction_bgd',
    0,
    255, 255, 255, 255
  )
  LastBuiltMenu = m
  return m
end)

exports('button', function(...)
  local label, spec = ...
  if type(spec) ~= 'table' then spec = {} end
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.OnActivated = function() safeCall(spec.onSelect) end
  if spec.rightLabel then item:RightLabel(tostring(spec.rightLabel)) end
  if LastBuiltMenu then LastBuiltMenu:AddItem(item) end
end)

exports('checkbox', function(...)
  local label, spec = ...
  if type(spec) ~= 'table' then spec = {} end
  local initial = spec.checked == true
  local item = NativeUI.CreateCheckboxItem(label or '', initial, spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.OnCheckedChanged = function(_, _item, checked)
    safeCall(spec.onChange, checked == true)
  end
  if LastBuiltMenu then LastBuiltMenu:AddItem(item) end
end)

exports('slider', function(...)
  local label, spec = ...
  if type(spec) ~= 'table' then spec = {} end
  local min = tonumber(spec.min) or 0
  local max = tonumber(spec.max) or 100
  local step = tonumber(spec.step) or 1
  local value = math.floor(((tonumber(spec.value) or min) - min) / step + 0.5) * step + min
  -- NativeUI's UIMenuSliderItem uses an indexed list of values, not a
  -- numeric range. We build a synthetic index list of size
  -- (max-min)/step+1 so OnSliderChanged delivers a numeric value.
  local values = {}
  for i = min, max, step do values[#values + 1] = i end
  local index = math.floor((value - min) / step) + 1
  if index < 1 then index = 1 end
  if index > #values then index = #values end
  -- NativeUI's CreateSliderHeritageItem takes (Text, Items, Index,
  -- Description, SliderColors, BackgroundSliderColors). Pass the GTA
  -- Online-style blue-on-darker-blue colours explicitly.
  local item = NativeUI.CreateSliderHeritageItem(
    label or '',
    index, #values,
    spec.description or '',
    { R = 57, G = 119, B = 200, A = 255 },
    { R = 4,  G = 32,  B = 57,  A = 255 }
  )
  if spec.disabled then item:Enabled(false) end
  item.OnSliderChanged = function(_, _item, newIndex)
    local newValue = values[newIndex] or value
    safeCall(spec.onChange, newValue)
  end
  item.OnActivated = function(_, _item, newIndex)
    local newValue = values[newIndex] or value
    safeCall(spec.onSelect, newValue)
  end
  if LastBuiltMenu then LastBuiltMenu:AddItem(item) end
end)

exports('select', function(...)
  local label, spec = ...
  if type(spec) ~= 'table' then spec = {} end
  local items = spec.items or {}
  local index = tonumber(spec.index) or 1
  if index < 1 then index = 1 end
  if index > #items then index = math.max(1, #items) end
  -- NativeUI's UIMenuListItem takes (Text, Items, Index, Description).
  local item = NativeUI.CreateListItem(label or '', items, index, spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.OnListChanged = function(_, _item, newIndex)
    safeCall(spec.onChange, newIndex, items[newIndex])
  end
  item.OnActivated = function(_, _item, newIndex)
    safeCall(spec.onSelect, newIndex, items[newIndex])
  end
  if LastBuiltMenu then LastBuiltMenu:AddItem(item) end
end)

exports('separator', function(...)
  print(('[nifty-ui] separator called, n_args=%d, LastBuiltMenu=%s'):format(select('#', ...), tostring(LastBuiltMenu)))
  local ok, result = pcall(function()
    local label = ...
    print(('[nifty-ui]   label=%s'):format(tostring(label)))
    local item = UIMenuSeparatorItem.New()
    print(('[nifty-ui]   item created, type=%s'):format(type(item)))
    item:Text(label or '')
    print('[nifty-ui]   text set')
    if LastBuiltMenu then
      print(('[nifty-ui]   adding to LastBuiltMenu, type=%s'):format(type(LastBuiltMenu)))
      LastBuiltMenu:AddItem(item)
      print('[nifty-ui]   added')
    else
      print('[nifty-ui]   LastBuiltMenu is nil, skipping AddItem')
    end
  end)
  if not ok then
    print(('[nifty-ui] separator error: %s'):format(tostring(result)))
  end
end)

-- Text input. NativeUI has no text input widget, so we use FiveM's
-- native on-screen keyboard (DisplayOnscreenKeyboard) when the user
-- activates the input row. The typed value updates a closure-bound
-- variable on the menu, so the rest of the menu can read it via
-- Menu.input's getValue pattern (callers read it at click time of
-- the "save" button, not via a callback).
exports('input', function(...)
  local label, spec = ...
  if type(spec) ~= 'table' then spec = {} end
  if not LastBuiltMenu then return end
  if LastBuiltMenu._input_value == nil then
    LastBuiltMenu._input_value = tostring(spec.value or '')
  end
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.OnActivated = function()
    DisplayOnscreenKeyboard(true, 'FMMC_KEY_TIP8', '', LastBuiltMenu._input_value or '', '', '', '', 64)
    -- Wait for the keyboard to be ready, then read the result.
    -- DisplayOnscreenKeyboard is asynchronous: UpdateOnscreenKeyboard
    -- returns 0 while the user is typing, 1 when done, 2 when cancelled.
    Citizen.CreateThread(function()
      while UpdateOnscreenKeyboard() == 0 do Citizen.Wait(0) end
      local status = UpdateOnscreenKeyboard()
      if status == 1 then
        local result = GetOnscreenKeyboardResult()
        LastBuiltMenu._input_value = tostring(result or '')
        safeCall(spec.onChange, LastBuiltMenu._input_value)
      end
    end)
  end
  LastBuiltMenu:AddItem(item)
end)

exports('list', function(...)
  local spec = ...
  if type(spec) ~= 'table' then spec = {} end
  -- nifty's "list" was an old API the codebase never used; emit a
  -- disabled button so callers that mistakenly use it see something
  -- instead of an empty row.
  local item = NativeUI.CreateItem('(list - not implemented)', '')
  item:Enabled(false)
  if LastBuiltMenu then LastBuiltMenu:AddItem(item) end
end)

exports('submenu', function(...)
  local label, spec = ...
  if type(spec) ~= 'table' then spec = {} end
  -- A submenu is a button that, when activated, builds and shows a
  -- child UIMenu. We lazily build the child the first time the button
  -- is activated (the nifty API takes a build function, not a pre-built
  -- menu). The result is cached on the parent for subsequent opens.
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.OnActivated = function()
    if not LastBuiltMenu then return end
    if not LastBuiltMenu._submenu_cache then
      LastBuiltMenu._submenu_cache = {}
    end
    if not LastBuiltMenu._submenu_cache[label] then
      LastBuiltMenu._submenu_cache[label] = spec.build()
    end
    local sub = LastBuiltMenu._submenu_cache[label]
    if sub and type(sub) == 'table' then
      pool:Add(sub)
      sub:Visible(true)
    end
  end
  if LastBuiltMenu then LastBuiltMenu:AddItem(item) end
end)

-- ----- Visibility / pool control -----

-- Common path: validate, register onClose, add to pool, show.
local function presentHandle(menu)
  if type(menu) ~= 'table' or not menu.Visible then return false end
  if menu._onClose then
    -- NativeUI menus fire an OnMenuClose event when Visible(false) is
    -- called. We use that to surface the user's onClose with a reason.
    menu.OnMenuClose = function(_)
      if type(menu._onClose) == 'function' then
        pcall(menu._onClose, 'closed')
      end
    end
  end
  pool:Add(menu)
  menu:Visible(true)
  return true
end

exports('openMenu', function(...)
  local _owner, menu = ...
  if not presentHandle(menu) then return false end
  return true
end)

exports('pushMenu', function(...)
  local _owner, menu = ...
  -- pushMenu: caller has a new menu to show, replacing the current
  -- one. We close everything currently visible first to mirror the
  -- previous framework's "navigate to new menu" behaviour.
  pool:CloseAllMenus()
  return presentHandle(menu)
end)

exports('closeMenu', function(...)
  local _owner, _reason = ...
  -- Close whichever menu is currently visible. The OnMenuClose
  -- handler set up by presentHandle fires the user's onClose with the
  -- reason. NativeUI's close does not pass a reason, so we collapse
  -- the cases - the user's onClose reads module-local state (e.g.
  -- confirmed = true) the same way it did before.
  pool:CloseAllMenus()
end)

exports('isOpen', function(...)
  return pool:IsAnyMenuOpen()
end)

exports('holder', function(...)
  -- The native-UI menu does not need the focus broker; the broker
  -- stays in nifty-core for chat/phone. We return the broker's
  -- current holder so callers that diagnose focus (e.g. the creator's
  -- could-not-open diagnostic) still get a meaningful value.
  return exports['nifty-core']:holder()
end)

-- ----- Render thread -----
-- NativeUI menus need ProcessMenus / ProcessControl / ProcessMouse /
-- Draw every frame. One thread, single pool.
Citizen.CreateThread(function()
  while true do
    pool:ProcessMenus()
    pool:ProcessControl()
    pool:ProcessMouse()
    pool:Draw()
    Citizen.Wait(0)
  end
end)

print(('[%s] menu framework ready (native UI)'):format(RESOURCE))
