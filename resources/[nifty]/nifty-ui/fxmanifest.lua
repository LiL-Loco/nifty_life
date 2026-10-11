fx_version 'cerulean'
game 'gta5'

name 'nifty-ui'
author 'Nifty Life 2.0'
description 'The menu framework and the single NUI focus broker. One menu surface for the server.'
version '0.2.0'

-- ADR-0023.
--
-- This resource HAS a ui_page, which reverses what it was built for. It started as
-- shared CSS plus a focus broker with no page on purpose — nothing to draw, only
-- something to arbitrate. Once the character creator became a menu and nothing
-- else, the menu needed a renderer, and the renderer belonging to the same
-- resource that owns the keyboard is what keeps the model simple: ONE menu
-- browser, ONE focus owner.
--
-- Two resources each drawing their own menus would put two CEF browsers behind one
-- global SetNuiFocus. Last writer wins, and the player ends up steering a menu they
-- cannot see. That is the whole reason menus are lent out from here rather than
-- instantiated by each caller.

files {
  'ui/base.css',
  'ui/base.js',
  'ui/menu.css',
  'ui/menu.js',
}

ui_page 'ui/menu.html'

-- Order is load order. The broker first: cl_menu.lua acquires focus through it at
-- the moment a menu opens, and a nil Focus would turn every open into a silent
-- false rather than an error.
client_script 'client/cl_focus.lua'
client_script 'client/cl_menu.lua'

-- No server half. Focus is a client-side concern and a menu is a local projection —
-- nothing about opening a menu needs the server's permission, because a menu
-- decides nothing. Every value it carries is re-validated by the resource that
-- built it, on the server, before anything is stored or spent.

dependencies {
  '/onesync',
}

server_only 'no'