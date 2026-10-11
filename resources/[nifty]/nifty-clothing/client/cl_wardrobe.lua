--[[
  Wardrobe menu + outfits.

  Three panes:

    1. Top-level picker: a button per slot that has owned pieces, plus
       "Outfits ansehen" and "Outfit speichern".
    2. Slot list: every owned piece in that (kind, slot). One row per
       (drawable, texture) - select to wear, "Ablegen" removes the slot.
    3. Outfits: a list of names. Click to wear (apply), right-side menu
       for rename / delete. "Outfit speichern" snapshots the current
       loadout under a typed name.

  Access: property-only per the agreed design. nifty-housing does not yet
  expose a closet hook, so for V1 the menu is reached via the /wardrobe
  command. When nifty-housing adds the hook the prompt replaces the
  command. Until then, /wardrobe is logged at resource start so the gap
  is visible.
]]

local RESOURCE = GetCurrentResourceName()

local Menu = exports['nifty-core']

-- Slot labels - same table as in cl_store.lua. Keeping a copy here so the
-- wardrobe can be built without depending on the store loading first.
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
-- Current appearance snapshot
--
-- The wardrobe writes via `nifty:server:clothingEquip`, which calls
-- Identity.saveCharacter with the full new appearance. We need to know
-- the player's CURRENT appearance to make the swap. Comes from the
-- world's getCurrentAppearance export.
-- ----------------------------------------------------------------------------

local function getCurrentAppearance()
  local ok, appear = pcall(function()
    return exports['nifty-world']:getCurrentAppearance()
  end)
  if ok and type(appear) == 'table' then return appear end
  return { components = {}, props = {}, faceFeatures = {}, overlays = {},
           hairColour = { primary = 0, highlight = 0 },
           hairOverlay = nil, tattoos = {}, eyeColour = 0, headBlend = {} }
end

local function snapshotCurrent()
  local a = getCurrentAppearance()
  -- Make sure the world knows about our changes from the player's side.
  a.components = a.components or {}
  a.props = a.props or {}
  return a
end

-- ----------------------------------------------------------------------------
-- Slot picker (top level)
-- ----------------------------------------------------------------------------

local function openWardrobeRoot()
  -- Build an appearance-aware top-level menu. Showing only slots that have
  -- owned pieces is the next iteration; for V1 every slot is listed.
  local menu = Menu:menu({ title = 'Kleiderschrank' })
  menu.dock = 'right'

  Menu:separator(menu, 'Komponenten')

  for _, slot in ipairs(COMPONENT_SLOTS) do
    Menu:submenu(menu, labelFor('component', slot), {
      build = function() return buildSlotMenu('component', slot) end,
    })
  end

  Menu:separator(menu, 'Accessoires')

  for _, slot in ipairs(PROP_SLOTS) do
    Menu:submenu(menu, labelFor('prop', slot), {
      build = function() return buildSlotMenu('prop', slot) end,
    })
  end

  Menu:separator(menu, 'Outfits')

  Menu:submenu(menu, 'Outfits ansehen', {
    build = function() return buildOutfitsMenu() end,
  })

  Menu:button(menu, 'Outfit speichern', {
    description = 'Derzeitige Kleidung als benanntes Outfit speichern.',
    onSelect = function() Menu:pushMenu(RESOURCE, promptOutfitName()) end,
  })

  Menu:button(menu, 'Schliessen', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'closed') end,
  })

  return menu
end

-- ----------------------------------------------------------------------------
-- Per-slot menu (own + select)
-- ----------------------------------------------------------------------------

local function buildSlotMenu(kind, slot)
  local menu = Menu:menu({ title = labelFor(kind, slot) })
  menu.dock = 'right'

  -- Fetch owned pieces for this slot, then push the populated menu.
  TriggerServerEvent('nifty:server:wardrobeListForSlot', {
    kind = kind, slot_id = slot,
  })

  local listener
  listener = RegisterNetEvent('nifty:client:wardrobeListForSlot', function(data)
    if type(data) ~= 'table' or data.kind ~= kind or data.slot ~= slot then return end
    RemoveEventHandler(listener)
    Menu:pushMenu(RESOURCE, buildSlotItemMenu(kind, slot, data.items or {}))
  end)

  -- Placeholder while the fetch is in flight.
  Menu:button(menu, 'Lade ...', { disabled = true })
  Menu:button(menu, 'Zurueck', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'back') end,
  })
  return menu
end

local function buildSlotItemMenu(kind, slot, items)
  local menu = Menu:menu({ title = labelFor(kind, slot) })
  menu.dock = 'right'

  if #items == 0 then
    Menu:button(menu, 'Nichts im Kleiderschrank', { disabled = true,
      description = 'Kein Kleidungsstueck in diesem Slot. Kaufe im Laden oder Creator.' })
  else
    for _, item in ipairs(items) do
      local entry = item
      Menu:button(menu, entry.name or ('Drawable #' .. tostring(entry.drawable)), {
        description = ('Quelle: ' .. (entry.source or 'creator')
                      .. '. Anklicken zum Anziehen.'),
        onSelect = function() equipPiece(kind, slot, entry) end,
      })
    end
  end

  Menu:separator(menu, 'Aktionen')

  -- The "Ablegen" action drops this slot. For a component that's an empty
  -- object; for a prop it's index -1 (the engine treats that as no prop).
  -- For an accessory, the inventory mirror STAYS - only the "Hinwerfen"
  -- action below actually removes both at once.
  Menu:button(menu, 'Ablegen', {
    description = ('Dieses Teil ausziehen (Slot leer lassen).'),
    onSelect = function() unequipPiece(kind, slot) end,
  })

  -- Drop is the path that fully discards an accessory: unequips + removes
  -- the inventory row. Only show on slots that have an inventory mirror
  -- to drop (the accessory slots).
  local isAccessory = isAccessorySlot(kind, slot)
  if isAccessory then
    Menu:button(menu, 'Hinwerfen (wegwerfen)', {
      description = ('Ausziehen UND das Inventar-Item loswerden. '
                  .. 'Das Item ist hinterher weg - benutze "Ablegen", '
                  .. 'wenn du es behalten willst.'),
      onSelect = function() dropAccessory(kind, slot) end,
    })
  end

  Menu:button(menu, 'Zurueck', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'back') end,
  })

  return menu
end

-- ----------------------------------------------------------------------------
-- Equip / unequip
-- ----------------------------------------------------------------------------

local ACCESSORY_SLOTS = {
  component = { [1] = true },
  prop      = { [0] = true, [1] = true, [2] = true, [6] = true, [7] = true },
}

local function isAccessorySlot(kind, slot)
  local byKind = ACCESSORY_SLOTS[kind]
  if not byKind then return false end
  return byKind[slot] == true
end

local function dropAccessory(kind, slot)
  -- Tell the server to unequip the slot AND remove the matching
  -- inventory item. The server's `equippedDrop` handler does both.
  TriggerServerEvent('nifty:server:equippedDrop', {
    kind = kind, slot_id = slot,
  })

  local listener
  listener = RegisterNetEvent('nifty:client:equippedDrop', function(data)
    RemoveEventHandler(listener)
    if data and data.ok then
      notify(('Weggeworfen: ' .. labelFor(kind, slot)))
      Menu:closeMenu(RESOURCE, 'dropped')
    else
      notify(('Wegwerfen fehlgeschlagen: ' .. tostring(data and data.reason or 'unbekannt')))
    end
  end)
end

local function equipPiece(kind, slot, item)
  local a = snapshotCurrent()
  local slotKey = tostring(slot)
  if kind == 'component' then
    a.components[slotKey] = {
      collection = item.collection or '',
      drawable   = item.drawable,
      texture    = item.texture,
    }
  elseif kind == 'prop' then
    a.props[slotKey] = {
      collection = item.collection or '',
      drawable   = item.drawable,
      texture    = item.texture,
    }
  end

  TriggerServerEvent('nifty:server:clothingEquip', { appearance = a })
  notify(('Angezogen: ' .. tostring(item.name or item.drawable)))

  -- Listen for the response and apply locally if it succeeded.
  local listener
  listener = RegisterNetEvent('nifty:client:clothingEquip', function(data)
    RemoveEventHandler(listener)
    if data and data.ok then
      -- Local ped update: the server has the new loadout. The world's
      -- applyAppearance will catch up via the next autosave push; for
      -- an immediate visible result, mirror it through the world's
      -- applyAppearanceParts if exposed.
      Menu:closeMenu(RESOURCE, 'equipped')
    end
  end)
end

local function unequipPiece(kind, slot)
  local a = snapshotCurrent()
  local slotKey = tostring(slot)
  if kind == 'component' then
    a.components[slotKey] = { collection = '', drawable = 0, texture = 0 }
  elseif kind == 'prop' then
    a.props[slotKey] = { collection = '', drawable = -1, texture = 0 }
  end

  TriggerServerEvent('nifty:server:clothingEquip', { appearance = a })
  notify(('Slot ' .. labelFor(kind, slot) .. ' abgelegt.'))
  Menu:closeMenu(RESOURCE, 'unequipped')
end

-- ----------------------------------------------------------------------------
-- Outfits
-- ----------------------------------------------------------------------------

local function buildOutfitsMenu()
  local menu = Menu:menu({ title = 'Outfits' })
  menu.dock = 'right'

  TriggerServerEvent('nifty:server:outfitList', {})

  local listener
  listener = RegisterNetEvent('nifty:client:outfitList', function(list)
    RemoveEventHandler(listener)
    if type(list) ~= 'table' or #list == 0 then
      Menu:pushMenu(RESOURCE, emptyOutfitsMenu())
      return
    end

    local newMenu = Menu:menu({ title = 'Outfits' })
    newMenu.dock = 'right'
    for _, o in ipairs(list) do
      local outfit = o
      Menu:submenu(newMenu, outfit.name .. '  (' .. (outfit.pieces or 0) .. ')', {
        build = function() return buildOutfitActionsMenu(outfit) end,
      })
    end
    Menu:button(newMenu, 'Zurueck', {
      onSelect = function() Menu:closeMenu(RESOURCE, 'back') end,
    })
    Menu:pushMenu(RESOURCE, newMenu)
  end)

  Menu:button(menu, 'Lade ...', { disabled = true })
  Menu:button(menu, 'Zurueck', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'back') end,
  })
  return menu
end

local function emptyOutfitsMenu()
  local menu = Menu:menu({ title = 'Outfits' })
  menu.dock = 'right'
  Menu:button(menu, 'Noch keine Outfits gespeichert', { disabled = true,
    description = 'Speichere das erste ueber "Outfit speichern" im Kleiderschrank.' })
  Menu:button(menu, 'Zurueck', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'back') end,
  })
  return menu
end

local function buildOutfitActionsMenu(outfit)
  local menu = Menu:menu({ title = outfit.name })
  menu.dock = 'right'

  Menu:button(menu, 'Anziehen', {
    description = ('Wendet das Outfit an (' .. (outfit.pieces or 0) .. ' Teile).'),
    onSelect = function()
      TriggerServerEvent('nifty:server:outfitApply', { outfitId = outfit.id })
      local listener
      listener = RegisterNetEvent('nifty:client:outfitApply', function(data)
        RemoveEventHandler(listener)
        if data and data.ok then
          notify(('Outfit angezogen: ' .. outfit.name))
          Menu:closeMenu(RESOURCE, 'outfit-applied')
        elseif data and data.reason == 'piece_lost' then
          notify('Outfit enthaelt ein Stueck, das du nicht mehr besitzt.')
        else
          notify(('Outfit fehlgeschlagen: ' .. tostring(data and data.reason or 'unbekannt')))
        end
      end)
    end,
  })

  Menu:button(menu, 'Einpacken', {
    description = 'Outfit in das Inventar packen (ein Item, max 10 stapelbar).',
    onSelect = function()
      TriggerServerEvent('nifty:server:outfitPack', { outfitId = outfit.id })
      local listener
      listener = RegisterNetEvent('nifty:client:outfitPack', function(data)
        RemoveEventHandler(listener)
        if data and data.ok then
          notify(('Eingepackt: ' .. outfit.name))
          Menu:closeMenu(RESOURCE, 'outfit-packed')
        else
          notify(('Einpacken fehlgeschlagen: ' .. tostring(data and data.reason or 'unbekannt')))
        end
      end)
    end,
  })

  Menu:button(menu, 'Umbenennen', {
    onSelect = function()
      Menu:pushMenu(RESOURCE, openRenamePrompt(outfit))
    end,
  })

  Menu:button(menu, 'Loeschen', {
    description = 'Endgueltig loeschen.',
    onSelect = function()
      TriggerServerEvent('nifty:server:outfitDelete', { outfitId = outfit.id })
      notify(('Outfit geloescht: ' .. outfit.name))
      Menu:closeMenu(RESOURCE, 'outfit-deleted')
    end,
  })

  Menu:button(menu, 'Zurueck', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'back') end,
  })

  return menu
end

-- ----------------------------------------------------------------------------
-- Outfit name prompt
--
-- A two-step menu: type a name, save. We use the menu framework's input
-- row (Menu:input) to gather the name. The "save" button writes it.
-- ----------------------------------------------------------------------------

local function promptOutfitName()
  local menu = Menu:menu({ title = 'Outfit speichern' })
  menu.dock = 'right'

  -- Local state for the input row.
  local outfitName = ''

  Menu:input(menu, 'Name', {
    value = outfitName,
    placeholder = 'z.B. Alltag',
    maxLength = 64,
    onChange = function(text)
      outfitName = text or ''
    end,
  })

  Menu:button(menu, 'Speichern', {
    description = 'Speichert die derzeitige Kleidung unter diesem Namen.',
    onSelect = function()
      local a = snapshotCurrent()
      TriggerServerEvent('nifty:server:outfitSave', {
        name = outfitName,
        appearance = a,
      })

      local listener
      listener = RegisterNetEvent('nifty:client:outfitSave', function(data)
        RemoveEventHandler(listener)
        if data and data.ok then
          notify('Outfit gespeichert.')
          Menu:closeMenu(RESOURCE, 'outfit-saved')
        else
          notify(('Speichern fehlgeschlagen: ' .. tostring(data and data.reason or 'unbekannt')))
        end
      end)
    end,
  })

  Menu:button(menu, 'Abbrechen', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'cancelled') end,
  })

  return menu
end

-- Rename prompt: same shape as save, but calls outfitRename.
local function openRenamePrompt(outfit)
  local menu = Menu:menu({ title = outfit.name .. ' umbenennen' })
  menu.dock = 'right'
  local newName = outfit.name

  Menu:input(menu, 'Name', {
    value = newName,
    maxLength = 64,
    onChange = function(text) newName = text or '' end,
  })

  Menu:button(menu, 'Speichern', {
    onSelect = function()
      TriggerServerEvent('nifty:server:outfitRename', {
        outfitId = outfit.id, name = newName,
      })
      notify('Umbenannt.')
      Menu:closeMenu(RESOURCE, 'renamed')
    end,
  })

  Menu:button(menu, 'Abbrechen', {
    onSelect = function() Menu:closeMenu(RESOURCE, 'cancelled') end,
  })

  Menu:pushMenu(RESOURCE, menu)
end

-- ----------------------------------------------------------------------------
-- Entry points
-- ----------------------------------------------------------------------------

RegisterCommand('wardrobe', function()
  Menu:openMenu(RESOURCE, openWardrobeRoot())
end, false)

RegisterKeyMapping('wardrobe', 'Nifty Life - Kleiderschrank (debug)', 'keyboard', 'F8')

-- Surface a verbose start line if the housing hook is missing. Until
-- nifty-housing exposes `getOwnedProperty`, the wardrobe is reachable only
-- via /wardrobe.
print(('[%s] wardrobe property-hook missing, using command fallback'):format(RESOURCE))

-- ----------------------------------------------------------------------------
-- Chat hook
-- ----------------------------------------------------------------------------

local function notify(message)
  if type(message) ~= 'string' then return end
  TriggerServerEvent('nifty:server:hoodNotice', message)
end
