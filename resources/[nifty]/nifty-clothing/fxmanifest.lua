fx_version 'cerulean'
game 'gta5'

name 'nifty-clothing'
author 'Nifty Life 2.0'
description 'Worn clothing on the ped: the hood up/down toggle (ported from root-cause/ragemp-hood-up, MIT).'
version '0.1.0'

-- Load order matters twice over.
--
-- appearance_config.lua first: shared/config.lua reads MAX_DRAWABLE out of it to
-- bound a variant drawable, and a `nil` there would compare as false and reject
-- every variant as implausible.
--
-- shared/config.lua second: the client and the server both read Clothing.* at
-- load time, and a nil there is a silent no-op rather than an error.
shared_scripts {
  '@nifty-core/shared/constants.lua',
  '@nifty-core/shared/appearance_config.lua',
  'shared/config.lua',
}

server_script 'server/sv_clothing.lua'
client_script 'client/cl_hood.lua'

dependencies {
  'nifty-core',
  'nifty-world',
  'nifty-chat',
}

server_only 'no'