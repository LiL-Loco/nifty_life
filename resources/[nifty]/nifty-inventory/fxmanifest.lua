fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-inventory'
author 'Nifty Life 2.0'
description 'Items, containers and the item catalogue.'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/inventory.lua'

-- The inventory panel lives entirely in this resource - including its
-- own ui_page. FiveM gives each ui_page its own CEF browser, so the
-- inventory opens in its own frame and does not share focus with the
-- rest of the HUD. cl_inventory.lua owns the focus state and pushes
-- inventory state to the NUI.
-- The shared focus API is deliberately NOT included here — see nifty-chat's
-- fxmanifest.lua for why a manifest `@` include is the wrong mechanism.
client_script 'client/cl_inventory.lua'

files {
  'ui/dist/index.html',
  'ui/dist/assets/*.js',
  'ui/dist/assets/*.css',
}

-- The panel is BUILT from ui-monorepo/packages/inventory (React + shadcn + Vite).
-- `ui/dist/**` is the build artefact and is committed deliberately: a FiveM
-- server is deployed from a checkout, so a gitignore rule that swallows dist/
-- would leave every `ui_page` pointing at a file that is not there.
--
-- To rebuild:
--   ssh root@<host> 'cd /root/ui-monorepo && bun install && bun run build:inventory'
--   then copy packages/inventory/dist over this resource's ui/dist and restart.
--
-- The Lua side is unchanged and still sends the same action names; the panel
-- types them through @nifty/bridge so a renamed action is a build error.


ui_page 'ui/dist/index.html'

dependencies {
  'nifty-core',
}
