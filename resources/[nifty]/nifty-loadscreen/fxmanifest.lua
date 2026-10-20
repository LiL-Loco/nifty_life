--[[
  Nifty Life loading screen.

  Replaces the stock Cfx `example-loadscreen`. The stock one is a light beach
  photograph with a Bank-Gothic outline; this one is the same mark the website
  draws (see website/src/app/globals.css, `.hero` and `.hero-mark-*`), so the
  first thing a player sees before they ever reach the site already looks like
  it.

  The brand is copied, not imported: the website is a Tailwind/Next pipeline and
  CEF renders one plain stylesheet with no build step (ADR-0002). The duplicated
  values are called out in `loadscreen.css` under "MIRRORED FROM globals.css" —
  a brand change has to be made in both files, and that is deliberate rather
  than accidental.

  This resource is deliberately NIGHTMARE-FREE: no Lua at all. The loading
  screen runs before any script VM exists, so every byte here is JS/CSS that the
  client downloads once and reuses for every join.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nifty-loadscreen'
author 'Nifty Life 2.0'
description 'The website look, as the loading screen.'
version '0.1.0'

files {
  'index.html',
  'loadscreen.css',
  'loadscreen.js',
}

loadscreen 'index.html'