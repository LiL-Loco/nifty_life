fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-armwrestling'
author 'Nifty Life 2.0'
description 'Arm-wrestling minigame. Two players at a table, server-authoritative winner.'
version '0.1.0'

-- The world already has prop_arm_wrestle_01 at the positions in shared/positions.lua;
-- we do NOT spawn it. The decompiled RAGE script behaves the same way: it locates
-- the nearest table within 8 m of a given coordinate, never CREATE_OBJECTs a new one.

shared_script 'shared/positions.lua'

client_scripts {
  'client/cl_armwrestling.lua',
}

server_script 'server/sv_armwrestling.lua'

files {
  'ui/index.html',
  'ui/style.css',
  'ui/script.js',
}

ui_page 'ui/index.html'

dependencies {
  'nifty-core',
}
