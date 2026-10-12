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
-- `ui_page` was removed in 2025-09. The HUD lives in nifty-world, the
-- creator in nifty-creator, the phone in nifty-phone and the chat in
-- nifty-chat - each with its own page, which is why nifty-ui exists
-- to arbitrate focus between them. The 2026-10-12 NUI migration
-- brought the spawn picker back into nifty-core (it was native-menu
-- before) and the picker now uses the ui/spawn.html page.
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

-- Owned module (per-character clothing pieces). Loads before the facade for
-- the same reason Economy/Stuetze do: the facade publishes Owned by reference.
server_script 'server/clothing.lua'

-- LAST. It captures Db, GetSetting, Identity and the rest as they are at this
-- moment, so loading it earlier would publish a facade containing nil.
server_script 'server/sv_facade.lua'

-- nifty-spawn (absorbed). Runs on the client only - server does not deal with
-- the spawn picker. cl_spawn.lua reads Spawn.Locations and Spawn.CAM_* from
-- shared/spawn.lua (loaded earlier in the shared_scripts block). The 2026-10-12
-- NUI migration replaced the legacy NativeUI menu with a vanilla-JS NUI
-- (ui/spawn.html, ui/spawn.js, ui/spawn.css).
client_script 'client/cl_spawn.lua'

-- The focus broker (cl_focus) stays here so chat and phone can keep using
-- it. The menu moved to nifty-ui (now vendored directly by every
-- resource that needs it).
client_script 'client/cl_focus.lua'
client_script 'client/cl_welcome.lua'

-- ui/base.css and ui/base.js stay: chat and phone still load base.js
-- for the Nifty.nui fetch helper, and base.css is the shared colour-token
-- file. The spawn picker uses its own NUI page (ui/spawn.*).
files {
  'ui/base.css',
  'ui/base.js',
  'ui/spawn.html',
  'ui/spawn.css',
  'ui/spawn.js',
}

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

-- Spawn picker page. The page is hidden until cl_spawn.lua acquires
-- focus and pushes an 'open' message. cl_welcome.lua / cl_focus.lua
-- arbitrate who owns the keyboard when both the welcome and the
-- picker are visible (the welcome opens first; the picker opens
-- after the player has picked a slot).
ui_page 'ui/spawn.html'

dependencies {
  '/onesync',
  '/server:4500',
}
