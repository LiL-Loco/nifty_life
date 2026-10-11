# Own menu framework in NUI, Lemon-style API

We build our own menu library — LemonUI's API shape (`Menu`, `Checkbox`, `Slider`, `ListItem`, `Separator`, `SubMenu`, `Button`) — inside the NUI layer, as a reusable resource with exports. The character creator is its first consumer, not its only one.

## Why this and not LemonUI itself

LemonUI exists in three flavours, all checked on 2026-10-11:

- `LemonUI` (C#/.NET) — the original, MIT, 247 stars, actively maintained. Requires the .NET runtime in FXServer. We are Legacy + Lua 5.4 (ADR-0001), so it cannot load.
- `LemonUI_TS` (TypeScript) — MIT, actively maintained, but `package.json` declares **no React and no bundler**. It draws GTA-native menus through `@citizenfx/client`. It is a second implementation of the *native* approach, not an NUI component library.
- `LemonUI_Lua` — MIT, and **empty**: 2 KB, created and abandoned on 2022-05-20, never touched again.

So there is no LemonUI that drops into a `ui_page` on a Lua server. The gap is real and the answer is to close it ourselves rather than to port C# to Lua, which would be a rewrite producing something worse than the original.

The capability that motivates this is specific: **sliders and checkboxes**. Our character creator needs ~20 face-feature sliders, overlay toggles and colour pickers, and every other system will need the same primitives eventually (job lists, shop filters, housing options, admin toggles). One shared library, written once.

## What it is

`nifty-ui` grows into the project's single **menu surface**: it owns a `ui_page`, renders every menu, and arbitrates focus for everything on screen — menus, chat, phone, HUD.

That is a change of direction from the resource's original shape, and it is worth stating why. `nifty-ui` started life as shared CSS plus a focus broker with no `ui_page` on purpose: nothing to draw, only something to arbitrate. Once the character creator became a menu and nothing else, the menu needed a renderer, and the renderer belonging to the same resource that owns focus is what makes the model simple — **one menu browser, one focus owner.** Two resources each drawing menus would reintroduce exactly the contention the broker exists to prevent.

Everything else keeps its own surface, because none of them is a menu:

| Resource | Has `ui_page` | Why |
|---|---|---|
| `nifty-ui` | **yes** | Renders every menu; owns focus |
| `nifty-creator` | no | Builds a menu through exports |
| `nifty-chat` | yes | The log is always drawn, and must survive any menu opening |
| `nifty-phone` | yes | A persistent overlay, not a menu |
| `nifty-world` | yes | HUD is always drawn |

## What it does not change

**ADR-0002 stays.** No framework, on the server side, for player, character, money, inventory, job and state logic. This is a *presentation* library living in a browser. The rule being overridden was never "no libraries anywhere" — it was "do not depend on a core we cannot read or change".

**ADR-0011 stays.** Lua decides, NUI presents. Every menu is a projection of server state; the client never decides what is valid.

**Still no build step.** Plain HTML/CSS/JS, served from `ui_page`. No npm, no bundler, no TypeScript. This is the constraint that makes the own-implementation route viable at all.

## Consequences

- The **API shape is LemonUI's** — `Menu`, `Checkbox`, `Slider`, `ListItem`, `Separator`, `SubMenu`, `Button` — because that vocabulary is already the community standard and re-inventing the naming costs us and gains nothing. MIT permits it; we write our own implementation rather than copy theirs.
- A menu is a **client-side projection with a server decision behind it**. A checkbox is a boolean the server validates; a slider is a bounded integer the server validates. The menu draws and forwards, exactly like every other surface.
- Menus compose. A `SubMenu` is a nested menu, not a special case, because jobs and housing both need "category → list → detail" and building that three times is how UIs rot.
- Menus can be **docked, not only overlaid**. The character creator is the case that forces this: a player choosing a face needs to see the face. Because the menu is NUI and not a native GTA menu, it can occupy a column beside the ped instead of covering it. A native menu library cannot offer this at all — the panel is fullscreen by construction.
- Every surface still goes through the focus broker. A submenu opening is an acquire, not a steal.
- `nifty-creator` loses its `index.html`, `style.css` and `app.js`. Its entire interface is Lua that builds a menu.

## What we accept

We own this code forever. Every component is a maintenance cost with no upstream to pull fixes from, and a bug in the menu shows up in the creator, the phone, the shop and the admin panel at once. That is the same trade ADR-0002 already makes for the server core, taken deliberately for the presentation layer.

The alternative — LemonUI_TS — would have given us a maintained upstream and a documented API. It would also have cost the NUI layer entirely, brought a TypeScript toolchain into a Lua project, and removed the focus broker by replacing the thing it arbitrates. For a server whose whole UI is currently four pages of hand-written HTML, that is a large trade for a large dependency.