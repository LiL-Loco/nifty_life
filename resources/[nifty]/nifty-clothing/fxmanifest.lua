fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-clothing'
author 'Nifty Life 2.0'
description 'Clothing system: per-character owned pieces, wardrobe (property-only), three-store catalogue, outfit presets.'
version '0.3.0'

-- core.lua first: it loads the facade and exposes Identity / Owned / Economy
-- on the `Nifty` global. Every file in this resource reads from there.
--
-- appearance_config.lua + config.lua after: their slot constants and tag
-- checks are referenced by both client and server files.
--
-- stores.lua + prices.lua last: pure data, no side effects.
shared_scripts {
  -- `@ox_lib/init.lua` FIRST: the shop proximity check uses `lib.points`. A
  -- resource cannot reference it before its shared_script block has run, and
  -- nifty-clothing is ensured before ox_lib is, so without this the order was
  -- luck rather than declaration.
  '@ox_lib/init.lua',
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
  '@nifty-core/shared/appearance_config.lua',
  'shared/config.lua',
  'shared/stores.lua',
  'shared/prices.lua',
  'shared/drop_props.lua',
}

server_script 'server/sv_clothing.lua'
server_script 'server/sv_owned.lua'
server_script 'server/sv_drops.lua'

-- 2026-10-12: NativeUI removed. The wardrobe renders through a vanilla-JS
-- NUI styled like nifty-inventory (dark theme, gold #d6b469 accent).
-- cl_nui.lua owns focus, push messages, and the RegisterNUICallback
-- handlers; cl_wardrobe.lua and cl_store.lua keep their data engine
-- (COMPONENT_LABELS, snapshotCurrent, getCurrentAppearance, etc.)
-- 2026-10-12: NativeUI removed entirely. The wardrobe and the
-- store both render through the same vanilla-JS NUI page, gated
-- by a `mode` field on the open message. wardrobe.js owns the
-- wardrobe UI; store.js owns the store UI. The NUI page is shared
-- because the focus broker holds one CEF per resource and the
-- two UIs are mutually exclusive (you can't be in the wardrobe
-- and the store at the same time).
files {
  'ui/dist/index.html',
  'ui/dist/assets/*.js',
  'ui/dist/assets/*.css',
}

-- The panel is BUILT from ui-monorepo/packages/clothing (React + shadcn + Vite).
-- `ui/dist/**` is the build artefact and is committed deliberately: a FiveM
-- server is deployed from a checkout, so a gitignore rule that swallows dist/
-- would leave every `ui_page` pointing at a file that is not there.
--
-- To rebuild:
--   ssh root@<host> 'cd /root/ui-monorepo && bun install && bun run build:clothing'
--   then copy packages/clothing/dist over this resource's ui/dist and restart.
--
-- The Lua side is unchanged and still sends the same action names; the panel
-- types them through @nifty/bridge so a renamed action is a build error.


-- Load order: cl_wardrobe.lua + cl_store.lua (data engine) before
-- cl_nui.lua (driver), because cl_nui.lua references the same state.
-- The shared focus API is deliberately NOT included here — see nifty-chat's
-- fxmanifest.lua for why a manifest `@` include is the wrong mechanism.
client_script 'client/cl_hood.lua'
client_script 'client/cl_targets.lua'
client_script 'client/cl_drops.lua'
client_script 'client/cl_wardrobe.lua'
client_script 'client/cl_store.lua'
client_script 'client/cl_nui.lua'

-- NUI page. The CEF renders ui/dist/index.html — the React build. The
-- hand-written ui/index.html, ui/store.js, ui/wardrobe.js and ui/style.css are
-- gone. The page is hidden until
-- the wardrobe NUI driver sends an `open` message.
ui_page 'ui/dist/index.html'

dependencies {
  'ox_lib',
  'nifty-core',
  'nifty-world',
  'nifty-chat',
  'ox_target',
}
