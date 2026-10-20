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
  'ui/dist/index.html',
  'ui/dist/assets/*.js',
  'ui/dist/assets/*.css',
}

-- The panel is BUILT from ui-monorepo/packages/armwrestling (React + shadcn + Vite).
-- `ui/dist/**` is the build artefact and is committed deliberately: a FiveM
-- server is deployed from a checkout, so a gitignore rule that swallows dist/
-- would leave every `ui_page` pointing at a file that is not there.
--
-- To rebuild:
--   ssh root@<host> 'cd /root/ui-monorepo && bun install && bun run build:armwrestling'
--   then copy packages/armwrestling/dist over this resource's ui/dist and restart.
--
-- The Lua side is unchanged and still sends the same action names; the panel
-- types them through @nifty/bridge so a renamed action is a build error.


ui_page 'ui/dist/index.html'

dependencies {
  'nifty-core',
}
