# Lua for game logic, HTML/CSS/JS for NUI

All game logic — server and client — is written in Lua (`fx_version 'cerulean'`, Lua 5.4, which has been the
default since June 2025 and where the deprecated `lua54` flag no longer applies). User interfaces are built
as NUI pages in ordinary HTML, CSS and JavaScript.

This inverts the recommendation made during design. Lua was chosen because the documentation, the natives
reference and essentially all RP examples are Lua — and this project is read-mostly against those sources
while hand-rolling its entire core (ADR-0002). Reading Lua is cheap for an experienced developer; the reverse
is not true, and every reference the project will need for the next two years is more likely to exist in Lua.

## The two-runtime boundary

NUI runs in a Chromium Embedded Framework context inside the game client. It is **not** the same runtime as the
Lua scripts and shares no memory with them — the only interface between them is the NUI callback bridge:

- game Lua → UI: Lua triggers a NUI message via `SendNUIMessage`
- UI → game Lua: JavaScript calls a registered callback via `fetch`

That bridge is a **trust boundary**, and it is the one most often built carelessly. Traffic crossing it from the
UI arrives client-side like any other client event, so per the "Secure Your Events" guidance it can be forged
by a cheat exactly as easily as a directly triggered event can. Anything the UI reports back — an item
selected, a form submitted, a price displayed — must be re-validated server-side against stored state rather
than trusted because it came through the UI.

## Consequences

- Two languages in the project, but with a clean line between them: Lua owns game state and rules, JavaScript
  owns presentation only. No game logic may live in NUI JavaScript, because it is client-side and forgeable.
- Adding UI later is comfortable — it is the same stack we already write professionally, and NUI is the
  standard choice over DUI for menus, inventory and HUD.
- Because NUI files must also be listed in `files {}` in `fxmanifest.lua` to be served, every UI page has a
  manifest touchpoint that is easy to forget.