fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-ui'
author 'Nifty Life 2.0 (vendor: dhawton/NativeUILua_Reloaded)'
description 'Native-UI menu library for FiveM (GTA V native rendering, no NUI). Bridges NativeUILua-Reloaded into the nifty system.'
version '1.0.0'

-- nifty-core owns the focus broker (for chat and phone). The native-UI
-- menu does not need SetNuiFocus because it draws directly to the screen
-- with DrawSprite / DrawText / DrawRect, so there is no CEF to take focus
-- from. The broker stays in nifty-core/client/cl_focus.lua untouched.
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

  -- nifty's wrapper lives last so it can reach every global the library
  -- exposes. It re-exports the API in the same shape nifty's caller files
  -- already use (Menu.menu, Menu.button, ...) and provides the render
  -- thread that drives MenuPool.
  'client/nifty_wrap.lua',
}
