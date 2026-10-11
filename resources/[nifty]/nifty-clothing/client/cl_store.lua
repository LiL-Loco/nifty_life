--[[
  Clothing store menu.

  Triggered by cl_targets.lua when the player presses K inside a store's
  proximity radius. Two menu levels:

    * Slot picker - one row per (slot_id, label) that has priced items.
    * Per-slot item list - the server's `nifty:server:storeListForSlot`
      returns each (drawable, texture, name, price). The store menu shows
      these as buttons; clicking buys and equips the piece.

  Slot labels match the character creator (nifty-creator/client/cl_creator.lua
  COMPONENT_LABELS / PROP_LABELS) so the menus read like the same shop.

  Async pattern: opening the menu is synchronous. When a slot button is
  picked, the server is asked for the slot's items, the player waits in
  the slot-picker menu, and the response uses Menu:pushMenu to put the
  per-slot menu on screen. The push call is what actually shows the
  results; the slot menu stays up while the fetch is in flight.
]]

local RESOURCE = GetCurrentResourceName()

local Menu = exports['nifty-ui']

-- Mirrors nifty-creator/client/cl_creator.lua COMPONENT_LABELS / PROP_LABELS.
local COMPONENT_LABELS = {
  [1]  = 'Masken',
  [2]  = 'Haare',
  [3]  = 'Oberkoerper',
  [4]  = 'Hosen',
  [5]  = 'Schuhe',
  [7]  = 'Accessoires',
  [8]  = 'Unterhemden',
  [11] = 'Oberteile',
}

local PROP_LABELS = {
  [0] = 'Kopfbedeckung',
  [1] = 'Brille',
  [2] = 'Ohrring',
  [6] = 'Schmuck',
  [7] = 'Uhr',
}

local COMPONENT_SLOTS = { 1, 2, 3, 4, 5, 7, 8, 11 }
local PROP_SLOTS      = { 0, 1, 2, 6, 7 }

local function labelFor(kind, slot)
  if kind == 'component' then
    return COMPONENT_LABELS[slot] or ('Slot ' .. slot)
  end
  if kind == 'prop' then
    return PROP_LABELS[slot] or ('Slot ' .. slot)
  end
  return tostring(slot)
end

-- ----------------------------------------------------------------------------
-- Per-slot item list as a fresh menu (pushMenu).
-- ----------------------------------------------------------------------------

local function buildItemMenu(kind, slot, items)
  local menu = Menu.menu({ title = labelFor(kind, slot) .. ' kaufen' })
  menu.dock = 'right'

  if #items == 0 then
    Menu.button(menu, 'Aktuell nichts im Angebot', {
      disabled = true,
      description = 'Kein Preis fuer diese Stuecke gesetzt.',
    })
  else
    for _, item in ipairs(items) do
      local buttonLabel = (item.name or ('T-Shirt #' .. item.drawable))
        .. '  -$' .. tostring(item.price or 0)
      local itemCopy = item
      Menu.button(menu, buttonLabel, {
        description = ('Kauf und ziehe dieses Stueck direkt an.'),
        onSelect = function()
          local payload = {
            kind = kind,
            slot_id = slot,
            collection = '',
            drawable = itemCopy.drawable,
            texture = itemCopy.texture,
          }
          TriggerServerEvent('nifty:server:clothingPurchase', payload)

          -- Listen once for the response.
          local listener
          listener = RegisterNetEvent('nifty:client:clothingPurchase', function(data)
            RemoveEventHandler(listener)
            if data and data.ok then
              notify(('Gekauft fuer $' .. tostring(data.price or 0)))
              Menu.closeMenu(RESOURCE, 'purchased')
            else
              notify(('Kauf fehlgeschlagen: ' .. tostring(data and data.reason or 'unbekannt')))
            end
          end)
        end,
      })
    end
  end

  Menu.button(menu, 'Zurueck', {
    onSelect = function()
      Menu.closeMenu(RESOURCE, 'back')
    end,
  })

  return menu
end

-- ----------------------------------------------------------------------------
-- Slot picker (top level)
-- ----------------------------------------------------------------------------

local function openSlotPicker(kind)
  local slots = (kind == 'component') and COMPONENT_SLOTS or PROP_SLOTS

  local menu = Menu.menu({ title = 'Klamottenladen' })
  menu.dock = 'right'

  for _, slot in ipairs(slots) do
    local pickedKind, pickedSlot = kind, slot
    Menu.submenu(menu, labelFor(kind, slot), {
      build = function()
        -- Ask the server for the items, push the response when it arrives.
        TriggerServerEvent('nifty:server:storeListForSlot', {
          kind = pickedKind, slot_id = pickedSlot,
        })

        local listener
        listener = RegisterNetEvent('nifty:client:storeListForSlot', function(data)
          -- The fetch may have been replaced by a newer one (player picking
          -- different slots in quick succession). Echo keys match the
          -- request, so ignore responses that don't pair up.
          if type(data) ~= 'table'
            or data.kind ~= pickedKind
            or data.slot ~= pickedSlot
          then return end

          RemoveEventHandler(listener)
          Menu.pushMenu(RESOURCE, buildItemMenu(pickedKind, pickedSlot, data.items or {}))
        end)

        -- While the server's round-trip is in flight, push an empty menu
        -- so the submenu opens immediately. The fetch response above will
        -- replace it. A real "loading" row keeps the user confident
        -- something is happening.
        local placeholder = Menu.menu({ title = labelFor(pickedKind, pickedSlot) })
        Menu.button(placeholder, 'Lade ...', { disabled = true })
        return placeholder
      end,
    })
  end

  Menu.button(menu, 'Schliessen', {
    onSelect = function() Menu.closeMenu(RESOURCE, 'closed') end,
  })

  Menu.separator(menu, 'Oberteile sind der haeufigste Slot.')

  return menu
end

-- ----------------------------------------------------------------------------
-- Entry points
-- ----------------------------------------------------------------------------

RegisterNetEvent('nifty:client:openStore', function(storeId)
  if type(storeId) ~= 'number' then return end
  Menu.openMenu(RESOURCE, openSlotPicker('component'))
end)

RegisterCommand('+niftyclotheshop', function()
  Menu.openMenu(RESOURCE, openSlotPicker('component'))
end, false)
RegisterCommand('-niftyclotheshop', function() end, false)
RegisterKeyMapping('+niftyclotheshop', 'Nifty Life - Klamottenladen (debug)', 'keyboard', 'F7')

-- ----------------------------------------------------------------------------
-- Chat hook for status lines (the chat surface is server-driven)
-- ----------------------------------------------------------------------------

local function notify(message)
  if type(message) ~= 'string' then return end
  TriggerServerEvent('nifty:server:hoodNotice', message)
end
