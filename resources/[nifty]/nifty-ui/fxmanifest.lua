fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-ui'
author 'Nifty Life 2.0'
description 'Menu framework (zUI-v2) and NUI page, rebranded as a nifty system.'
version '1.0.0'

-- nifty-core is a dependency because the focus broker (cl_focus.lua in
-- nifty-core) is the single owner of SetNuiFocus; the shim routes every
-- zUI.ManageFocus call through exports['nifty-core']:acquire / :release.
dependencies { 'nifty-core' }

files {
  'ui/menu.html',
  'ui/menu.css',
  'ui/menu.js',
  'themes/*.json',
  'vendor/zui/themes/*.json',
}

ui_page 'ui/menu.html'

-- zUI-v2's own load order (per its upstream manifest):
-- triggerNuiEvent first (it declares the local-global),
-- then common.lua (declares zUI, MENUS, CURRENT_MENU, MENU_COUNTER),
-- then functions/getTheme, applyTheme, showInfoBox,
-- then menu/items/*.lua, menu/functions/*.lua, menu/main.lua.
-- nifty-ui's own scripts (theme_loader, shim) load AFTER zUI so the
-- shim's monkey-patch of zUI.ManageFocus runs after zUI is fully loaded.
client_scripts {
  'vendor/zui/functions/triggerNuiEvent.lua',
  'vendor/zui/common.lua',
  'vendor/zui/functions/getTheme.lua',
  'vendor/zui/functions/applyTheme.lua',
  'vendor/zui/functions/showInfoBox.lua',
  'vendor/zui/menu/items/_manager.lua',
  'vendor/zui/menu/items/button.lua',
  'vendor/zui/menu/items/checkbox.lua',
  'vendor/zui/menu/items/colorPicker.lua',
  'vendor/zui/menu/items/colorsList.lua',
  'vendor/zui/menu/items/line.lua',
  'vendor/zui/menu/items/linkButton.lua',
  'vendor/zui/menu/items/list.lua',
  'vendor/zui/menu/items/searchBar.lua',
  'vendor/zui/menu/items/separator.lua',
  'vendor/zui/menu/items/slider.lua',
  'vendor/zui/menu/items/textArea.lua',
  'vendor/zui/menu/functions/closeAll.lua',
  'vendor/zui/menu/functions/getCurrentMenu.lua',
  'vendor/zui/menu/functions/getHoveredItem.lua',
  'vendor/zui/menu/functions/goback.lua',
  'vendor/zui/menu/functions/goto.lua',
  'vendor/zui/menu/functions/isMenuOpen.lua',
  'vendor/zui/menu/functions/isVisible.lua',
  'vendor/zui/menu/functions/manageFocus.lua',
  'vendor/zui/menu/functions/onClosing.lua',
  'vendor/zui/menu/functions/onOpening.lua',
  'vendor/zui/menu/functions/registerMenu.lua',
  'vendor/zui/menu/functions/setDescription.lua',
  'vendor/zui/menu/functions/setIsClosable.lua',
  'vendor/zui/menu/functions/setSubtitle.lua',
  'vendor/zui/menu/functions/setTitle.lua',
  'vendor/zui/menu/main.lua',
  'client/theme_loader.lua',
  'client/shim.lua',
}

-- API-compatible shim. Same names cl_menu.lua used to expose.
-- Existing callers in nifty-creator, nifty-clothing, nifty-core/cl_spawn
-- import the namespace via `local Menu = exports['nifty-ui']` and call
-- the same methods.
exports {
  'menu',
  'button',
  'checkbox',
  'slider',
  'select',
  'list',
  'separator',
  'input',
  'submenu',
  'openMenu',
  'pushMenu',
  'closeMenu',
  'isOpen',
  'holder',
}
