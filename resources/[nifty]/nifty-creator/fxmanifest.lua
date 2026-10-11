fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-creator'
author 'Nifty Life 2.0'
description 'Character creation: the allowlist, the creator UI and what the player picks (ADR-0017).'
version '0.1.0'

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

-- THE INTERFACE IS A NATIVE GTA MENU, OWNED BY THIS RESOURCE.
--
-- Earlier this resource borrowed nifty-ui's menu surface through exports.
-- That worked, but every cross-resource call went through FiveM's export
-- proxy, which (a) drops the first user arg and (b) deep-copies the
-- return value. The shim that papers over those quirks has its own bugs
-- and its own debugging loop. The pattern in lbg-char
-- (github.com/lambits/lbg-char) is to load the menu library directly
-- in the consumer resource: client_script '@nifty-ui/NativeUI.lua' and
-- the rest of the library files in load order, then use the NativeUI
-- global straight from the script. No cross-resource boundary, no
-- shim, no proxy quirks.
--
-- The library files come from nifty-ui via @nifty-ui/... paths, so the
-- vendored copy in nifty-ui stays the single source of truth. nifty-ui
-- itself is no longer a dependency - it is just the file path the
-- library is sourced from.
--
-- No `ui_page` here on purpose. A resource with a `ui_page` would be a
-- second focus owner, which is the exact thing the broker exists to
-- prevent. Native menus draw with GTA natives (DrawSprite, DrawText,
-- DrawRect) and never touch NUI focus.

-- The data folder is loaded BY THE SCRIPT, not by the manifest's shared_scripts.
-- It is nearly 8 MB of item names, restriction tags and torso mappings, and
-- decoding all of it at boot would cost every player who never opens a menu.
-- `cl_gamedata.lua` reads each file the first time something actually needs it.
files {
  'data/*.json',
  'data/tattoos/*.json'
}

-- The data folder is loaded BY THE SCRIPT, not by the manifest's shared_scripts.
-- It is nearly 8 MB of item names, restriction tags and torso mappings, and
-- decoding all of it at boot would cost every player who never opens a menu.
-- `cl_gamedata.lua` reads each file the first time something actually needs it.
--
-- The `stream/*.ytd` files are the texture atlases the menu library uses
-- (commonmenu, shop_arrows_upanddown, etc.). They must be in this resource's
-- `files` block so the GTA streaming system registers them. The same files
-- are also in nifty-ui's `files` block; registering the same textures from
-- two resources is harmless - the game picks the first registered copy.
files {
  'data/*.json',
  'data/tattoos/*.json',
  '@nifty-ui/stream/*.ytd',
}

-- Load order is significant. The menu library (`@nifty-ui/...` paths) must
-- load BEFORE cl_creator.lua, because cl_creator.lua references `NativeUI`
-- and `UIMenuSeparatorItem` as globals. cl_labels.lua and cl_gamedata.lua
-- are loaded first because they populate the `Labels` and `GameData`
-- globals that cl_creator.lua reads.
--
-- The library files come from nifty-ui rather than being vendored here, so
-- the canonical copy lives in one place. A new nifty-ui release updates
-- every consumer at once.
client_scripts {
  'client/cl_labels.lua',
  'client/cl_gamedata.lua',

  -- NativeUI-Lua-Reloaded library, loaded in the same order nifty-ui uses.
  '@nifty-ui/share/Utils.lua',

  -- UIVisual and UIMenuSeparatorItem are not in MrMathias154's repo; we
  -- do not use them, so the entries are gone.
  '@nifty-ui/elements/UIResRectangle.lua',
  '@nifty-ui/elements/UIResText.lua',
  '@nifty-ui/elements/Sprite.lua',

  '@nifty-ui/elements/Badge.lua',
  '@nifty-ui/elements/Colours.lua',
  '@nifty-ui/elements/ColoursPanel.lua',
  '@nifty-ui/elements/StringMeasurer.lua',

  '@nifty-ui/items/UIMenuItem.lua',
  '@nifty-ui/items/UIMenuCheckboxItem.lua',
  '@nifty-ui/items/UIMenuListItem.lua',
  '@nifty-ui/items/UIMenuSliderItem.lua',
  '@nifty-ui/items/UIMenuSliderHeritageItem.lua',
  '@nifty-ui/items/UIMenuColouredItem.lua',
  '@nifty-ui/items/UIMenuProgressItem.lua',
  -- UIMenuSliderProgressItem and UIMenuSeparatorItem are not in the
  -- MrMathias154 fork; we do not use them, so the entries are gone.

  '@nifty-ui/windows/UIMenuHeritageWindow.lua',

  '@nifty-ui/panels/UIMenuGridPanel.lua',
  '@nifty-ui/panels/UIMenuColourPanel.lua',
  '@nifty-ui/panels/UIMenuPercentagePanel.lua',

  '@nifty-ui/base/UIMenu.lua',
  '@nifty-ui/base/MenuPool.lua',

  '@nifty-ui/NativeUI.lua',

  'client/cl_creator.lua',
}

-- No server_script. Creating a character is now the website's job, through
-- create_character_from_web (migration 021); what is left here is appearance,
-- which the game server validates against AppearanceConfig and this resource only
-- offers.

dependencies {
  'nifty-core',
}
