--[[
  The menu framework — client half.

  ONE menu surface for the whole server. `nifty-ui` owns the `ui_page` that draws
  menus, and therefore also owns the keyboard while one is open. Two resources
  each drawing their own menus would put two CEF browsers behind one global
  `SetNuiFocus`, and last writer wins — the player would be steering a menu they
  cannot see. So the menu is not a component every resource instantiates; it is
  a single surface this resource lends out.

  WHAT THIS FILE DECIDES: whether a menu is open, which menu, and whether the
  keyboard may move. Nothing else. Every item in a menu carries a callback that
  was supplied by the RESOURCE that built it — the menu never decides what any of
  those callbacks mean, and a value a player changed in a slider is untrusted the
  moment it leaves here.

  A menu is a plain description, not a live object. Building one produces a table:

      { title = 'Character erstellen', items = { { kind = 'slider', ... } } }

  and it is that table which is sent to the page and back. No functions survive the
  crossing, which is the point: the page can redraw the menu, a submenu can be
  restored after a focus change, and nothing the browser does can become a Lua
  call it was not given.

  ---

  FiveM's exports namespace auto-adds itself to every call. That is: the
  function the user registered with exports('menu', function(spec) ... end)
  is invoked with (Menu, spec) when the user code is `Menu.menu(spec)`,
  and with (spec) when the call comes from inside this resource directly.
  Every export below calls stripSelf(...) on its args; that helper detects
  which case we are in and returns the slice starting at the real first
  user arg. Without this the menu export receives the namespace as `spec`,
  the namespace has no `title` or `items` field, and the resulting menu is
  an empty table. Diagnosed 2026-10-11 (commit 3a0d06a -> 6275267).
]]

local RESOURCE = GetCurrentResourceName()

--- The broker, the only thing allowed to touch SetNuiFocus. See cl_focus.lua.
local Focus = exports['nifty-core']

--- This is the exports namespace itself. Every entry below uses it to detect
--- whether FiveM has prepended the namespace as `self` to the call. We have
--- to support both call patterns (FiveM auto-add AND a direct in-resource
--- call); the helper does the routing.
local Self = exports['nifty-core']

--- Strip the leading `self` arg if it is the namespace. FiveM adds it on
--- every call; an in-resource direct call does not. After the strip the
--- returned values are exactly the user-passed args, in order.
local function stripSelf(...)
  local args = table.pack(...)
  if args.n >= 1 and args[1] == Self then
    return table.unpack(args, 2, args.n)
  end
  return table.unpack(args, 1, args.n)
end

--- What is on screen right now: the owner resource, its menu table, and a token.
--- The token is what makes close events unambiguous — see `closeMenu` below.
local Current = nil

--- Monotonic counter. A menu's id is `<owner>:<n>`, so a resource that opens the
--- same menu twice still produces two distinct ids, and a close event that arrives
--- late cannot close a menu that merely happens to have the same content.
local MenuSerial = 0

-- ---------------------------------------------------------------------------
-- Menu construction
--
-- Fluent, because a menu is a list and reading it top to bottom should look like
-- the menu does. Each builder returns the menu, so calls chain.
-- ---------------------------------------------------------------------------

local function newMenu(spec)
  return {
    owner = nil,        -- filled in by openMenu; the page never sends it back
    id = nil,
    title = spec.title or '',
    subtitle = spec.subtitle or nil,
    -- `dock` decides where the menu sits. 'center' overlays everything; 'right'
    -- takes a column and leaves the middle of the screen alone, which is what the
    -- character creator needs so the player can watch the face change.
    dock = spec.dock or 'center',
    width = spec.width or nil,
    onClose = spec.onClose or nil,
    items = {},
  }
end

--- Append one item. Every builder funnels through here so that validation and the
--- `kind` string live in exactly one place — an item type that is added to the page
--- but not to this function is invisible until somebody opens that menu.
---
--- DEFENSIVE `items` ASSIGNMENT. `newMenu` always returns a table with `items = {}`,
--- so in a correctly constructed flow this line is a no-op. It exists for the case
--- where a menu arrived here without that field (the openCreator chain was hitting
--- a runtime error on `attempt to get length of a nil value (field 'items')` from
--- this function; the print below surfaces the actual menu so we can see what is
--- arriving). When the diagnostic fires we know the menu is malformed and the
--- caller has to fix it; when it does not, this is a one-liner that costs nothing.
local function push(menu, item)
  if type(menu) ~= 'table' then
    print(('[nifty-core] push: ERROR menu is %s, item.kind=%s'):format(type(menu), tostring(item and item.kind)))
    return menu
  end
  if menu.items == nil then
    local keys = {}
    for k in pairs(menu) do keys[#keys + 1] = tostring(k) end
    print(('[nifty-core] push: menu arrived with no items field - keys=%s, creating []'):format(table.concat(keys, ', ')))
    menu.items = {}
  end
  item.kind = item.kind or 'button'
  menu.items[#menu.items + 1] = item
  return menu
end

exports('menu', function(...)
  local spec = stripSelf(...)
  return newMenu(type(spec) == 'table' and spec or {})
end)

--- A row that is drawn and does nothing. Used to break a long menu into readable
--- groups; it carries no state and no callback.
exports('separator', function(...)
  local menu, label = stripSelf(...)
  print(('[nifty-core] separator: menu=%s, label=%s'):format(tostring(menu), tostring(label)))
  return push(menu, { kind = 'separator', label = label or '' })
end)

--- A button. `onSelect` fires on click and on Enter while the row is selected.
exports('button', function(...)
  local menu, label, spec = stripSelf(...)
  spec = spec or {}
  return push(menu, {
    kind = 'button',
    label = tostring(label or ''),
    disabled = spec.disabled or false,
    description = spec.description or nil,
    onSelect = spec.onSelect,
  })
end)

--- A checkbox. One boolean, toggled in place.
exports('checkbox', function(...)
  local menu, label, spec = stripSelf(...)
  spec = spec or {}
  return push(menu, {
    kind = 'checkbox',
    label = tostring(label or ''),
    checked = spec.checked == true,
    description = spec.description or nil,
    onChange = spec.onChange,
  })
end)

--- A slider over a closed integer range.
---
--- `step` defaults to 1 and that is deliberate. The range is a range, not a list of
--- buttons: 0..100 is one row with a draggable handle, not a hundred targets. A
--- step of 5 is only right where the underlying value is coarse — and the caller
--- knows that, which is why it is a parameter and not a guess.
exports('slider', function(...)
  local menu, label, spec = stripSelf(...)
  spec = spec or {}
  local min = tonumber(spec.min) or 0
  local max = tonumber(spec.max) or 100
  local step = tonumber(spec.step) or 1
  if max <= min then max = min + 1 end
  if step <= 0 then step = 1 end
  local value = tonumber(spec.value) or min
  if value < min then value = min end
  if value > max then value = max end
  return push(menu, {
    kind = 'slider',
    label = tostring(label or ''),
    min = min,
    max = max,
    step = step,
    value = value,
    format = spec.format or nil,
    description = spec.description or nil,
    onChange = spec.onChange,
  })
end)

--- A single line of text, edited in place.
---
--- NOT part of LemonUI's vocabulary, and added here for a concrete reason: the
--- character creator has to ask for a name and a date of birth, and LemonUI has no
--- text input at all. Without this row the player cannot name their character, so
--- every other menu primitive is irrelevant.
---
--- The value is a STRING and always a string. It is not parsed here, not
--- length-checked for meaning and not trimmed — that is the resource that built
--- the menu, and on the server, not the widget. All this does is carry characters
--- a player typed to whoever asked for them.
exports('input', function(...)
  local menu, label, spec = stripSelf(...)
  spec = spec or {}
  return push(menu, {
    kind = 'input',
    label = tostring(label or ''),
    value = tostring(spec.value or ''),
    placeholder = spec.placeholder or '',
    maxLength = tonumber(spec.maxLength) or 64,
    description = spec.description or nil,
    onChange = spec.onChange,
  })
end)

--- One of N, chosen from a list. Different from a list item in that it does not
--- open anything: it changes a value in place, like a checkbox changes a boolean.
exports('select', function(...)
  local menu, label, spec = stripSelf(...)
  spec = spec or {}
  local items = {}

  for _, v in ipairs(spec.items or {}) do
    items[#items + 1] = tostring(v)
  end

  local index = tonumber(spec.index) or 1
  if index < 1 then index = 1 end
  if index > #items then index = #items end

  return push(menu, {
    kind = 'select',
    label = tostring(label or ''),
    items = items,
    index = index,
    description = spec.description or nil,
    onChange = spec.onChange,
  })
end)

--- A row that opens another menu. The `build` callback is called lazily, the first
--- time the row is opened, so a menu with ten submenus is not built ten times at
--- construction — and a submenu whose contents depend on state reads that state at
--- open time rather than at construction time.
exports('submenu', function(...)
  local menu, label, spec = stripSelf(...)
  spec = spec or {}
  return push(menu, {
    kind = 'submenu',
    label = tostring(label or ''),
    description = spec.description or nil,
    build = spec.build,
  })
end)

--- A list of rows, each carrying arbitrary payload. `onSelect(index, payload)`
--- fires on click and on Enter. This is the one item kind that knows nothing about
--- the payload: it hands it back untouched, so a caller can put a drawable index,
--- a phone number or a property id in there without this file knowing which.
exports('list', function(...)
  local menu, spec = stripSelf(...)
  spec = spec or {}
  local rows = {}

  for _, row in ipairs(spec.items or {}) do
    rows[#rows + 1] = {
      label = tostring(row.label or ''),
      description = row.description or nil,
      right = row.right or nil,
      selected = row.selected or false,
      payload = row.payload,
    }
  end

  return push(menu, {
    kind = 'list',
    label = spec.label or nil,
    rows = rows,
    onSelect = spec.onSelect,
  })
end)

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------

--- Strip everything the browser must not be able to call back into.
---
--- `onSelect`, `onChange` and `build` are Lua functions. `SendNUIMessage` would
--- happily try to serialise them and produce either an error or a table with a
--- function in it that the page cannot use. Dropping them here means the wire
--- format is data all the way down, which is what makes the page untrusted.
local function toWire(menu)
  local wire = {
    id = menu.id,
    title = menu.title,
    subtitle = menu.subtitle,
    dock = menu.dock,
    width = menu.width,
    items = {},
  }

  -- Section bar data: a small dark strip under the gradient header that
  -- shows where the player is in the creator (e.g. "Features 1 / 11").
  -- Only sent when the menu spec set it. nil on most menus; a
  -- truthy section.name flips the strip visible on the page.
  if menu.section and menu.section.name then
    wire.section = {
      name = menu.section.name,
      current = menu.section.current,
      total = menu.section.total,
    }
  end

  for i, item in ipairs(menu.items) do
    local row = { kind = item.kind, label = item.label }
    for _, k in ipairs({ 'checked', 'min', 'max', 'step', 'value', 'items',
                         'index', 'rows', 'description', 'disabled', 'right',
                         'selected' }) do
      if item[k] ~= nil then row[k] = item[k] end
    end
    wire.items[i] = row
  end

  return wire
end

--- Send one menu to the page and remember it, so a callback can be routed back.
local function present(menu)
  SendNUIMessage({ action = 'menuOpen', data = toWire(menu) })
  print(('[nifty-core] present: sent menuOpen id=%s items=%d to NUI'):format(menu.id or '?', tostring(#menu.items)))
end

--- Open a menu owned by `owner`.
---
--- Returns false when another surface holds the keyboard — including another menu.
--- A menu that silently replaced whatever was on screen would leave a player
--- staring at a menu with dead controls, which is the exact class of bug the focus
--- broker was written to make impossible.
exports('openMenu', function(...)
  local owner, menu = stripSelf(...)
  if type(menu) ~= 'table' or #menu.items == 0 then
    print(('[nifty-core] menu.openMenu(%s) -> REJECTED, items=%s, type=%s'):format(
      tostring(owner), tostring(type(menu) == 'table' and #menu.items or 'n/a'),
      type(menu)))
    return false
  end
  if Current ~= nil then
    print(('[nifty-core] menu.openMenu(%s) -> REJECTED, current already set (id=%s)'):format(tostring(owner), Current.id or '?'))
    return false
  end

  if not Focus:acquire(RESOURCE) then
    print(('[nifty-core] menu.openMenu(%s) -> REJECTED, focus not acquired'):format(tostring(owner)))
    return false
  end

  MenuSerial = MenuSerial + 1
  menu.owner = owner
  menu.id = ('%s:%d'):format(tostring(owner), MenuSerial)

  Current = menu
  present(menu)
  print(('[nifty-core] menu.openMenu(%s) -> opened id=%s items=%d'):format(tostring(owner), menu.id, #menu.items))
  return true
end)

--- Replace the open menu with another, keeping focus. This is what a submenu is.
exports('pushMenu', function(...)
  local owner, menu = stripSelf(...)
  if type(menu) ~= 'table' or #menu.items == 0 then
    print(('[nifty-core] menu.pushMenu(%s) -> REJECTED, items=%s'):format(
      tostring(owner), tostring(type(menu) == 'table' and #menu.items or 'n/a')))
    return false
  end
  if Current == nil then
    print(('[nifty-core] menu.pushMenu(%s) -> no current, falling back to openMenu'):format(tostring(owner)))
    return exports['nifty-core']:openMenu(owner, menu)
  end

  menu.owner = owner
  menu.id = Current.id
  -- The PARENT MENU TABLE, not its id. `menuBack` hands this straight back to the
  -- renderer, and it used to receive `Current.parentId` - a string. The type check
  -- in `openMenu` rejected it, so going back from a submenu always failed.
  -- Inheriting the chain rather than setting one is what keeps three levels deep
  -- from losing its way to the root.
  menu.parent = Current.parent
  Current = menu
  present(menu)
  print(('[nifty-core] menu.pushMenu(%s) -> pushed id=%s items=%d'):format(tostring(owner), menu.id, #menu.items))
  return true
end)

--- Close whatever is open. Takes the token so a stale close cannot shut a menu the
--- player never opened: a menu whose id is `<owner>:<serial>`, and the page echoes
--- the id it was given, so "is this still the menu I was asked to close" is a
--- string compare rather than a guess.
local function close(current, reason)
  if current == nil then return false end

  Current = nil
  SendNUIMessage({ action = 'menuClose', data = { id = current.id, reason = reason or 'closed' } })
  Focus:release(RESOURCE)

  if type(current.onClose) == 'function' then
    local ok, err = pcall(current.onClose, reason)
    if not ok then print(('[%s] menu onClose failed: %s'):format(RESOURCE, tostring(err))) end
  end

  return true
end

exports('closeMenu', function(...)
  local owner, reason = stripSelf(...)
  if Current == nil or Current.owner ~= owner then return false end
  return close(Current, reason)
end)

exports('isOpen', function(...)
  return Current ~= nil
end)

exports('holder', function(...)
  return Current and Current.owner or nil
end)

-- ---------------------------------------------------------------------------
-- Page callbacks
--
-- These come from the browser. Everything they carry is untrusted: a value in a
-- slider callback is whatever the page says it is, and the RESOURCE that built the
-- menu is the one that must re-validate it before acting. The clamp below is
-- deliberately shallow — it keeps a page bug from producing an out-of-range value,
-- and it is not a rule.
-- ---------------------------------------------------------------------------

local function clamp(value, min, max, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  if value < min then return min end
  if value > max then return max end
  return value
end

--- Which item of the currently open menu has this id?
local function itemById(id)
  if Current == nil then return nil end
  for i, item in ipairs(Current.items) do
    if tostring(i) == tostring(id) then return item, i end
  end
  return nil
end

RegisterNUICallback('menuSelect', function(data, cb)
  if Current == nil or tostring(data.menuId) ~= Current.id then
    return cb({ ok = false })
  end

  local item = itemById(data.index)
  if item == nil then return cb({ ok = false }) end

  if item.kind == 'button' or item.kind == 'list' then
    if type(item.onSelect) == 'function' then
      local row = data.row or data.rowIndex
      local payload = nil
      if item.kind == 'list' and item.rows[row] then
        payload = item.rows[row].payload
      end
      pcall(item.onSelect, row, payload)
    end
  end

  cb({ ok = true })
end)

RegisterNUICallback('menuChange', function(data, cb)
  if Current == nil or tostring(data.menuId) ~= Current.id then
    return cb({ ok = false })
  end

  local item = itemById(data.index)
  if item == nil then return cb({ ok = false }) end

  if item.kind == 'checkbox' then
    item.checked = data.checked == true
    if type(item.onChange) == 'function' then pcall(item.onChange, item.checked) end
  elseif item.kind == 'slider' then
    local value = clamp(data.value, item.min, item.max, item.value)
    -- Re-aligned to the step, so a drag cannot produce a value the step forbids.
    value = item.min + (math.floor((value - item.min) / item.step + 0.5) * item.step)
    item.value = value
    if type(item.onChange) == 'function' then pcall(item.onChange, value) end
  elseif item.kind == 'select' then
    -- `data.index` is the ROW's index and is already spent finding `item`. The
    -- chosen position arrives as `data.value`, matching the slider branch. Using
    -- `data.index` here would select by row number, which on a nine-item list is a
    -- wrong answer that looks like a control that does not respond.
    local chosen = clamp(data.value, 1, math.max(1, #item.items), item.index)
    item.index = math.floor(chosen)
    if type(item.onChange) == 'function' then pcall(item.onChange, item.index, item.items[item.index]) end
  elseif item.kind == 'input' then
    -- The length clamp is the ONLY rule applied here, and it is not a policy: it
    -- keeps a paste of a novel from turning into a 4000-character name that the
    -- caller never sees and cannot refuse. Everything about whether the text is a
    -- valid NAME is the caller's question, asked on the server.
    local text = type(data.text) == 'string' and data.text or ''
    if #text > item.maxLength then text = text:sub(1, item.maxLength) end
    item.value = text
    if type(item.onChange) == 'function' then pcall(item.onChange, text) end
  end

  cb({ ok = true })
end)

--- A submenu is requested by the page, which has no Lua and therefore cannot
--- build one. The `build` callback supplied at construction time runs here, in the
--- resource that owns the data.
RegisterNUICallback('menuSubmenu', function(data, cb)
  if Current == nil or tostring(data.menuId) ~= Current.id then
    return cb({ ok = false })
  end

  local item = itemById(data.index)
  if item == nil or item.kind ~= 'submenu' or type(item.build) ~= 'function' then
    return cb({ ok = false })
  end

  local sub = item.build()
  if type(sub) ~= 'table' or #sub.items == 0 then return cb({ ok = false }) end

  sub.dock = sub.dock or Current.dock
  sub.parentId = Current.id
  -- The parent is kept as the object, because going back is "put the previous
  -- description on screen again" - not "look the id up somewhere".
  sub.parent = Current
  Current = sub
  present(sub)
  cb({ ok = true })
end)

--- The page asked to go back. Re-present the parent menu if there was one; a root
--- menu with no parent closes.
---
--- This deliberately does NOT go through `openMenu`. That refuses while a menu is
--- current, and a menu is always current here - so routing "back" through the same
--- entry point that opens menus made every Back press a no-op that still consumed
--- the keystroke. The player was stuck one level deep with no way out and no
--- explanation.
RegisterNUICallback('menuBack', function(_, cb)
  if Current == nil then return cb({ ok = false }) end
  if Current.parent == nil then
    close(Current, 'back')
    return cb({ ok = true })
  end

  local parent = Current.parent
  Current = parent
  present(parent)
  cb({ ok = true })
end)

--- The page's own close (Escape, the X, or Backspace at the root).
RegisterNUICallback('menuClosed', function(data, cb)
  if Current == nil or tostring(data.menuId) ~= Current.id then
    return cb({ ok = false })
  end
  close(Current, 'page')
  cb({ ok = true })
end)

--- A resource being restarted must not leave its menu open. `onResourceStop` fires
--- for the STOPPING resource, so the menu is closed when nifty-ui itself goes, and
--- the focus broker's `onClientResourceStop` handles the case where the OWNER goes
--- — which is why `close` takes the owner rather than assuming it is this one.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  Current = nil
end)

AddEventHandler('onClientResourceStop', function(resource)
  if Current == nil or Current.owner ~= resource then return end
  close(Current, 'owner-stopped')
end)

print(('[%s] menu framework ready'):format(RESOURCE))