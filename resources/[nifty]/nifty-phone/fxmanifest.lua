fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-phone'
author 'Nifty Life 2.0'
description 'Phone — device, account, messages and calls (ADR-0018, -0020, -0021, -0022).'
version '0.1.0'

shared_scripts {
  'shared/core.lua',
  'shared/contract.lua',
  '@nifty-core/shared/constants.lua',
}

server_script '@oxmysql/lib/MySQL.lua'
-- Order is load-bearing: sv_events.lua calls into the other four at event time,
-- not at load time, so the only real requirement is that they are all present.
-- It is listed last because it is the only file that exports anything outward.
server_script 'server/sv_account.lua'
server_script 'server/sv_contacts.lua'
server_script 'server/sv_messages.lua'
server_script 'server/sv_calls.lua'
server_script 'server/sv_events.lua'

client_script 'client/cl_phone.lua'

-- The panel is built from ui-monorepo/packages/phone (React + shadcn + Vite) and
-- deployed by ui-monorepo/deploy.sh. The source of truth for the action names is
-- shared/contract.lua on this side and packages/phone/src/contract.ts on that
-- one; if they ever disagree, the build fails rather than the player seeing a
-- panel that answers nothing.
ui_page 'ui/dist/index.html'

files {
  'ui/dist/index.html',
  'ui/dist/assets/*.js',
  'ui/dist/assets/*.css',
}

-- `ox_target` is not needed: the phone is opened by USING the item, which goes
-- through nifty-inventory's use handler rather than by looking at something.
dependencies {
  'nifty-core',
  'nifty-inventory',
}