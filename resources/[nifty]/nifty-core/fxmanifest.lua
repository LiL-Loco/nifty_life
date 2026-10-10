fx_version 'cerulean'
game 'gta5'

name 'nifty-core'
author 'Nifty Life 2.0'
description 'Core runtime: persistence, identity, and the shared systems everything else builds on.'
version '0.1.0'

shared_script 'shared/constants.lua'

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/db.lua'
server_script 'server/settings.lua'
server_script 'server/sv_main.lua'

client_script 'client/cl_main.lua'

-- ADR-0015: voice is Teamspeak, not an in-game resource. Nothing to load here.
-- ADR-0016: interiors are loaded by Bob74_IPL, ensured in server.cfg.
dependencies {
  '/onesync',
  '/server:4500',
}

server_only 'no'