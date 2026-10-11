-- nifty-ui/client/shim.lua
--
-- API-compatible shim that translates the existing in-house menu API
-- (Menu.menu{}, Menu.button(m, label, spec), Menu.pushMenu(RESOURCE, m),
-- Menu.closeMenu(RESOURCE, reason), Menu.isOpen(), Menu:input(m, label, spec),
-- Menu.submenu(m, label, { build = function() return submenu end }))
-- to zUI-v2's zUI.* API.
--
-- The shim owns the row-based representation (handle.rows) and lets zUI-v2's
-- items.lua translate those rows to its internal ITEMS table at render time.
-- This means the five rounds of FiveM proxy-quirk workarounds that the
-- previous in-house framework had (LastBuiltMenu, MenuCloseHandlers,
-- resolveArgs, defensive push, _NIFTY_STRIPSELF_DEBUG) are no longer
-- needed: the shim follows the canonical Menu:menu{} call pattern and
-- zUI-v2's own client handles the rest.
--
-- A `handle` is the table returned from Menu.menu{}. It is what callers
-- pass to Menu.button, Menu.separator, etc. The handle carries:
--   id                - zUI menu id (string)
--   owner             - resource name passed to Menu.openMenu
--   onClose           - the user's spec.onClose (closure, never crossed)
--   dock, width       - passed to zUI.SetVisible's spec
--   section           - { name, current, total } for the section bar
--   rows              - appended-to by every builder; the items_fn reads this
--   submenu_builders  - { spec, fn } pairs; pre-built when the parent opens
--   submenu_children  - resolved child handles, keyed by child.id
--   _input_value      - current value for Menu.input rows (closure-bound)

local RESOURCE = GetCurrentResourceName()

-- Focus broker in nifty-core. The shim routes every focus call through it
-- rather than calling SetNuiFocus directly, so chat/phone and menu can
-- never fight for the keyboard.
local Focus = exports['nifty-core']

-- zUI-v2 lives in the same resource (vendored under vendor/zui/). It is
-- exposed as exports('getObject', function() return zUI end). Internal
-- calls (zUI.CreateMenu, zUI.SetItems, zUI.SetVisible) do NOT have the
-- exports namespace prepended because we are inside the same resource.
local zUI = exports[RESOURCE]:getObject()

-- The exports-namespace userdata, captured at load time. FiveM prepends
-- it as the first arg of every external call (from nifty-creator,
-- nifty-clothing, nifty-core/cl_spawn, etc.). Each export below wraps
-- its body in stripNamespace so the function bodies see the user args
-- the way the original in-house framework's cl_menu.lua did.
local Self = exports[RESOURCE]
local function stripNamespace(...)
  local args = table.pack(...)
  if args.n >= 1 and args[1] == Self then
    return table.unpack(args, 2, args.n)
  end
  return table.unpack(args, 1, args.n)
end

-- Monkey-patch zUI.ManageFocus so every focus transition goes through the
-- broker. The file at vendor/zui/menu/functions/manageFocus.lua is a
-- no-op for this reason; this is the real implementation.
--
-- Focus:acquire uses SetNuiFocus(true, true) - the cursor is LOCKED inside
-- the panel. Focus:release uses SetNuiFocus(false, false). This matches
-- the behaviour the in-house framework had and is the user-confirmed
-- choice for the port.
zUI.ManageFocus = function(state)
  if state then
    if not Focus:acquire(RESOURCE) then return false end
  else
    Focus:release(RESOURCE)
  end
end

-- ---------------------------------------------------------------------------
-- handle = Menu.menu{ title, subtitle, dock, width, section, onClose }
-- ---------------------------------------------------------------------------
-- Creates a zUI menu, stores the user's spec in the handle, returns the
-- handle. Callers pass the handle to every builder (button, separator,
-- slider, submenu, ...). The shim's items_fn reads handle.rows.
local function createHandle(spec)
  local id = zUI.CreateMenu(
    spec.title or '',
    spec.subtitle or '',
    spec.description or '',
    'nifty',
    spec.banner,
    nil,
    nil
  )

  local handle = {
    id = id,
    owner = nil,
    onClose = spec.onClose,
    dock = spec.dock,
    width = spec.width,
    section = spec.section,
    rows = {},
    submenu_builders = {},
    submenu_children = {},
    _input_value = spec.value or '',
  }

  return handle
end

-- ---------------------------------------------------------------------------
-- Build items from handle.rows, calling zUI-v2's builders.
-- Called by zUI-v2's UpdateItems every 500ms. The builders populate zUI's
-- global ITEMS table; zUI-v2 then serialises and sends to the NUI.
-- ---------------------------------------------------------------------------
local function buildItems(handle)
  for i, row in ipairs(handle.rows) do
    if row.kind == 'separator' then
      zUI.Separator(row.label or '', 'center')

    elseif row.kind == 'button' then
      -- The last arg is the submenu id. zUI-v2 navigates there on click
      -- (its _manager.lua's handleItemAction checks ACTIONS[itemId][2]).
      zUI.Button(row.label or '', row.description or '', row.styles or {}, row.action, row.submenu_id)

    elseif row.kind == 'checkbox' then
      zUI.Checkbox(row.label or '', row.description or '', row.state == true, row.styles or {}, row.action)

    elseif row.kind == 'slider' then
      zUI.Slider(row.label or '', row.description or '', row.percentage, row.step, row.styles or {}, row.action)

    elseif row.kind == 'list' then
      zUI.List(row.label or '', row.description or '', row.items or {}, row.index or 1, row.styles or {}, row.action)

    elseif row.kind == 'input' then
      -- The NUI renders our input row as a single-line <input>. The
      -- action updates the closure; zUI-v2's _manager.lua fires the
      -- action with (true, value) when the NUI posts menu:useItem.
      zUI.TextArea(row.label or '', row.description or '', handle._input_value, row.placeholder or '', row.styles or {}, row.action)
    end
  end
end

-- Build a single child submenu and wire it to its parent row. Called
-- from openMenu and pushMenu right before SetItems, so the submenu
-- id is in zUI-v2's MENUS table by the time UpdateItems runs.
local function preBuildSubmenus(handle)
  for i, builder in ipairs(handle.submenu_builders) do
    local child = builder.fn()
    handle.submenu_children[child.id] = child
    handle.rows[i].submenu_id = child.id

    -- Each child also needs its own items_fn so UpdateItems works when
    -- the user navigates into it.
    zUI.SetItems(child.id, function() buildItems(child) end)
  end
end

-- ---------------------------------------------------------------------------
-- exports('menu', function(...) ... end)
-- ---------------------------------------------------------------------------
exports('menu', function(...)
  local spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  return createHandle(spec)
end)

-- ---------------------------------------------------------------------------
-- Row builders
-- ---------------------------------------------------------------------------
-- Each one appends a row to handle.rows. The spec arguments match the
-- in-house API the callers already use. The onSelect / onChange
-- closures are wrapped in pcall so a Lua error in the caller's handler
-- does not propagate to zUI-v2 and break the menu.

local function safeCall(fn, ...)
  if type(fn) == 'function' then
    pcall(fn, ...)
  end
end

exports('button', function(...)
  local handle, label, spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  handle.rows[#handle.rows + 1] = {
    kind = 'button',
    label = label or '',
    description = spec.description,
    styles = {
      IsDisabled = spec.disabled == true,
      RightLabel = spec.rightLabel,
      RightBadge = spec.rightBadge,
      LeftBadge = spec.leftBadge,
    },
    action = function() safeCall(spec.onSelect) end,
    submenu_id = nil,  -- filled in by preBuildSubmenus if this is a submenu row
  }
end)

exports('checkbox', function(...)
  local handle, label, spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  local state = spec.checked == true
  handle.rows[#handle.rows + 1] = {
    kind = 'checkbox',
    label = label or '',
    description = spec.description,
    state = state,
    styles = { IsDisabled = spec.disabled == true },
    action = function() safeCall(spec.onChange, not state) end,
  }
end)

exports('slider', function(...)
  local handle, label, spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  local percentage = tonumber(spec.value) or 0
  local step = tonumber(spec.step) or 1
  handle.rows[#handle.rows + 1] = {
    kind = 'slider',
    label = label or '',
    description = spec.description,
    percentage = percentage,
    step = step,
    styles = { IsDisabled = spec.disabled == true, ShowPercentage = spec.showPercentage },
    action = function(onSelected, onChange, pct)
      if onChange then
        safeCall(spec.onChange, pct)
      elseif onSelected then
        safeCall(spec.onSelect, pct)
      end
    end,
  }
end)

exports('select', function(...)
  local handle, label, spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  local items = {}
  for _, v in ipairs(spec.items or {}) do items[#items + 1] = tostring(v) end
  local index = tonumber(spec.index) or 1
  if index < 1 then index = 1 end
  if index > #items then index = math.max(1, #items) end
  handle.rows[#handle.rows + 1] = {
    kind = 'list',
    label = label or '',
    description = spec.description,
    items = items,
    index = index,
    styles = { IsDisabled = spec.disabled == true },
    action = function(onSelected, onChange, idx)
      if onChange then
        safeCall(spec.onChange, idx, items[idx])
      else
        safeCall(spec.onSelect, idx, items[idx])
      end
    end,
  }
end)

exports('list', function(...)
  local handle, spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  local rows = {}
  for _, r in ipairs(spec.items or {}) do
    rows[#rows + 1] = {
      label = tostring(r.label or ''),
      description = r.description,
      right = r.right,
      selected = r.selected == true,
      payload = r.payload,
    }
  end
  handle.rows[#handle.rows + 1] = {
    kind = 'list',
    label = spec.label or '',
    description = spec.description,
    items = rows,
    index = 1,
    styles = { IsDisabled = spec.disabled == true },
    action = function(onSelected, onChange, idx, payload)
      if onChange then
        safeCall(spec.onChange, idx, payload)
      else
        safeCall(spec.onSelect, idx, payload)
      end
    end,
  }
end)

exports('separator', function(...)
  local handle, label = stripNamespace(...)
  handle.rows[#handle.rows + 1] = {
    kind = 'separator',
    label = label or '',
  }
end)

exports('input', function(...)
  local handle, label, spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  handle.rows[#handle.rows + 1] = {
    kind = 'input',
    label = label or '',
    description = spec.description,
    placeholder = spec.placeholder or '',
    styles = { IsDisabled = spec.disabled == true },
    action = function(_, value)
      handle._input_value = tostring(value or '')
      safeCall(spec.onChange, handle._input_value)
      zUI.UpdateItems(handle.id)
    end,
  }
  if spec.value then handle._input_value = tostring(spec.value) end
end)

exports('submenu', function(...)
  local handle, label, spec = stripNamespace(...)
  if type(spec) ~= 'table' then spec = {} end
  handle.rows[#handle.rows + 1] = {
    kind = 'button',
    label = label or '',
    description = spec.description,
    styles = {},
    action = function() end,
    submenu_id = nil,
  }
  handle.submenu_builders[#handle.submenu_builders + 1] = {
    fn = spec.build,
  }
end)

-- ---------------------------------------------------------------------------
-- exports('openMenu', function(owner, handle) ... end)
-- exports('pushMenu', function(owner, handle) ... end)
-- exports('closeMenu', function(owner, reason) ... end)
-- exports('isOpen', function() ... end)
-- exports('holder', function() ... end)
-- ---------------------------------------------------------------------------

-- Common path for openMenu and pushMenu: pre-build submenus, set
-- items_fn, update zUI's view. Returns true if the menu was accepted
-- (always true for pushMenu, may be false for openMenu if focus was
-- denied).
local function presentHandle(handle)
  -- Wire onClose via zUI-v2's first-class handler. The handler closure
  -- lives in nifty-ui, so the user's onClose is captured by reference
  -- and survives the resource boundary.
  zUI.SetCloseHandler(handle.id, function(reason)
    Focus:release(RESOURCE)
    if type(handle.onClose) == 'function' then
      pcall(handle.onClose, reason)
    end
  end)

  preBuildSubmenus(handle)
  zUI.SetItems(handle.id, function() buildItems(handle) end)
  zUI.SetVisible(handle.id, true)
  zUI.UpdateItems(handle.id)
end

exports('openMenu', function(...)
  local owner, handle = stripNamespace(...)
  handle.owner = owner
  if #handle.rows == 0 then return false end

  -- zUI-v2's SetOpenHandler runs after SetVisible returns, but we can
  -- acquire focus synchronously here so the very first render of the
  -- NUI is already focused. If acquire fails (something else holds
  -- focus), bail without opening.
  if not Focus:acquire(RESOURCE) then return false end

  presentHandle(handle)
  return true
end)

exports('pushMenu', function(...)
  local owner, handle = stripNamespace(...)
  handle.owner = owner
  if #handle.rows == 0 then return false end
  -- pushMenu assumes focus is already held; do not re-acquire.
  presentHandle(handle)
  return true
end)

exports('closeMenu', function(...)
  local _owner, reason = stripNamespace(...)
  local current = zUI.GetCurrentMenu()
  if current then zUI.SetVisible(current, false, reason) end
end)

exports('isOpen', function(...)
  return zUI.IsAnyMenuOpen()
end)

exports('holder', function(...)
  return Focus:holder()
end)

-- onResourceStop is handled by zUI-v2 itself (common.lua iterates MENUS,
-- finds entries whose id starts with `{nifty-ui}/`, and closes them with
-- a 500ms wait). The shim's own close handler is what fires the
-- user's onClose and releases focus. No additional handler needed here.

print(('[%s] menu framework ready'):format(RESOURCE))
