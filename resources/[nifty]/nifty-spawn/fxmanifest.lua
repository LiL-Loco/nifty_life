fx_version 'cerulean'
game 'gta5'

name 'nifty-spawn'
author 'Nifty Life 2.0'
description 'Player spawning - the complete Cfx spawnmanager replacement. Ensured before every other gameplay resource so its exports are available to anything that asks.'
version '0.1.0'

-- Load order: shared base first, then the appearance config (SpawnPoints is
-- defined there). The order of `ensure` in server.cfg puts this resource as
-- the first nifty-* that starts after nifty-core.
shared_scripts {
  '@nifty-core/shared/constants.lua',
  '@nifty-core/shared/appearance_config.lua',
}

client_script 'client/cl_spawn.lua'

dependencies { 'nifty-core' }

server_only 'no'