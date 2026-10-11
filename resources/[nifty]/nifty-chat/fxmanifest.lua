fx_version 'cerulean'
game 'gta5'
lua54 'yes'

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

-- The shared base (base.js, base.css) lives in nifty-core's `files` block
-- and is loaded by URL from there. The chat page references it via
-- `https://cfx-nui-nifty-core/ui/base.{js,css}` in the HTML and a CSS
-- @import in style.css. That resource declares the files in its own
-- `files` block, so the browser can fetch them. If nifty-core ever stops
-- the page renders unstyled rather than erroring, so the boot check looks
-- for the accent variable.

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/sv_chat.lua'
client_script 'client/cl_chat.lua'

-- `nifty-core` first because shared/core.lua calls into it during load.
dependencies {
  'nifty-core',
}

