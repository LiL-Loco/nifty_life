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

-- ---------------------------------------------------------------------------
-- 2026-10-12: The NUI driver (cl_nui.lua) opens the wardrobe through
-- a vanilla-JS NUI. The legacy NativeUI surface and the local _pool
-- are gone. This file keeps the data helpers (labelFor,
-- getCurrentAppearance, snapshotCurrent) and the /wardrobe command.
-- The Menu wrapper, the render thread, and the buildXxxMenu helpers
-- were all removed in the NUI migration.
-- ---------------------------------------------------------------------------

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

-- =================================================================
-- ENTRY POINTS
-- =================================================================
-- The /wardrobe command opens the NUI wardrobe (cl_nui.lua owns the
-- driver). The legacy NativeUI surface is gone; the only entry
-- point is the chat command. Property-only access is enforced by
-- nifty-housing, not here.

RegisterCommand('wardrobe', function()
  -- Trigger the NUI driver. The NUI's 'open' action sends the initial
  -- state. This file (cl_wardrobe.lua) keeps the data helpers for
  -- the rest of the resource; cl_nui.lua handles the surface.
  TriggerEvent('nifty:client:openWardrobe', {})
end, false)

RegisterKeyMapping('wardrobe', 'Nifty Life - Kleiderschrank', 'keyboard', 'F8')

print(('[%s] wardrobe ready (NUI surface)'):format(RESOURCE))
