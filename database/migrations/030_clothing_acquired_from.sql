-- ============================================================================
-- 030_clothing_acquired_from.sql
-- Nifty Life 2.0 — provenance column on character_clothing
--
-- WHY
--
-- A character receives a clothing item from another character (trade, drop
-- etc.) and saves it into their own wardrobe. The owned piece is theirs
-- forever, but its name carries the giver so the wardrobe UI can label it
-- "T-Shirt #4 (von Max)" - a record of where the piece came from.
--
-- `acquired_from` is a free-form display string (the giver's character
-- name, e.g. "Max Mustermann"). It is not a foreign key: the giver's
-- character row may be deleted, renamed, or never linked to the items we
-- hold. The column reads on display and would just become "(von einem
-- Spieler)" or similar if cleaned up - a future migration can drop the
-- column, the wardrobe can detect NULL and hide the suffix.
--
-- Existing rows get NULL; the wardrobe renders "(von X)" only when the
-- column has a value.
-- ============================================================================

ALTER TABLE character_clothing
  ADD COLUMN acquired_from VARCHAR(128) NULL AFTER source;
