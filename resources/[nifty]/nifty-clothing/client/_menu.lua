-- nifty-clothing / client / _menu
--
-- File-local Menu wrapper around the NativeUI library (lbg-char pattern).
-- Loaded as the first client_script after the NativeUI library files in
-- fxmanifest, so the NativeUI global is in scope when this runs. Both
-- cl_wardrobe.lua and cl_store.lua `require('client/_menu')` and use
-- the returned Menu table the same way they used to use the nifty-ui
-- export shim.
--
-- The Menu table provides the API surface the two caller files actually
-- touch: menu, button, separator, submenu, input, openMenu, pushMenu,
-- closeMenu. Sliders, checkbox, list, select, etc. are not used by
-- nifty-clothing - extend here if a future caller needs them.
local _pool = NativeUI.CreatePool()
_pool:MouseControlsEnabled(true)
_pool:ControlDisablingEnabled(true)

local M = {}

function M.menu(spec)
  spec = spec or {}
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

function M.button(menu, label, spec)
  spec = spec or {}
  local item = NativeUI.CreateItem(label or '', spec.description or '')
  if spec.disabled then item:Enabled(false) end
  item.Activated = function(_, _) pcall(spec.onSelect) end
  menu:AddItem(item)
end

function M.separator(menu, label)
  local item = UIMenuSeparatorItem.New()
  item:Text(label or '')
  menu:AddItem(item)
end

function M.submenu(menu, label, spec)
  spec = spec or {}
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

function M.input(menu, label, spec)
  spec = spec or {}
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

function M.openMenu(_RESOURCE, menu)
  _pool:Add(menu)
  menu:Visible(true)
  return true
end

function M.pushMenu(_RESOURCE, menu)
  for _, other in ipairs(_pool.Menus) do
    if other.Visible then other.Visible(false) end
  end
  _pool:Add(menu)
  menu:Visible(true)
  return true
end

function M.closeMenu(_RESOURCE, _reason)
  for _, other in ipairs(_pool.Menus) do
    if other.Visible then other.Visible(false) end
  end
end

-- Render thread. lbg-char style: one thread, one pool, one line per
-- frame. The other client scripts in this resource do not have their
-- own menu thread.
Citizen.CreateThread(function()
  while true do
    _pool:ProcessMenus()
    Citizen.Wait(0)
  end
end)

return M
