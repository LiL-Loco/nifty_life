# Housing Catalogue — 60 properties

Working plan for 61 residences across Los Santos, built only from stock GTA V assets (ADR-0012).
Every entry is a real IPL name or a real shell coordinate taken from the IPL reference. Nothing here is
invented; entries marked ⚠ need on-server verification before they are committed.

## How the stock actually breaks down

| Pool | Count | Distribution |
|---|---|---|
| `apa_v_mp_h_01_a` … `apa_v_mp_h_08_c` apartments | 24 | **All in Eclipse Towers, Pillbox** — one building |
| Residential shells (`Apartments NO IPL`) | 17 | Properly spread: downtown, Del Perro, Vinewood, Rockford, Davis |
| Vanilla single-player dwellings | ~9 | Scattered incl. Grapeseed, Little Seoul, Paleto, far north |
| Office interiors (`ex_dt1_*` / `ex_sm_*`) | 36 | 4 towers: Arcadius, Maze Bank, Lom Bank, Maze Bank West |
| Bunkers (`gr_case*_bunkerclosed`) | 12 | **The only stock option in far northern Los Santos** |

**The concentration problem is real:** 24 of 60 properties sit in one tower. This cannot be fixed with
stock assets. It is better handled by *naming and framing* — Eclipse Towers becomes a recognisable
neighbourhood — than by pretending the spread is even.

---

## District 1 — Eclipse Towers, Pillbox (24) · Premium tier

All eight styles × three variants. Coordinates: **A** `(-786.87, 315.72, 217.63)` ·
**B** `(-786.93, 315.68, 187.91)` · **C** `(-774.02, 342.07, 196.69)`

| Apartment | IPL |
|---|---|
| Modern 1 / 2 / 3 | `apa_v_mp_h_01_a` / `_01_c` / `_01_b` |
| Mody 1 / 2 / 3 | `apa_v_mp_h_02_a` / `_02_c` / `_02_b` |
| Vibrant 1 / 2 / 3 | `apa_v_mp_h_03_a` / `_03_c` / `_03_b` |
| Sharp 1 / 2 / 3 | `apa_v_mp_h_04_a` / `_04_c` / `_04_b` |
| Monochrome 1 / 2 / 3 | `apa_v_mp_h_05_a` / `_05_c` / `_05_b` |
| Seductive 1 / 2 / 3 | `apa_v_mp_h_06_a` / `_06_c` / `_06_b` |
| Regal 1 / 2 / 3 | `apa_v_mp_h_07_a` / `_07_c` / `_07_b` |
| Aqua 1 / 2 / 3 | `apa_v_mp_h_08_a` / `_08_c` / `_08_b` |

## District 2 — Downtown studios (9) · Entry tier

Office interiors reused as small flats. Desk-and-chair rooms read as studio apartments at low tier.

**Arcadius** `(-141.x, -620.9, 168.8)` — `ex_dt1_02_office_02b` Executive Rich · `_02c` Cool ·
`_02a` Contrast · `_01a` Old Spice Warm · `_01b` Classical · `_01c` Vintage

**Maze Bank Tower** `(-75.x, -827.x, 243.4)` — `ex_dt1_11_office_02b` Executive Rich · `_02c` Cool ·
`_02a` Contrast

## District 3 — Del Perro studios (6) · Entry tier

**Lom Bank** `(-1579.x, -565.x, 108.5)` — `ex_sm_13_office_02b` Executive Rich · `_02c` Cool · `_02a` Contrast

**Maze Bank West** `(-1392.x, -480.x, 72.0)` — `ex_sm_15_office_02b` Executive Rich · `_02c` Cool ·
`_02a` Contrast

## District 4 — Vinewood & Richman (4) · Standard

| Address | Coords | Note |
|---|---|---|
| Michael's House | `(-85, -785)` | Vanilla SP |
| 2044 North Conker Avenue | `(340.94, 437.18, 149.39)` | Shell ⚠ interior load unverified |
| 2045 North Conker Avenue | `(373.02, 416.11, 145.70)` | Shell ⚠ |
| 2133 Mad Wayne Thunder Drive | `(-1288.00, 440.75, 97.69)` | Shell ⚠ |

## District 5 — Vinewood Hills (2) · Premium

| Address | Coords |
|---|---|
| 3671 Whispymound Drive (Franklin's Mansion) | `(-169.29, 486.49, 137.44)` |
| 3655 Wild Oats Drive | `(-169.29, 486.49, 137.44)` ⚠ verify — listed near the same cluster |

## District 6 — Rockford Hills / Hillcrest (3) · Premium

`2862 Hillcrest Avenue (-676.13, 588.61, 145.17)` · `2868 Hillcrest Avenue (-763.11, 615.91, 144.14)` ·
`2874 Hillcrest Avenue (-857.80, 682.56, 152.65)` — all shells ⚠

## District 7 — Davis (2) · Standard

| Address | Coords |
|---|---|
| Franklin's Aunt House | `(-67, -809)` |
| 2677 Whispymound Drive | `(120.50, 549.95, 184.10)` ⚠ |

## District 8 — Outskirts & rural (8) · Character tier

| Address | Coords | Note |
|---|---|---|
| Trevor's Trailer | `(1975.55, 3820.54, 33.45)` | **The only enterable trailer in GTA.** `TrevorsMP` / `TrevorsTrailerTidy` are dirty/clean states of the *same* trailer, not two homes |
| The Motor Motel | `(152.26, -1004.47, -99.00)` | Vanilla |
| Floyd's Apartment, Little Seoul | — | Vanilla, mission-only ⚠ IPL name unconfirmed |
| Harvey Molina's Apartment | — | Vanilla, mission-only ⚠ IPL name unconfirmed |
| Madrazos Ranch | `(1399, 1150, 115)` | ⚠ |
| O'Neil Ranch | `(2469.03, 4955.28, 45.12)` | `farm` / `farm_int` / `farm_props` |
| Diamond Casino Penthouse | `(976.64, 70.30, 115.16)` | `vw_casino_penthouse` — luxury tier |
| Lester's House | `(1273.90, -1719.31, 54.77)` | |

## District 9 — Northern Los Santos (3) · Outlier tier

North is structurally starved — bunkers are the only stock interior up there. Thematically they are
underground military bunkers, so **frame them as rough hideouts, not homes**. This is the honest solution
rather than pretending the north has housing.

| Location | IPL | Coords |
|---|---|---|
| Paleto Bunker | `gr_case7_bunkerclosed` | `(-783.08, 5934.69, 24.31)` |
| Grapeseed Bunker | `gr_case5_bunkerclosed` | `(1823.96, 4708.14, 42.50)` |
| Chumash Bunker | `gr_case11_bunkerclosed` | `(-3180.47, 1374.19, 19.96)` |

**Total: 61.**

> **Correction (2026-10-11).** This document previously claimed 60. It listed 60 while
> counting Madrazos Ranch twice in the tier table, and the District 8 heading said 9
> against 8 listed rows. Counting what is actually written down gives 61, which is what
> `database/migrations/008_property_catalogue.sql` seeds and what the harness asserts.

---

## Tiers

Scarcity is reintroduced by **tier**, not by count — at 61 properties against a 20–40 player base there is no
scarcity left in the raw numbers.

| Tier | Count | Examples | Role | Storage |
|---|---|---|---|---|
| Luxury | 4 | Casino Penthouse, 3× Hillcrest | Top of the wealth sink | 25 |
| Premium | 26 | Eclipse Towers ×24, Vinewood Hills ×2 | Main housing market | 15 |
| Standard | 11 | North Conker ×2, Davis ×2, Mad Wayne Thunder, Michael's, Floyd's, Molina's, Motor Motel, trailer | Most players land here | 10 |
| Entry | 15 | Downtown ×9, Del Perro ×6 studios | Free-to-enter floor | 6 |
| Outlier | 5 | 3 bunkers, O'Neil Ranch, Madrazos Ranch | Rural/rough, geographically necessary | 8 |

Ownership is **free to own**; tier governs *rent and upkeep*, which is where the sink lives (ADR-0009).
A player never becomes permanently homeless, and wealth still costs something.

## Verification method

Use **Bob74_IPL** (ADR-0016) — toggle an IPL on, walk to the location, confirm the interior loads. This is
what the resource exists for, and it resolves every item below.

1. **All eight `apa_v_mp_h_*` styles load.** Names and coordinates come from the reference list, not from a
   confirmed load. Invalid IPL names fail *silently* — a missing apartment with no error.
2. **The eight suburban house shells actually carry interiors.** They are listed as `NO IPL`: the building
   exists in the map geometry, the interior is unconfirmed.
3. **Floyd's and Harvey Molina's IPL names.** Mission-only spaces, no IPL identified.
4. **3655 Wild Oats** — the coordinates in the reference sit almost on top of Franklin's Mansion
   (`-169.29, 486.49, 137.44`). Possible transcription error in the source; re-check.
5. **How the northern bunkers read in practice.** They may be unusable as housing and become criminal hideouts
   instead — decide before building around them.

Only the first two block the launch gate. The rest are quality-of-life items that can be resolved during
content work.

### How verification flips a row

`properties.is_active` is one flag and the catalogue has **two different kinds of gap**, which must not be
confused:

| Gap | Symptom | Effect |
|---|---|---|
| **Interior unverified** | The IPL name or shell has never been confirmed to load | `is_active = 0` — the residence does not exist as far as the game is concerned |
| **Door unmeasured** | The residence is real, but its street entrance was never measured | Stays `is_active = 1` and stays listed. `cl_housing` simply draws no marker and logs it |

The 15 studios are entirely door-unmeasured: their entrances appear here only as `(-141.x, -620.9, 168.8)`,
where `.x` is a gap in the source rather than a truncated digit. They are valid, confirmed interiors and they
must not be hidden for want of a coordinate.

The 11 entries marked ⚠ above are interior-unverified and are seeded with `is_active = 0`, so they do not appear
in `Ownership.listProperties` at all — an interior that fails to load silently produces no error, so an
unconfirmed house is worse than an absent one. Once an IPL has been seen to load:

```sql
UPDATE properties SET is_active = 1 WHERE code = 'nconker-2044';
```

The seed deliberately does **not** update `is_active` on re-run, so this flip is not undone by
re-applying the migration.

**Reference:** CodeWalker's IPL browser (`forge.plebmasters.de`) is the authoritative cross-check, but it is
JS-rendered and could not be queried programmatically.