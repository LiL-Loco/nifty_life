fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-clothing'
author 'Nifty Life 2.0'
description 'Clothing system: per-character owned pieces, wardrobe (property-only), three-store catalogue, outfit presets.'
version '0.2.0'

-- core.lua first: it loads the facade and exposes Identity / Owned / Economy
-- on the `Nifty` global. Every file in this resource reads from there.
--
-- appearance_config.lua + config.lua after: their slot constants and tag
-- checks are referenced by both client and server files.
--
-- stores.lua + prices.lua last: pure data, no side effects.
shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
  '@nifty-core/shared/appearance_config.lua',
  'shared/config.lua',
  'shared/stores.lua',
  'shared/prices.lua',
  'shared/drop_props.lua',
}

server_script 'server/sv_clothing.lua'
server_script 'server/sv_owned.lua'
server_script 'server/sv_drops.lua'

-- @nifty-ui/stream/*.ytd: texture atlases the menu library uses
-- (commonmenu, shop_arrows_upanddown, etc.). Must be in the files
-- block so the GTA streaming system registers them.
files {
  '@nifty-ui/stream/*.ytd',
}

-- The two menu-driven files (cl_wardrobe, cl_store) load the NativeUI
-- library directly via @nifty-ui/... paths, the lbg-char pattern. They
-- have their own local Menu table and MenuPool, independent of every
-- other resource's menu.
client_script 'client/cl_hood.lua'
client_script 'client/cl_targets.lua'
client_script 'client/cl_drops.lua'
client_script '@nifty-ui/share/Utils.lua'
client_script '@nifty-ui/elements/UIResRectangle.lua'
client_script '@nifty-ui/elements/UIResText.lua'
client_script '@nifty-ui/elements/Sprite.lua'
client_script '@nifty-ui/elements/Badge.lua'
client_script '@nifty-ui/elements/Colours.lua'
client_script '@nifty-ui/elements/ColoursPanel.lua'
client_script '@nifty-ui/elements/StringMeasurer.lua'
client_script '@nifty-ui/items/UIMenuItem.lua'
client_script '@nifty-ui/items/UIMenuCheckboxItem.lua'
client_script '@nifty-ui/items/UIMenuListItem.lua'
client_script '@nifty-ui/items/UIMenuSliderItem.lua'
client_script '@nifty-ui/items/UIMenuSliderHeritageItem.lua'
client_script '@nifty-ui/items/UIMenuColouredItem.lua'
client_script '@nifty-ui/items/UIMenuProgressItem.lua'
client_script '@nifty-ui/base/UIMenu.lua'
client_script '@nifty-ui/base/MenuPool.lua'
client_script '@nifty-ui/NativeUI.lua'
client_script 'client/_menu.lua'
client_script 'client/cl_wardrobe.lua'
client_script 'client/cl_store.lua'

dependencies {
  'nifty-core',
  'nifty-world',
  'nifty-chat',
  'ox_target',
}
