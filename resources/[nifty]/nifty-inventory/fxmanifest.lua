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

dependencies {
  'nifty-core',
  'nifty-economy',
}
