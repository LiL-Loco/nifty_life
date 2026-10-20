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

ui_page 'ui/dist/index.html'

-- The panel is BUILT from ui-monorepo/packages/chat (React + shadcn + Vite).
-- `ui/dist/**` is the build artefact and is committed deliberately: a FiveM
-- server is deployed from a checkout, so a gitignore rule that swallows dist/
-- would leave every `ui_page` pointing at a file that is not there.
--
-- To rebuild after changing the panel:
--   ssh root@<host> 'cd /root/ui-monorepo && bun install && bun run build:chat'
--   ssh root@<host> 'cd /home/fivem/server-data/resources/[nifty]/nifty-chat \
--     && rm -rf ui/dist && cp -r /root/ui-monorepo/packages/chat/dist ui/dist \
--     && chown -R fivem:fivem ui'
--
-- The hand-written `ui/index.html`, `ui/app.js`, `ui/style.css` are gone; the
-- Lua side below is unchanged and still sends `chatLine` / `chatSystem` /
-- `chatInput`, which the panel now types through @nifty/bridge.
files {
  'ui/dist/index.html',
  'ui/dist/assets/*.js',
  'ui/dist/assets/*.css',
}

-- HISTORY worth keeping: this resource used to load
-- `https://cfx-nui-nifty-core/ui/base.js` by absolute URL and @import the
-- matching stylesheet. That single cross-resource coupling is what turned
-- nifty-core into a UI layer — and because a resource owning a visible CEF
-- page composites ABOVE every other resource's frame, the spawn page parked
-- there covered the character creator and swallowed its clicks.
--
-- The vendored copies existed only as an intermediate step. The panel is now
-- built from `ui-monorepo/packages/chat`, and `@nifty/ui` is a BUILD-time
-- dependency imported in source — it never crosses a frame boundary, because
-- bundling it into `ui/dist/` means the browser resolves it relative to this
-- page and cannot be talked into fetching someone else's NUI host.

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/sv_chat.lua'
-- Focus is deliberately NOT shared with anything. cl_chat.lua makes its own
-- SetNuiFocus calls: that native only reaches a CEF from the resource that
-- declares a ui_page, and no other resource's ui_page is the right one to borrow.
client_script 'client/cl_chat.lua'

-- `nifty-core` first because shared/core.lua calls into it during load.
dependencies {
  'nifty-core',
}

