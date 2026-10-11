fx_version 'cerulean'
game 'gta5'

name 'nifty-phone'
author 'Nifty Life 2.0'
description 'The handset: numbers, messages and reports (ADR-0018, ADR-0021).'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/style.css',
  'ui/app.js',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/phone.lua'
client_script 'client/cl_phone.lua'

dependencies {
  'nifty-core',
  'nifty-inventory',
  'nifty-ui',
}

server_only 'no'
