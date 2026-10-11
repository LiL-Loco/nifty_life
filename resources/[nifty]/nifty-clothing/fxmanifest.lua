fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-clothing'
author 'Nifty Life 2.0'
description 'Clothing system: per-character owned pieces, wardrobe (property-only), three-store catalogue, outfit presets.'
version '0.2.0'

-- core.lua first: it loads the facade and exposes Identity / Owned / Economy
-- on the `Nifty` global. Every file in this resource reads from there.
--
-- appearance_config.lua + config.lua after: their slot constants and tag
-- checks are referenced by both client and server files.
--
-- stores.lua + prices.lua last: pure data, no side effects.
shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
  '@nifty-core/shared/appearance_config.lua',
  'shared/config.lua',
  'shared/stores.lua',
  'shared/prices.lua',
}

server_script 'server/sv_clothing.lua'
server_script 'server/sv_owned.lua'
server_script 'server/sv_drops.lua'

client_script 'client/cl_hood.lua'
client_script 'client/cl_targets.lua'
client_script 'client/cl_drops.lua'
client_script 'client/cl_wardrobe.lua'
client_script 'client/cl_store.lua'

dependencies {
  'nifty-core',
  'nifty-world',
  'nifty-chat',
  'ox_target',
}
