-- ============================================================================
-- 008_property_catalogue.sql
-- Nifty Life 2.0 — the housing catalogue (ADR-0013)
--
-- ADR-0013: housing is DATA. A new residence is a new row in this table, never a
-- new Lua file, never a new subsystem. Everything below is stock GTA V geometry
-- (ADR-0012 — no purchased assets, no MLO).
--
-- ---------------------------------------------------------------------------
-- IDs are DERIVED, not random
-- ---------------------------------------------------------------------------
-- `properties.id` is CHAR(36). Nothing here uses UUID(), because a random UUID
-- would be re-issued on every re-run of this file and would orphan every row in
-- `property_owners` pointing at it. Ownership is a ROW (ADR-0013); a re-seed that
-- changes the property ID silently destroys the link and leaves a house that
-- belongs to nobody while the owner still believes otherwise.
--
-- So the ID is SHA1('nl2:housing:' || code), reshaped into UUID version 5 form
-- (the 13th hex digit forced to '5', the 17th to 'a'). Deterministic: same code
-- always yields the same ID, on every machine, in every environment.
--
-- ---------------------------------------------------------------------------
-- is_active is the verification flag, and is deliberately NOT updated on re-run
-- ---------------------------------------------------------------------------
-- `is_active = 0` means "the interior is not confirmed loadable yet" — the ⚠
-- entries in docs/housing-catalogue.md. `Ownership.listProperties` filters on
-- `is_active = 1`, so unverified houses are invisible rather than half-working:
-- an interior that silently fails to load gives no error, and a player who walks
-- into one finds himself standing in the world with no walls.
--
-- Bob74_IPL (ADR-0016) is how these get confirmed. A curator flips 0 -> 1 once
-- an interior has been seen to load. That flip must SURVIVE re-running this
-- file, so `is_active` is intentionally absent from the ON DUPLICATE clause.
-- Every other catalogue column IS updated, because the catalogue is their
-- source of truth.
--
-- ---------------------------------------------------------------------------
-- Deliberately empty columns
-- ---------------------------------------------------------------------------
-- `entrance_x/y/z` are NULL wherever docs/housing-catalogue.md records an
-- approximate coordinate (`(-141.x, -620.9, 168.8)`). Writing a rounded-off guess
-- into a DOUBLE makes it indistinguishable from a measured value, and a player
-- standing 40m from the door learns nothing about why.
--
-- `exit_x/y/z` are NULL for ALL rows. Teleporting into an IPL that has not been
-- confirmed to load puts the player in the void; the exit coordinates are part of
-- that verification, not before it. See ADR-0013.
--
-- `rent_amount` / `upkeep_amount` are 0.00. Ownership is free to obtain
-- (ADR-0013) and the TIER is supposed to govern the recurring sink (ADR-0009),
-- but the numbers themselves are a deferred economy pass (docs/PLAN.md). Writing
-- invented figures now would put fake numbers behind a live rent mechanic. They
-- are per-tier, so the pass is one UPDATE per tier.
--
-- COUNT: 61 residences. The catalogue document says 60; its District 8 heading
-- claimed 9 entries while listing 8, and its tier table counted Madrazos Ranch
-- twice. What is actually written down is 61, and that is what is seeded here.
-- ============================================================================

INSERT INTO properties
  (id, kind, code, name, district, tier, interior_ipl,
   entrance_x, entrance_y, entrance_z, storage_slots, is_active)
SELECT
  id,
  'housing', code, name, district, tier, ipl, x, y, z, slots, is_active
FROM (
  SELECT
    CONCAT(
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)),  1,  8), '-',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)),  9,  4), '-5',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)), 14,  3), '-a',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)), 18,  3), '-',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)), 21, 12)
    ) AS id,
    code, name, district, tier, ipl, x, y, z, slots, is_active
  FROM (
    -- -----------------------------------------------------------------------
    -- District 1 — Eclipse Towers, Pillbox (24) · premium
    -- All eight styles x three variants. Three entrance doors exist in the
    -- building; which door belongs to which variant is NOT confirmed, so
    -- variants 1/2/3 map to doors A/B/C in order. This is the single assumption
    -- in this migration that Bob74_IPL must check first.
    -- -----------------------------------------------------------------------
    SELECT 'ecl-modern-1' AS code, 'Eclipse Towers - Modern 1' AS name, 'Eclipse Towers' AS district,
           'premium' AS tier, 'apa_v_mp_h_01_a' AS ipl,
           -786.87 AS x, 315.72 AS y, 217.63 AS z, 15 AS slots, 1 AS is_active
    UNION ALL SELECT 'ecl-modern-2', 'Eclipse Towers - Modern 2', 'Eclipse Towers', 'premium', 'apa_v_mp_h_01_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-modern-3', 'Eclipse Towers - Modern 3', 'Eclipse Towers', 'premium', 'apa_v_mp_h_01_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-mody-1',    'Eclipse Towers - Mody 1',    'Eclipse Towers', 'premium', 'apa_v_mp_h_02_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-mody-2',    'Eclipse Towers - Mody 2',    'Eclipse Towers', 'premium', 'apa_v_mp_h_02_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-mody-3',    'Eclipse Towers - Mody 3',    'Eclipse Towers', 'premium', 'apa_v_mp_h_02_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-vibrant-1', 'Eclipse Towers - Vibrant 1', 'Eclipse Towers', 'premium', 'apa_v_mp_h_03_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-vibrant-2', 'Eclipse Towers - Vibrant 2', 'Eclipse Towers', 'premium', 'apa_v_mp_h_03_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-vibrant-3', 'Eclipse Towers - Vibrant 3', 'Eclipse Towers', 'premium', 'apa_v_mp_h_03_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-sharp-1',   'Eclipse Towers - Sharp 1',   'Eclipse Towers', 'premium', 'apa_v_mp_h_04_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-sharp-2',   'Eclipse Towers - Sharp 2',   'Eclipse Towers', 'premium', 'apa_v_mp_h_04_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-sharp-3',   'Eclipse Towers - Sharp 3',   'Eclipse Towers', 'premium', 'apa_v_mp_h_04_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-mono-1',    'Eclipse Towers - Monochrome 1',    'Eclipse Towers', 'premium', 'apa_v_mp_h_05_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-mono-2',    'Eclipse Towers - Monochrome 2',    'Eclipse Towers', 'premium', 'apa_v_mp_h_05_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-mono-3',    'Eclipse Towers - Monochrome 3',    'Eclipse Towers', 'premium', 'apa_v_mp_h_05_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-seductive-1', 'Eclipse Towers - Seductive 1', 'Eclipse Towers', 'premium', 'apa_v_mp_h_06_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-seductive-2', 'Eclipse Towers - Seductive 2', 'Eclipse Towers', 'premium', 'apa_v_mp_h_06_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-seductive-3', 'Eclipse Towers - Seductive 3', 'Eclipse Towers', 'premium', 'apa_v_mp_h_06_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-regal-1',   'Eclipse Towers - Regal 1',   'Eclipse Towers', 'premium', 'apa_v_mp_h_07_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-regal-2',   'Eclipse Towers - Regal 2',   'Eclipse Towers', 'premium', 'apa_v_mp_h_07_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-regal-3',   'Eclipse Towers - Regal 3',   'Eclipse Towers', 'premium', 'apa_v_mp_h_07_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-aqua-1',    'Eclipse Towers - Aqua 1',    'Eclipse Towers', 'premium', 'apa_v_mp_h_08_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-aqua-2',    'Eclipse Towers - Aqua 2',    'Eclipse Towers', 'premium', 'apa_v_mp_h_08_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-aqua-3',    'Eclipse Towers - Aqua 3',    'Eclipse Towers', 'premium', 'apa_v_mp_h_08_b', -774.02, 342.07, 196.69, 15, 1

    -- -----------------------------------------------------------------------
    -- District 2 — Downtown studios (9) · entry
    -- Office interiors reused as studios. Entrance coordinates are NULL: the
    -- catalogue records them only as (-141.x, -620.9, 168.8) and the .x is an
    -- ellipsis, not a truncated digit.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'dt-arcadius-rich',     'Arcadius - Executive Rich', 'Downtown', 'entry', 'ex_dt1_02_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-cool',     'Arcadius - Cool',           'Downtown', 'entry', 'ex_dt1_02_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-contrast', 'Arcadius - Contrast',       'Downtown', 'entry', 'ex_dt1_02_office_02a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-warm',     'Arcadius - Old Spice Warm', 'Downtown', 'entry', 'ex_dt1_01_office_01a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-classical','Arcadius - Classical',      'Downtown', 'entry', 'ex_dt1_01_office_01b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-vintage',  'Arcadius - Vintage',        'Downtown', 'entry', 'ex_dt1_01_office_01c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-rich',     'Maze Bank Tower - Executive Rich', 'Downtown', 'entry', 'ex_dt1_11_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-cool',     'Maze Bank Tower - Cool',           'Downtown', 'entry', 'ex_dt1_11_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-contrast', 'Maze Bank Tower - Contrast',       'Downtown', 'entry', 'ex_dt1_11_office_02a', NULL, NULL, NULL, 6, 1

    -- -----------------------------------------------------------------------
    -- District 3 — Del Perro studios (6) · entry
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'dp-lom-rich',          'Lom Bank - Executive Rich',      'Del Perro', 'entry', 'ex_sm_13_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-lom-cool',          'Lom Bank - Cool',                'Del Perro', 'entry', 'ex_sm_13_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-lom-contrast',      'Lom Bank - Contrast',            'Del Perro', 'entry', 'ex_sm_13_office_02a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-rich',    'Maze Bank West - Executive Rich', 'Del Perro', 'entry', 'ex_sm_15_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-cool',    'Maze Bank West - Cool',           'Del Perro', 'entry', 'ex_sm_15_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-contrast','Maze Bank West - Contrast',       'Del Perro', 'entry', 'ex_sm_15_office_02a', NULL, NULL, NULL, 6, 1

    -- -----------------------------------------------------------------------
    -- District 4 — Vinewood & Richman (4) · standard
    -- The three shells are marked `NO IPL` in the reference: the building exists
    -- in the map geometry, the interior is unconfirmed. Hence is_active = 0.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'vinewood-michael', 'Michael''s House', 'Vinewood / Richman', 'standard', NULL, -85.00, -785.00, NULL, 10, 1
    UNION ALL SELECT 'nconker-2044', '2044 North Conker Avenue', 'Vinewood / Richman', 'standard', NULL, 340.94, 437.18, 149.39, 10, 0
    UNION ALL SELECT 'nconker-2045', '2045 North Conker Avenue', 'Vinewood / Richman', 'standard', NULL, 373.02, 416.11, 145.70, 10, 0
    UNION ALL SELECT 'madwayne-2133', '2133 Mad Wayne Thunder Drive', 'Vinewood / Richman', 'standard', NULL, -1288.00, 440.75, 97.69, 10, 0

    -- -----------------------------------------------------------------------
    -- District 5 — Vinewood Hills (2) · premium
    -- Wild Oats carries the catalogue's warning that its coordinates sit almost
    -- exactly on top of Franklin's Mansion — probable transcription error, so
    -- it stays inactive until someone stands in both and finds out.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'whispymound-3671', '3671 Whispymound Drive', 'Vinewood Hills', 'premium', NULL, -169.29, 486.49, 137.44, 15, 1
    UNION ALL SELECT 'wildoats-3655',   '3655 Wild Oats Drive',   'Vinewood Hills', 'premium', NULL, -169.29, 486.49, 137.44, 15, 0

    -- -----------------------------------------------------------------------
    -- District 6 — Rockford Hills / Hillcrest (3) · luxury
    -- Shell entries, same reason as District 4.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'hillcrest-2862', '2862 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -676.13, 588.61, 145.17, 25, 0
    UNION ALL SELECT 'hillcrest-2868', '2868 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -763.11, 615.91, 144.14, 25, 0
    UNION ALL SELECT 'hillcrest-2874', '2874 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -857.80, 682.56, 152.65, 25, 0

    -- -----------------------------------------------------------------------
    -- District 7 — Davis (2) · standard
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'davis-aunt',        'Franklin''s Aunt House', 'Davis', 'standard', NULL, -67.00, -809.00, NULL, 10, 1
    UNION ALL SELECT 'davis-whispymound-2677', '2677 Whispymound Drive', 'Davis', 'standard', NULL, 120.50, 549.95, 184.10, 10, 0

    -- -----------------------------------------------------------------------
    -- District 8 — Outskirts & rural (8)
    -- The catalogue heading says 9. It lists 8. These 8 are what is written
    -- down, so these 8 are what exists.
    --
    -- Trevor's Trailer carries a note worth keeping: `TrevorsMP` and
    -- `TrevorsTrailerTidy` are the dirty and clean STATES of one trailer, not
    -- two residences. interior_ipl stays NULL because the interior is part of
    -- the base map and is entered by walking, not by loading an IPL.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'outskirts-trailer',  'Trevor''s Trailer',        'Outskirts', 'standard', NULL, 1975.55, 3820.54, 33.45, 10, 1
    UNION ALL SELECT 'outskirts-motel',    'The Motor Motel',          'Outskirts', 'standard', NULL, 152.26, -1004.47, -99.00, 10, 1
    UNION ALL SELECT 'outskirts-floyd',    'Floyd''s Apartment',       'Outskirts', 'standard', NULL, NULL, NULL, NULL, 10, 0
    UNION ALL SELECT 'outskirts-molina',   'Harvey Molina''s Apartment', 'Outskirts', 'standard', NULL, NULL, NULL, NULL, 10, 0
    UNION ALL SELECT 'outskirts-madrazos', 'Madrazos Ranch',           'Outskirts', 'outlier',  NULL, 1399.00, 1150.00, 115.00, 8, 0
    UNION ALL SELECT 'outskirts-oneil',    'O''Neil Ranch',            'Outskirts', 'outlier',  'farm', 2469.03, 4955.28, 45.12, 8, 1
    UNION ALL SELECT 'outskirts-casino',   'Diamond Casino Penthouse', 'Outskirts', 'luxury',   'vw_casino_penthouse', 976.64, 70.30, 115.16, 25, 1
    UNION ALL SELECT 'outskirts-lester',   'Lester''s House',          'Outskirts', 'standard', NULL, 1273.90, -1719.31, 54.77, 10, 1

    -- -----------------------------------------------------------------------
    -- District 9 — Northern Los Santos (3) · outlier
    -- North is structurally starved: bunkers are the only stock interior up
    -- there. Framed as rough hideouts rather than pretending the north has
    -- housing.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'bunker-paleto',    'Paleto Bunker',    'Northern Los Santos', 'outlier', 'gr_case7_bunkerclosed',  -783.08, 5934.69, 24.31, 8, 1
    UNION ALL SELECT 'bunker-grapeseed', 'Grapeseed Bunker', 'Northern Los Santos', 'outlier', 'gr_case5_bunkerclosed', 1823.96, 4708.14, 42.50, 8, 1
    UNION ALL SELECT 'bunker-chumash',   'Chumash Bunker',   'Northern Los Santos', 'outlier', 'gr_case11_bunkerclosed', -3180.47, 1374.19, 19.96, 8, 1
  ) AS seed
) AS property
ON DUPLICATE KEY UPDATE
  `name`          = VALUES(`name`),
  `district`      = VALUES(`district`),
  `tier`          = VALUES(`tier`),
  `interior_ipl`  = VALUES(`interior_ipl`),
  `entrance_x`    = VALUES(`entrance_x`),
  `entrance_y`    = VALUES(`entrance_y`),
  `entrance_z`    = VALUES(`entrance_z`),
  `storage_slots` = VALUES(`storage_slots`);
  -- `is_active` is intentionally NOT in this list — see the header. Re-running
  -- this migration must not undo an interior that Bob74_IPL has since confirmed.