-- ============================================================================
-- 027_clothing_prices.sql
-- Nifty Life 2.0 — per-(drawable, texture) clothing prices in the database
--
-- WHY THIS TABLE
--
-- The Lua `prices.lua` ships curated defaults. They are the floor: any piece
-- the catalogue knows about has SOME price, even on a fresh database. The
-- trade-off is that the file has to be edited and the resource reloaded for
-- any pricing change.
--
-- This table is for everything that comes AFTER the floor. Staff sets a row
-- for a specific (kind, slot_id, collection, drawable, texture) tuple and
-- that price is used the next time a player opens the wardrobe or the
-- store. Fabvariations get their own rows: drawing 4 in fabric 2 can be a
-- different price from drawing 4 in fabric 0.
--
-- The combination is the natural key, which mirrors Owned's ownership shape:
-- one row per (variant, fabric) and you cannot accidentally book the same
-- variant at two prices.
--
-- `updated_at` is the last touch; useful for "what did pricing change this
-- week" reports. No gameplay code reads it.
-- ============================================================================

CREATE TABLE IF NOT EXISTS clothing_prices (
  kind        ENUM('component','prop') NOT NULL,
  slot_id     TINYINT UNSIGNED NOT NULL,
  collection  VARCHAR(64)     NOT NULL,
  drawable    INT UNSIGNED    NOT NULL,
  texture     INT UNSIGNED    NOT NULL,
  price       INT UNSIGNED    NOT NULL,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (kind, slot_id, collection, drawable, texture),
  KEY ix_clothing_prices_collection (kind, slot_id, collection)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed: copy of the curated Lua defaults so a fresh DB already has SOMETHING.
-- The resolver reads DB first, falls back to the Lua file only when there is
-- no row - which means the seed is what the resolver hits in 99% of cases
-- after this migration runs. Editing the file after the migration changes
-- only pieces the staff has not yet customised.
INSERT IGNORE INTO clothing_prices (kind, slot_id, collection, drawable, texture, price)
VALUES
  -- Tops (slot 11) - the most-traded slot. The default collection is the
  -- freemode base ('') because the store fronts use the same coords as GTA
  -- Online and the bulk of what the player will see on first visit.
  ('component', 11, '', 0,  0, 500),
  ('component', 11, '', 0,  1, 500),
  ('component', 11, '', 3,  0, 600),
  ('component', 11, '', 7,  0, 1200),
  ('component', 11, '', 11, 0, 1500),
  ('component', 11, '', 15, 0, 800),
  ('component', 11, '', 24, 0, 1100),
  -- Torsos (slot 3).
  ('component', 3, '', 0,  0, 350),
  ('component', 3, '', 1,  0, 350),
  ('component', 3, '', 2,  0, 450),
  ('component', 3, '', 5,  0, 500),
  -- Legs (slot 4).
  ('component', 4, '', 0,  0, 500),
  ('component', 4, '', 1,  0, 550),
  ('component', 4, '', 2,  0, 700),
  ('component', 4, '', 4,  0, 950),
  -- Shoes (slot 6).
  ('component', 6, '', 0,  0, 400),
  ('component', 6, '', 1,  0, 450),
  ('component', 6, '', 3,  0, 600),
  ('component', 6, '', 5,  0, 700),
  -- Accessories (slot 8).
  ('component', 8, '', 0,  0, 800),
  ('component', 8, '', 1,  0, 350),
  ('component', 8, '', 2,  0, 450),
  -- Hats (prop 0).
  ('prop', 0, '', 0,  0, 200),
  ('prop', 0, '', 2,  0, 400),
  ('prop', 0, '', 5,  0, 350),
  ('prop', 0, '', 7,  0, 600),
  ('prop', 0, '', 14, 0, 250),
  -- Glasses (prop 1).
  ('prop', 1, '', 0, 0, 300),
  ('prop', 1, '', 1, 0, 350),
  -- Ears (prop 2), Watch (prop 6), Bracelet (prop 7).
  ('prop', 2, '', 0, 0, 150),
  ('prop', 6, '', 0, 0, 400),
  ('prop', 7, '', 0, 0, 500);
