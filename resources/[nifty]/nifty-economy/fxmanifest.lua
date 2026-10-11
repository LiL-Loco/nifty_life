fx_version 'cerulean'
game 'gta5'

name 'nifty-economy'
author 'Nifty Life 2.0'
description 'Wallets, transfers, and the Stütze (ADR-0009). Money is DECIMAL, never float.'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/economy.lua'
server_script 'server/stuetze.lua'

-- No ui_page. The money display belongs to the HUD (nifty-world); this resource
-- owns the numbers, not the pixels that show them.

dependencies {
  'nifty-core',
}
