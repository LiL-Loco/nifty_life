fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-ui'
author 'Nifty Life 2.0 (vendor: MrMathias154/NativeUILua-Reloaded)'
description 'NativeUI-Lua-Reloaded library (MrMathias154 fork). Vendored so other resources can load it via @nifty-ui/... paths. No exports, no client logic - just the library files and texture atlases.'
version '3.0.0'

-- Pure library resource. Other nifty resources (nifty-creator, nifty-core,
-- nifty-clothing) consume the NativeUI library directly via @nifty-ui/...
-- paths in their client_scripts. The export shim used to live here but
-- was removed when every caller moved to the lbg-char pattern of
-- loading the library in-process (no cross-resource boundary).
--
-- The source is MrMathias154's fork of NativeUILua-Reloaded (a fork of
-- dhawton's). The directory layout is flatter than the dhawton one
-- (base/, elements/, items/, panels/, share/, windows/ instead of
-- UIMenu/, UIElements/, UITimerBar/, UIProgressBar/, Wrapper/). The
-- public API (NativeUI.CreateMenu, CreateItem, CreateListItem, etc.)
-- is the same - no caller code needs to change beyond the file paths
-- in the manifests.
--
-- The texture atlases in stream/ are dhawton's - the MrMathias154 fork
-- does not ship them. They are the same GTA stock textures (commonmenu,
-- etc.) and the menu library looks for them by the exact same YTD names.
-- FiveM's streaming system registers them once from this resource and
-- every consumer's NativeUI.* call uses the registered copy.
dependencies { 'nifty-core' }

files {
  'stream/*.ytd',
}

-- Load order matches MrMathias154's __resource.lua.
-- 1. Share (utility helpers)
-- 2. Elements (Sprite, UIResText, UIResRectangle, etc.)
-- 3. Items (Item, Checkbox, List, Slider variants, Coloured, Progress)
-- 4. Windows (Heritage)
-- 5. Panels (Grid, Colour, Percentage)
-- 6. Base (UIMenu, MenuPool)
-- 7. NativeUI.lua (top-level NativeUI.* factory)
client_scripts {
  'share/Utils.lua',

  'elements/UIResRectangle.lua',
  'elements/UIResText.lua',
  'elements/Sprite.lua',
  'elements/StringMeasurer.lua',
  'elements/Badge.lua',
  'elements/Colours.lua',
  'elements/ColoursPanel.lua',

  'items/UIMenuItem.lua',
  'items/UIMenuCheckboxItem.lua',
  'items/UIMenuListItem.lua',
  'items/UIMenuSliderItem.lua',
  'items/UIMenuSliderHeritageItem.lua',
  'items/UIMenuColouredItem.lua',
  'items/UIMenuProgressItem.lua',

  'windows/UIMenuHeritageWindow.lua',

  'panels/UIMenuGridPanel.lua',
  'panels/UIMenuColourPanel.lua',
  'panels/UIMenuPercentagePanel.lua',

  'base/UIMenu.lua',
  'base/MenuPool.lua',

  'NativeUI.lua',
}
