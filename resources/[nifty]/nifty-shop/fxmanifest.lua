fx_version 'cerulean'
game 'gta5'

name 'nifty-shop'
author 'Nifty Life 2.0'
description 'Buying, selling and the shop counter.'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/shop.lua'

-- Money and items are both touched here, so both systems must already exist.

dependencies {
  'nifty-core',
  'nifty-economy',
  'nifty-inventory',
}
