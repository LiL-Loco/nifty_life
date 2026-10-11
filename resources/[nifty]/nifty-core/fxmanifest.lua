fx_version 'cerulean'
game 'gta5'

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

-- LAST. It captures Db, GetSetting, Identity and the rest as they are at this
-- moment, so loading it earlier would publish a facade containing nil.
server_script 'server/sv_facade.lua'

-- No client_script, no ui_page. `cl_identity.lua` moved to nifty-world with the
-- rest of the play-side: the base decides WHO a player is, the world decides what
-- the client is told about it. A base that also pushed NUI messages would have to
-- know about the HUD, and the HUD is not the base's business.

-- ADR-0015: voice is Teamspeak, not an in-game resource. Nothing to load here.
-- ADR-0016: interiors are loaded by Bob74_IPL, ensured in server.cfg.
-- nifty-ui because the base hands out focus through it like every other surface.
dependencies {
  '/onesync',
  '/server:4500',
  'nifty-ui',
}

server_only 'no'