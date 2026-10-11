fx_version 'cerulean'
game 'gta5'

name 'nifty-chat'
author 'Nifty Life 2.0'
description 'Proximity chat: server-authoritative author, radius and rate limit.'
version '0.1.0'

-- Replaces the downloaded `chat` resource, which shipped three hardcoded
-- `http://chat/...` URLs. FiveM serves NUI over HTTPS, so the browser blocked every
-- one of them as mixed content and the resource could not do anything. Two of its
-- files were also a Vue 2.3.3-era layout with no build step — code that predates
-- the NUI scheme by years.

-- Order is load order. `shared/core.lua` fetches the base facade into `Nifty`, and
-- the constants below rebuild `Nifty.newUuid` / `Nifty.Schema` locally — a table
-- returned across an export is a COPY, so a resource cannot rely on another
-- resource's runtime state and must hold its own.
shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/style.css',
  'ui/app.js',
}

-- The shared base lives in nifty-ui and is loaded by URL, not copied here. That is
-- the whole point of the split: one `nui()` helper, not ten copies that drift.
-- A CSS `@import` of another resource's file works only if THAT resource declares
-- it in its own `files` — which nifty-ui does. If it ever stops, the page renders
-- unstyled rather than erroring, so the boot check looks for the accent variable.

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/sv_chat.lua'
client_script 'client/cl_chat.lua'

-- `nifty-core` first because shared/core.lua calls into it during load. `nifty-ui`
-- because the chat input is a focus-holding surface like any other.
dependencies {
  'nifty-core',
  'nifty-ui',
}
