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

-- The inventory panel (4-section grid, togglable visibility) is part of
-- nifty-inventory because inventory IS what this resource owns. nifty-world
-- loads the script + stylesheet into its NUI page via cfx-nui URLs in
-- index.html - the CEF browser is shared, but the panel itself lives in
-- this resource's filesystem.
files {
  'ui/app.js',
  'ui/style.css',
}

dependencies {
  'nifty-core',
}
