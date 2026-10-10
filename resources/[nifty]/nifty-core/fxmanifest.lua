fx_version 'cerulean'
game 'gta5'

name 'nifty-core'
author 'Nifty Life 2.0'
description 'Core runtime: persistence, identity, and the shared systems everything else builds on.'
version '0.1.0'

-- Appearance allowlist and spawn points are shared on purpose: the creator
-- offers only what the server will accept, and one file cannot drift (ADR-0017).
shared_scripts {
  'shared/constants.lua',
  'shared/appearance_config.lua',
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/style.css',
  'ui/app.js',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/db.lua'
server_script 'server/settings.lua'
server_script 'server/validate.lua'
server_script 'server/identity.lua'
server_script 'server/economy.lua'
server_script 'server/stuetze.lua'
server_script 'server/inventory.lua'
server_script 'server/ownership.lua'
server_script 'server/jobs.lua'
server_script 'server/shop.lua'
server_script 'server/phone.lua'
server_script 'server/peeper.lua'
server_script 'server/sv_main.lua'
server_script 'server/sv_actions.lua'

client_script 'client/cl_identity.lua'
client_script 'client/cl_creator.lua'
client_script 'client/cl_world.lua'
client_script 'client/cl_housing.lua'
client_script 'client/cl_phone.lua'

-- ADR-0015: voice is Teamspeak, not an in-game resource. Nothing to load here.
-- ADR-0016: interiors are loaded by Bob74_IPL, ensured in server.cfg.
dependencies {
  '/onesync',
  '/server:4500',
}

server_only 'no'