fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-core'
author 'Nifty Life 2.0'
description 'Base layer: persistence, settings, identity, sessions. Every system resource builds on this.'
version '0.2.0'

-- This is the BASE resource, not a system. It owns the database, the settings
-- cache, identity and the session guard, and it owns NO gameplay system.
--
-- `ui_page` is GONE from this file. The HUD moved to nifty-world, the creator to
-- nifty-creator, the phone to nifty-phone and the chat to nifty-chat — each with
-- its own page, which is why nifty-ui exists to arbitrate focus between them.
--
-- What the base still must not do: reach into a system. `sv_facade.lua` is the
-- one place a system may reach in, and it hands out data access, not behaviour.

-- Appearance allowlist and spawn points are shared on purpose: the creator
-- offers only what the server will accept, and one file cannot drift (ADR-0017).
-- Both are loaded by nifty-creator as well, because a player cannot pick a spawn
-- point the base has not defined.
shared_scripts {
  'shared/constants.lua',
  'shared/appearance_config.lua',
  'shared/spawn.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/db.lua'
server_script 'server/settings.lua'
server_script 'server/validate.lua'

-- Before every module that registers teardown with it. The guard owns the
-- playerDropped handler, so anything loading after it must not hook the event
-- itself (OneSync big mode does not guarantee it fires).
server_script 'server/sv_session_guard.lua'

server_script 'server/identity.lua'

-- Economy (was nifty-economy, absorbed). Loads before facade so the facade can
-- publish Economy and Stuetze by reference.
server_script 'server/economy/economy.lua'
server_script 'server/economy/stuetze.lua'

-- Jobs (was nifty-jobs, absorbed). Loads after economy because Jobs.startDuty
-- debits a payslip fee via Economy.debit; needs Economy already in scope.
server_script 'server/jobs.lua'

-- LAST. It captures Db, GetSetting, Identity and the rest as they are at this
-- moment, so loading it earlier would publish a facade containing nil.
server_script 'server/sv_facade.lua'

-- nifty-spawn (absorbed). Runs on the client only - server does not deal with
-- the spawn picker. cl_spawn.lua reads Spawn.Locations and Spawn.CAM_* from
-- shared/spawn.lua (loaded earlier in the shared_scripts block).
client_script 'client/cl_spawn.lua'

-- nifty-ui (absorbed). The focus broker (cl_focus) loads first; the menu
-- framework (cl_menu) loads after because its openMenu pulls focus through
-- cl_focus. cl_spawn's menu DSL calls go to the same resource and resolve
-- against cl_menu's exports.
client_script 'client/cl_focus.lua'
client_script 'client/cl_menu.lua'

-- The single NUI surface that every surface-level page renders against.
-- ui/menu.html is also the ui_page.
files {
  'ui/menu.html',
  'ui/menu.css',
  'ui/menu.js',
  'ui/base.css',
  'ui/base.js',
}

ui_page 'ui/menu.html'

-- Default spawnpoints for the gamemode (was nifty-map/map.lua). The picker
-- in cl_spawn.lua uses the same five locations from shared/spawn.lua; these
-- gamemode-level entries are what the Cfx forceRespawn flash shows for a
-- fresh character, before the picker takes over. The model is mp_m_freemode_01
-- so the flash is a normal freemode; nifty-world's enterWorld then swaps in the
-- character's actual model.
spawnpoint 'Legion Square' {
  pos = vector3(195.17, -933.77, 30.69),
  heading = 143.5,
  model = 'mp_m_freemode_01',
}
spawnpoint 'Vespucci Beach' {
  pos = vector3(-1290.0, -1480.0, 4.34),
  heading = 125.0,
  model = 'mp_m_freemode_01',
}
spawnpoint 'Paleto Bay' {
  pos = vector3(-260.0, 6630.0, 7.0),
  heading = 220.0,
  model = 'mp_m_freemode_01',
}
spawnpoint 'Sandy Shores' {
  pos = vector3(1950.0, 3720.0, 32.0),
  heading = 300.0,
  model = 'mp_m_freemode_01',
}
spawnpoint 'Flughafen' {
  pos = vector3(-1040.0, -2740.0, 20.0),
  heading = 330.0,
  model = 'mp_m_freemode_01',
}

-- ADR-0015: voice is Teamspeak, not an in-game resource. Nothing to load here.
-- ADR-0016: interiors are loaded by Bob74_IPL, ensured in server.cfg.
dependencies {
  '/onesync',
  '/server:4500',
}
