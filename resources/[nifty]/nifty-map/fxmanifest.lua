fx_version 'cerulean'
game 'gta5'

name 'nifty-map'
author 'Nifty Life 2.0'
description 'Our own map resource. Replaces fivem-map-skater (Cfx example, skater rooftop spawns) with sensible GTA V locations. Spawnpoints use mp_m_freemode_01 so the Cfx forceRespawn flash is a normal freemode, not a skater; nifty-world then swaps to the character model.'
version '0.1.0'

-- The Cfx fivem-map-skater declared `gameTypes = { ['basic-gamemode'] = true }`.
-- basic-gamemode is the gametype we ensure; if we ever ship our own
-- (nifty-gamemode or similar), add it here and in the gametype's own
-- resource_type block. See docs/adr/ for what to look for in a gametype.
resource_type 'map' { gameTypes = { ['basic-gamemode'] = true } }

map 'map.lua'

games { 'gta5' }
lua54 'yes'
