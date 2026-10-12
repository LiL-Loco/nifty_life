-- ============================================================================
-- 025_character_clothing.sql
-- Nifty Life 2.0 — per-character ownership of clothing pieces
--
-- WHY THIS TABLE
--
-- Before this migration, a character's clothing was one JSON blob on
-- `characters.appearance` with no per-piece identity. That made the creator
-- (pick an outfit once) and the hood toggle (swap one variant of a single top)
-- work, but it stopped matching the moment we wanted:
--
--   * a wardrobe UI that re-equips anything the character owns, for free
--   * clothing stores that hide pieces the character already owns
--   * creator picks to be persisted as a set of individual owned pieces,
--     not as one anonymous outfit
--
-- This table is the per-piece ownership list. `characters.appearance` keeps
-- its role: it stores the CURRENTLY-EQUIPPED loadout, exactly as it does
-- today, and the world's `applyAppearance` reads it unchanged.
--
-- SHAPE
--
-- One row per owned piece. The natural key is
-- (character_id, kind, slot_id, collection, drawable, texture): two
-- characters owning the same shirt each get their own row, and the same
-- character owning the same shirt twice is the same row (PRIMARY KEY dedupes).
--
-- `kind` distinguishes components from props at the schema layer because
-- their slot-id ranges overlap in places and the validation logic does not.
--
-- `source` is for audit only: 'creator' for the first-time outfit,
-- 'purchase' for buys from a clothing store, 'seed' for the migration.
-- No gameplay decision in V1 reads from it.
--
-- `ON DELETE CASCADE` mirrors `characters` (ADR-0001): a row that owns
-- rows must die with its owner.
--
-- Backfill of existing characters is handled in Lua at server boot
-- (nifty-core/server/clothing.lua), not in this file. SQL UNNEST over
-- JSON objects is awkward and version-fragile across MariaDB minors;
-- a Lua pass over `characters.appearance` reuses the same JSON library
-- the rest of the project already uses and writes through `Owned.grant`,
-- so the INSERT and the running code share one path.
-- ============================================================================

CREATE TABLE IF NOT EXISTS character_clothing (
  character_id  CHAR(36)        NOT NULL,
  kind          ENUM('component','prop') NOT NULL,
  slot_id       TINYINT UNSIGNED NOT NULL,
  collection    VARCHAR(64)     NOT NULL,
  drawable      INT UNSIGNED    NOT NULL,
  texture       INT UNSIGNED    NOT NULL,
  source        ENUM('creator','purchase','seed') NOT NULL DEFAULT 'seed',
  acquired_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (character_id, kind, slot_id, collection, drawable, texture),
  KEY ix_character_clothing_character (character_id),
  CONSTRAINT fk_character_clothing_character
    FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
