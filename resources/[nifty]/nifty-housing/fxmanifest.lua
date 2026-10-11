fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-housing'
author 'Nifty Life 2.0'
description 'Property ownership, vehicles and the housing menu (ADR-0013).'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
  -- ADR-0016: interiors come from Bob74_IPL, ensured in server.cfg. This resource
  -- decides WHICH interior, not that IPLs can be loaded at all.
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/ownership.lua'
client_script 'client/cl_housing.lua'

dependencies {
  'nifty-core',
  'nifty-economy',
  'nifty-ui',
}
