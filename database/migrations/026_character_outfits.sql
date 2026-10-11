-- ============================================================================
-- 026_character_outfits.sql
-- Nifty Life 2.0 — saved outfits per character
--
-- WHY THIS TABLE
--
-- The wardrobe re-equips pieces, but a player also wants named presets
-- ("Alltag", "Dienst", "Schwarz") so they can switch whole looks with one
-- pick. Outfits are a NAMED list of (kind, slot_id, collection, drawable,
-- texture) tuples the character has already owned. They reference the owned
-- pieces; they do not duplicate them. An outfit whose pieces the character
-- does not own cannot be applied — apply re-validates before writing.
--
-- SHAPE
--
-- Two tables. `character_outfits` is the named root (one row per outfit).
-- `character_outfit_pieces` is the body (one row per slot filled in the
-- outfit), keyed by (outfit_id, kind, slot_id) so each slot has at most one
-- piece in an outfit. The natural key is the same one Owned.has uses, so
-- an outfit save can re-use the check by name.
--
-- `applied_at` is just the last time the player picked this outfit at the
-- wardrobe. Not used for any rule in V1; recorded because "what did I last
-- wear before the meeting" is a question the audit log might one day answer.
--
-- UNIQUE (character_id, name) prevents two outfits with the same name on one
-- character. Rename / overwrite handles the "the user already had 'Dienst'"
-- case, which is what they almost certainly want.
--
-- `ON DELETE CASCADE` mirrors characters: an outfit dies with its owner.
-- pieces cascades from outfits.
-- ============================================================================

CREATE TABLE IF NOT EXISTS character_outfits (
  id           CHAR(36)        NOT NULL,
  character_id CHAR(36)        NOT NULL,
  name         VARCHAR(64)     NOT NULL,
  created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  applied_at   DATETIME        NULL,
  PRIMARY KEY (id),
  KEY ix_character_outfits_character (character_id),
  UNIQUE KEY uq_character_outfits_character_name (character_id, name),
  CONSTRAINT fk_character_outfits_character
    FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS character_outfit_pieces (
  outfit_id    CHAR(36)        NOT NULL,
  kind         ENUM('component','prop') NOT NULL,
  slot_id      TINYINT UNSIGNED NOT NULL,
  collection   VARCHAR(64)     NOT NULL,
  drawable     INT UNSIGNED    NOT NULL,
  texture      INT UNSIGNED    NOT NULL,
  PRIMARY KEY (outfit_id, kind, slot_id),
  CONSTRAINT fk_character_outfit_pieces_outfit
    FOREIGN KEY (outfit_id) REFERENCES character_outfits (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
