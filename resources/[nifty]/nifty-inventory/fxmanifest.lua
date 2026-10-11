fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-inventory'
author 'Nifty Life 2.0'
description 'Items, containers and the item catalogue.'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/inventory.lua'

-- The inventory panel lives entirely in this resource - including its
-- own ui_page. FiveM gives each ui_page its own CEF browser, so the
-- inventory opens in its own frame and does not share focus with the
-- rest of the HUD. cl_inventory.lua owns the focus state and pushes
-- inventory state to the NUI.
client_script 'client/cl_inventory.lua'

files {
  'ui/index.html',
  'ui/app.js',
  'ui/style.css',
}

ui_page 'ui/index.html'

dependencies {
  'nifty-core',
}
