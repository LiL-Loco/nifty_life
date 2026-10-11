fx_version 'cerulean'
game 'gta5'

name 'nifty-peeper'
author 'Nifty Life 2.0'
description 'Peeper — the in-world social network (ADR-0022).'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/sv_peeper.lua'

-- No ui_page. Peeper is a data surface: the feed is read by staff tooling and the
-- website (ADR-0022 binds the web side to the character, not the account), and the
-- in-game client for it is a later slice. Adding a page here before anything
-- renders through it would be exactly the "complete but unreachable" module that
-- LEARNINGS.md warns about.

dependencies {
  'nifty-core',
}
lua54 'yes'
