fx_version 'cerulean'
game 'gta5'

name 'nifty-spawn'
author 'Nifty Life 2.0'
description 'Spawn-location picker. Builds a menu through nifty-ui (Lemon-style) listing the spawn points, flies a cinematic camera to the one the player highlights, and hands the chosen coords back to the caller. The caller does the actual spawn.'
version '0.1.0'

-- Logik/Idee angelehnt an qb-spawn (qbcore-fivem/qb-spawn, GPL-3.0).
-- Nichts uebernommen oder uebersetzt - das Konzept eines Pickers ist
-- allgemein; unsere Umsetzung geht ueber das nifty-ui-Menuframework und
-- eine eigene Kamerafuehrung. Code ist eigenstaendig geschrieben.
shared_scripts {
  '@nifty-core/shared/constants.lua',
  'shared/config.lua',
}

client_script 'client/cl_spawn.lua'

dependencies { 'nifty-core', 'nifty-ui' }

server_only 'no'