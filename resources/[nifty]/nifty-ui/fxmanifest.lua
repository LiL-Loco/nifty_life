fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-ui'
author 'Nifty Life 2.0 (vendor: dhawton/NativeUILua_Reloaded)'
description 'NativeUI-Lua-Reloaded library. Vendored so other resources can load it via @nifty-ui/... paths. No exports, no client logic - just the library files and texture atlases.'
version '2.0.0'

-- Pure library resource. Other nifty resources (nifty-creator, nifty-core,
-- nifty-clothing) consume the NativeUI library directly via @nifty-ui/...
-- paths in their client_scripts. The export shim used to live here but
-- was removed when every caller moved to the lbg-char pattern of
-- loading the library in-process (no cross-resource boundary).
--
-- The nifty-chat page still references a base.js that used to come from
-- this resource. That file was a CSS / NUI helper, not a menu concern;
-- chat and phone have their own NUI pages and do not need anything from
-- nifty-ui anymore.
--
-- FiveM's require resolver walks a resource-relative path; the @ prefix
-- means "starting from another resource's directory". So the consumer
-- reads
--   client_script '@nifty-ui/UIMenu/UIMenu.lua'
-- and FiveM looks at resources/[nifty]/nifty-ui/UIMenu/UIMenu.lua. The
-- consumer must list nifty-ui in its dependencies block for this to load.
dependencies { 'nifty-core' }

files {
  'stream/*.ytd',
}

-- Load order matches the original __resource.lua.
-- 1. Wrapper (utility helpers)
-- 2. UIElements (Sprite, UIResText, UIResRectangle, UIVisual)
-- 3. UIMenu elements (Badge, Colours, ColoursPanel, StringMeasurer)
-- 4. UIMenu items (Item, Checkbox, List, Slider variants, Coloured, Progress, Separator)
-- 5. UIMenu windows (Heritage)
-- 6. UIMenu panels (Grid, Colour, Percentage, Statistics, etc.)
-- 7. UIMenu (the main UIMenu class) and MenuPool
-- 8. UIProgressBar / UITimerBar pools
-- 9. NativeUI.lua (top-level NativeUI.* factory)
client_scripts {
  'Wrapper/Utility.lua',

  'UIElements/UIVisual.lua',
  'UIElements/UIResRectangle.lua',
  'UIElements/UIResText.lua',
  'UIElements/Sprite.lua',

  'UIMenu/elements/Badge.lua',
  'UIMenu/elements/Colours.lua',
  'UIMenu/elements/ColoursPanel.lua',
  'UIMenu/elements/StringMeasurer.lua',

  'UIMenu/items/UIMenuItem.lua',
  'UIMenu/items/UIMenuCheckboxItem.lua',
  'UIMenu/items/UIMenuListItem.lua',
  'UIMenu/items/UIMenuSliderItem.lua',
  'UIMenu/items/UIMenuSliderHeritageItem.lua',
  'UIMenu/items/UIMenuColouredItem.lua',
  'UIMenu/items/UIMenuProgressItem.lua',
  'UIMenu/items/UIMenuSliderProgressItem.lua',
  'UIMenu/items/UIMenuSeparatorItem.lua',

  'UIMenu/windows/UIMenuHeritageWindow.lua',

  'UIMenu/panels/UIMenuGridPanel.lua',
  'UIMenu/panels/UIMenuHorizontalOneLineGridPanel.lua',
  'UIMenu/panels/UIMenuVerticalOneLineGridPanel.lua',
  'UIMenu/panels/UIMenuColourPanel.lua',
  'UIMenu/panels/UIMenuPercentagePanel.lua',
  'UIMenu/panels/UIMenuStatisticsPanel.lua',

  'UIMenu/UIMenu.lua',
  'UIMenu/MenuPool.lua',

  'UITimerBar/UITimerBarPool.lua',
  'UITimerBar/items/UITimerBarItem.lua',
  'UITimerBar/items/UITimerBarProgressItem.lua',
  'UITimerBar/items/UITimerBarProgressWithIconItem.lua',

  'UIProgressBar/UIProgressBarPool.lua',
  'UIProgressBar/items/UIProgressBarItem.lua',

  'NativeUI.lua',
}
