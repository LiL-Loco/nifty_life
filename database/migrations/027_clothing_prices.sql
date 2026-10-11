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
-- `name` carries the localized label so staff can read what they are
-- pricing. The Lua fallback files do not have a "no row exists" mode -
-- every drawable is in the table; only the `price` column is empty until
-- staff sets it.
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
  name        VARCHAR(128)    NOT NULL,
  price       INT UNSIGNED    NULL,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (kind, slot_id, collection, drawable, texture),
  KEY ix_clothing_prices_collection (kind, slot_id, collection)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed: just two pricing rows so a brand new DB has something that proves
-- the chain end-to-end. The full catalogue is filled by the boot-time scan
-- in nifty-core/server/clothing.lua's Price.scanCatalogue(), which reads
-- the JSON data files from nifty-creator and inserts one row per
-- (slot_id, drawable, texture) with the localized name and a NULL price.
-- Staff then sets the price column on the rows they want to sell.
INSERT IGNORE INTO clothing_prices (kind, slot_id, collection, drawable, texture, name, price)
VALUES
  ('component', 11, '', 0, 0, 'Crew T-Shirt', 500),
  ('prop',       0, '', 0, 0, 'White Cap',   200);
