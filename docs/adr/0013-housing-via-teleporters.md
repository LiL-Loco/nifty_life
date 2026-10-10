# Housing: ~60 properties built from apartment interiors across multiple shells

Revised after research. The original estimate of ~12 assumed vanilla single-player residential interiors
were plentiful. They are not — the story missions contain roughly **seven** enterable dwellings. Reaching
~60 requires GTA Online apartment interiors, which are confirmed loadable in FiveM.

## What is actually available

**GTA Online apartment interiors load in FiveM.** They ship in the base game's `x64/dlcpacks/`
(`dlcapartments`), shared by the base install rather than Online-exclusive, so FiveM reads them from the
install directory. Two independent FiveM housing resources ship `apa_v_mp_h_01_a` as a working interior with
storage, delivery and wardrobe coordinates — a furnished apartment, not a teleport marker. This requires no
purchase and no custom assets, so it is consistent with the no-MLO decision (ADR-0012).

The naming family `apa_v_mp_h_01_a` … `apa_v_mp_h_08_c` gives **8 styles × 3 variants = 24 interiors**,
all confirmed present with explicit IPL names and coordinates.

**All 24 are in a single building — Eclipse Towers, Pillbox** — at three coordinate clusters
(`-786.87, 315.72, 217.63` / `-786.93, 315.68, 187.91` / `-774.02, 342.07, 196.69`). An interior exists only
where its building exists, so **these cannot be distributed across the map.** An earlier draft of this ADR
proposed pairing apartment interiors with unrelated building shells; that is wrong, and the plan has been
corrected. Geographic spread comes instead from the shell buildings listed below.

**Vanilla single-player dwellings (~9 confirmed):** Franklin's Aunt House, Franklin's Mansion, Michael's
House, Trevor's Trailer, Floyd's Apartment, Harvey Molina's Apartment (Janitor's House), Motor Motel room,
O'Neil Ranch, Madrazos Ranch, plus the Casino Penthouse and Lester's House.

**Trailers: exactly one.** Trevor's Trailer is the only enterable trailer in GTA V. `TrevorsMP` and
`TrevorsTrailerTidy` are dirty/clean states of the *same* trailer at the same coordinates, not two
properties. Sandy Shores, Grapeseed and Alamo Sea trailers are YMAP geometry with no interior. An earlier
reference to a "Stab City Trailer" is **refuted** — Stab City has no interior.

## The full 60-property plan

See [housing-catalogue.md](./housing-catalogue.md) for the complete list with IPL names, coordinates,
districts and tiers. Composition: 24 Eclipse Towers apartments, 15 office interiors reused as downtown and
Del Perro studios, 8 suburban house shells, 9 vanilla/rural dwellings, 3 northern bunkers, 1 Casino
Penthouse.

**Northern Los Santos remains structurally starved.** Paleto, Sandy Shores, Alamo Sea and Chumash have
almost no residential stock; bunkers are the only interior available there. They are framed as rough
hideouts rather than homes, which is honest about what they are.

## Consequences

- Housing ceases to be scarce at 60 properties against a 20–40 player base. Scarcity must be reintroduced by
  **tier**, not count — a plain apartment costs little, a premium property costs a lot — if housing is still
  meant to function as a wealth sink (ADR-0009).
- The full `apa_v_mp_h_*` set must be verified in CodeWalker's IPL browser before the property count is
  committed. **Invalid IPL names fail silently**, so a wrong assumption produces missing interiors with no
  error message anywhere.
- **24 of 60 properties sit in one building.** This cannot be fixed with stock assets. It is better handled
  by naming Eclipse Towers as a recognisable neighbourhood than by pretending the spread is even.
- Travis/Sandy Shores trailer exteriors remain visible in the world even though they cannot be entered. Players
  will try them. Decide in advance whether those doors lead anywhere or are simply absent.
- Scarcity is reintroduced by **tier**, not count. Free ownership with tiered rent and upkeep keeps the sink
  strong (ADR-0009) without stranding a broke player.