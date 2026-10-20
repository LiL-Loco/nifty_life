fx_version 'cerulean'
game 'gta5'
lua54 'yes'

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

ui_page 'ui/dist/index.html'

files {
  'ui/dist/index.html',
  'ui/dist/assets/*.js',
  'ui/dist/assets/*.css',
}

-- The panel is BUILT from ui-monorepo/packages/world (React + shadcn + Vite).
-- `ui/dist/**` is the build artefact and is committed deliberately: a FiveM
-- server is deployed from a checkout, so a gitignore rule that swallows dist/
-- would leave every `ui_page` pointing at a file that is not there.
--
-- To rebuild:
--   ssh root@<host> 'cd /root/ui-monorepo && bun install && bun run build:world'
--   then copy packages/world/dist over this resource's ui/dist and restart.
--
-- The Lua side is unchanged and still sends the same action names; the panel
-- types them through @nifty/bridge so a renamed action is a build error.


server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/sv_main.lua'
server_script 'server/sv_actions.lua'

-- Spawning is handled by Cfx's spawnmanager. nifty-world's enterWorld
-- handler arms it for death respawns and registers the character's home
-- as a spawn point so the respawn lands there too. There is no nifty
-- dependency on a spawn resource of our own.
-- The shared focus API is deliberately NOT included here — see nifty-chat's
-- fxmanifest.lua for why a manifest `@` include is the wrong mechanism.
client_script '@nifty-core/client/cl_variation.lua'
client_script 'client/cl_identity.lua'
client_script 'client/cl_world.lua'

dependencies {
  'nifty-core',
  'nifty-inventory',
  'nifty-shop',
  'nifty-housing',
  'nifty-creator',
  'nifty-clothing',
}
