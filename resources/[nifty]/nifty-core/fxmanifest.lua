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
-- Every visible surface belongs to the resource that owns it: the HUD in
-- nifty-world, the character creator in nifty-creator, the chat in nifty-chat,
-- the wardrobe and store in nifty-clothing, the inventory in nifty-inventory.
-- The base owns NONE of them. See the NO ui_page note further down for why
-- that is a correctness rule and not a preference.
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
-- Bootstraps sql/init.sql on first start. MUST load before any module that
-- reads from the database, so the queue order in `Db.ready` makes the schema
-- up before settings.lua reads its cache.
server_script 'server/sql_bootstrap.lua'
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
server_script 'server/sv_diag.lua'

-- client/cl_spawn.lua is GONE, deliberately, and it was not only dead weight.
--
-- It acquired the focus broker's single global slot from inside THIS resource:
--
--     local Focus = exports['nifty-core']
--     Focus:acquire(RESOURCE)        -- RESOURCE == 'nifty-core'
--
-- The broker granted it, wrote Holder = 'nifty-core', and then called
-- SetNuiFocus from a resource with no ui_page — the no-op that made the whole
-- broker useless. So it parked the only slot a real surface could ever get,
-- drew nothing (its ui_page went away with the rest of nifty-core's), and left
-- no way out: every later acquire from the creator, the chat or a phone was
-- refused. `openSpawnPicker` had no caller outside this file to begin with.
--
-- If a spawn picker is ever wanted it belongs in its own resource with its own
-- ui_page, the way qb-spawn and qb-multicharacter are separate from qb-core. The
-- five locations below are the gamemode-level spawnpoints and need nothing else.

-- NUI FOCUS IS NOT IN THIS RESOURCE ANY MORE, and it must not come back.
--
-- There was a focus broker here: client/cl_focus.lua arbitrated who held the
-- keyboard, and client/cl_focus_api.lua made the actual native call. Both are
-- deleted. Two independent reasons, and the second one is the real one:
--
-- 1. THE CALL NEVER WORKED FROM HERE. SetNuiFocus acts on the calling resource's
--    own CEF instance, and this resource deliberately declares no ui_page — every
--    ui_page is its own full-screen composited browser, and one parked here once
--    sat above the character creator and swallowed every click. With no CEF there
--    is nothing for the native to act on. Measured, same code, one client, two
--    contexts: thirty consecutive calls from here read `focused=false`, thirty out
--    of thirty; the identical line from nifty-creator read `focused=1` within
--    100 ms. The broker logged `granted`, returned true, and did nothing.
--
-- 2. A UI RESOURCE SHOULD NOT DEPEND ON ANOTHER ONE. Each resource that owns a
--    ui_page now makes its own two calls, so it can be read, changed, restarted
--    or deleted without knowing that anything else exists.
--
-- What is genuinely lost, stated once so nobody rediscovers it at 2am: nothing can
-- ask "who holds the keyboard right now?", so two surfaces that can be open at
-- once are arbitrated by whichever opened last. ox_inventory has the same
-- constraint and resolves it with `Wait(100)` and a hopeful comment.
--
-- The measurement from point 1 is written out at the focus block of every resource
-- that now owns its own: nifty-creator/client/cl_nui.lua and its four siblings.
client_script 'client/cl_welcome.lua'
client_script 'client/cl_variation.lua'

-- Only the schema is served from here now. The colour tokens and the NUI
-- helper were moved out: nifty-chat vendored its own copy, and no other
-- resource referenced them.
files {
  'sql/init.sql',
}

-- Default spawnpoints for the gamemode (was nifty-map/map.lua). These are what
-- the Cfx forceRespawn flash shows for a fresh character. The model is
-- mp_m_freemode_01 so the flash is a normal freemode; nifty-world's enterWorld
-- then swaps in the character's actual model.
--
-- shared/spawn.lua carries the same five locations as data for anything that
-- wants to reason about spawn points in Lua rather than read this list.
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

-- NO ui_page. This resource must never own a NUI page again.
--
-- Every ui_page is its own CEF browser, and FiveM composites ALL of them on top
-- of each other. A full-screen page parked here sat above the character
-- creator's frame and swallowed every click: the creator's panel was rendered
-- and visible, its buttons belonged to the frame underneath, and the clicks
-- landed on this one instead. The symptom — "the menu shows but nothing in it
-- responds" — pointed at focus, at CSS and at the camera for two hours, and
-- none of those were involved. Deleting this resource's iframe in the FiveM
-- devtools made the creator work immediately, which is what identified it.
--
-- The spawn picker that lived here is gone with the page: it had no working
-- callbacks of its own and was never reachable from the login flow. If it is
-- ever needed it belongs in its own resource, the way qb-spawn and
-- qb-multicharacter are separate from qb-core. What stays in the base is
-- exactly what qb-core keeps: no UI.

dependencies {
  '/onesync',
  '/server:4500',
}
