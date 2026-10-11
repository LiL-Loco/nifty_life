fx_version 'cerulean'
game 'gta5'

name 'nifty-world'
author 'Nifty Life 2.0'
description 'The connect-to-play spine, the world client, the HUD and the panel shell.'
version '0.1.0'

-- This is the ORCHESTRATOR. It is the only resource allowed to know that the other
-- systems exist, because the connect-to-play sequence is the one flow that needs
-- all of them: create character -> reserve number -> grant inventory -> push
-- economy -> start the Stuetze -> send the client into the world.
--
-- Everything below it depends on nifty-core. Nothing below it knows about this file.

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
  -- SpawnPoints lives in appearance_config.lua, and sv_main.lua reads it to tell
  -- the client where to stand. Without this line the table is nil and the FIRST
  -- `enterWorld` of the session died on `SpawnPoints[...].x` - after login, in the
  -- middle of a flow that had already passed every gate.
  '@nifty-core/shared/appearance_config.lua',
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/style.css',
  'ui/app.js',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/sv_main.lua'
server_script 'server/sv_actions.lua'

-- Spawning is handled by Cfx's spawnmanager. nifty-world's enterWorld
-- handler arms it for death respawns and registers the character's home
-- as a spawn point so the respawn lands there too. There is no nifty
-- dependency on a spawn resource of our own.
client_script 'client/cl_identity.lua'
client_script 'client/cl_world.lua'

dependencies {
  'nifty-core',
  'nifty-spawn',
  'nifty-economy',
  'nifty-inventory',
  'nifty-phone',
  'nifty-shop',
  'nifty-jobs',
  'nifty-housing',
  'nifty-creator',
  'nifty-clothing',
  'nifty-ui',
}

server_only 'no'
