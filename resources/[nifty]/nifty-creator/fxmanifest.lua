fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-creator'
author 'Nifty Life 2.0'
description 'Character creation: the allowlist, the creator UI and what the player picks (ADR-0017).'
version '0.2.0'

-- WHAT LIVES WHERE, AND WHY IT IS NOT ALL HERE
--
-- The validation rules and the appearance allowlist moved BACK to nifty-core
-- during the split, and that is not tidiness — it is a cycle they would otherwise
-- have created. `Identity.createCharacter` validates the name, the date of birth,
-- the gender, the appearance and the spawn point BEFORE writing a row. Put those
-- rules in this resource and nifty-core would have to reach into nifty-creator,
-- while nifty-creator already needs nifty-core for the database. Two resources
-- that each need the other to have started is a boot order with no valid first
-- element.
--
-- The split of responsibility that survives is:
--   nifty-core      what is LEGAL (validate.lua, appearance_config.lua)
--   nifty-creator   what is OFFERED and what the player CHOOSES (this resource)
--
-- which is exactly what ADR-0017 asked for in the first place — one file the
-- server enforces cannot drift from the one the UI offers, because there is only
-- one. The creator renders the allowlist it is handed; it does not define it.

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
  '@nifty-core/shared/appearance_config.lua',
}

-- THE INTERFACE IS A VANILLA-JS NUI, OWNED BY THIS RESOURCE.
--
-- The 2026-10-12 migration replaced the NativeUI-Lua-Reloaded menu surface
-- (cl_creator.lua lines 54-302, the entire `Menu = {}` wrapper) with a
-- dark-themed NUI styled after the inventory: gold #d6b469 accent, minimal
-- grid lines, hover gold borders, panel-stack navigation. cl_creator.lua
-- keeps the data engine; cl_nui.lua owns the NUI lifecycle and the
-- RegisterNUICallback handlers.
--
-- The NUI runs in CEF. SetNuiFocus is called through nifty-core's focus
-- broker (exports['nifty-core']:acquire / release), never directly. The
-- skin-cam UX uses bone-projection from Lua into the NUI (cl_nui.lua's
-- projectFaceBones thread).

-- The data folder is loaded BY THE SCRIPT, not by the manifest's shared_scripts.
-- It is nearly 8 MB of item names, restriction tags and torso mappings, and
-- decoding all of it at boot would cost every player who never opens a menu.
-- `cl_gamedata.lua` reads each file the first time something actually needs it.
files {
  'data/*.json',
  'data/tattoos/*.json',
  'ui/index.html',
  'ui/style.css',
  'ui/app.js',
  'ui/images/*.webp',
}

-- Load order: cl_labels.lua and cl_gamedata.lua first (they populate
-- `Labels` and `GameData`); then cl_creator.lua (the data engine); then
-- cl_nui.lua (the NUI driver that opens, refreshes, closes and registers
-- every NUI callback). cl_nui.lua must load AFTER cl_creator.lua because
-- it references every public helper there.
client_scripts {
  'client/cl_labels.lua',
  'client/cl_gamedata.lua',
  'client/cl_creator.lua',
  'client/cl_nui.lua',
}

-- NUI page. The CEF renders ui/index.html. The page is hidden until
-- openCreator sends an `open` message.
ui_page 'ui/index.html'

-- No server_script. Creating a character is now the website's job, through
-- create_character_from_web (migration 021); what is left here is appearance,
-- which the game server validates against AppearanceConfig and this resource only
-- offers.

dependencies {
  'nifty-core',
}
