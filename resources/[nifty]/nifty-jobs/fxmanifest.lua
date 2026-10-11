fx_version 'cerulean'
game 'gta5'

name 'nifty-jobs'
author 'Nifty Life 2.0'
description 'Job definitions, duty state and wage settlement.'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/jobs.lua'

dependencies {
  'nifty-core',
  'nifty-economy',
  'nifty-inventory',
}
