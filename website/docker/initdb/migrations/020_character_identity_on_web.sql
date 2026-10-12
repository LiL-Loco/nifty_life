-- 020_character_identity_on_web.sql
--
-- The character is created on the WEBSITE, not in the game. The player gives name,
-- gender, date of birth and birthplace there; the in-game creator is left with
-- appearance alone. This migration gives the database the two things that flow
-- requires and that 001 could not have: a birthplace, and a name that is actually
-- UNIQUE.
--
-- WHY THIS FILE EXISTS SEPARATELY. 001 is applied to existing databases too, and
-- a migration that is edited after the fact changes the meaning of a historical
-- schema. Everything here is additive.
--
-- ---------------------------------------------------------------------------
-- 1. birthplace
-- ---------------------------------------------------------------------------
--
-- Asked on the website alongside the rest of the identity. A free-text VARCHAR
-- rather than a lookup table: this is a weekend roleplay server for dozens of
-- characters, the answer is only ever displayed as text, and normalising real
-- place names into a table would buy nothing but a second source of truth.
--
-- NULL because it is nullable in the application too — a player may leave it out,
-- and inventing a default would put a lie in everyone's character sheet.
--
-- ---------------------------------------------------------------------------
-- 2. Name uniqueness — the important half
-- ---------------------------------------------------------------------------
--
-- The requirement is "the website tells the player when a name is taken". A check
-- in the website can do that for the person standing in front of the form. It
-- cannot do it for the person who submits two seconds later: between the SELECT
-- and the INSERT another player can take the same name, and the second INSERT
-- simply succeeds. `ix_characters_name` from 001 is a plain index — it makes
-- lookups fast and enforces nothing.
--
-- So uniqueness has to live in the database, and the website's check becomes an
-- optimization (better error message, no failed insert) rather than the guarantee.
--
-- The generated column exists for ONE reason: `last_name` is NULLABLE, and in
-- SQL NULL never equals NULL in a unique index. "Lena" with no surname would
-- therefore be insertable any number of times while "Lena Mustermann" was not.
-- Coalescing into a single non-null key closes that hole without forcing a
-- surname on players who do not want one.
--
-- TRIM is there because 'Max ' and 'Max' are the same name to a human and two
-- different rows to a plain index.
--
-- Collation does the case- and accent-insensitive part for free: the table is
-- utf8mb4_unicode_ci, where 'MAX' = 'max' and 'Müller' = 'Muller'. That is the
-- behaviour we want — one name, one character, however it was typed.
--
-- STORED, not VIRTUAL, because a UNIQUE index on a virtual column is rebuilt on
-- every read in some MySQL/MariaDB versions, and this key is written on every
-- character creation.

-- ---------------------------------------------------------------------------

ALTER TABLE characters
  ADD COLUMN birthplace VARCHAR(96) NULL AFTER gender;

-- Dropped and replaced by uq_characters_name below. Keeping both would cost a
-- second index over the same two columns for no query that the unique one does not
-- already serve.
ALTER TABLE characters
  DROP INDEX ix_characters_name;

ALTER TABLE characters
  ADD COLUMN name_key VARCHAR(161)
    GENERATED ALWAYS AS (
      CONCAT(TRIM(first_name), '|', TRIM(COALESCE(last_name, '')))
    ) STORED
    COMMENT 'Normalised name key. UNIQUE on this is what makes a name unclaimable.';

-- The generated column carries utf8mb4_unicode_ci from the table, so this index is
-- case- and accent-insensitive. A player cannot register "Max", then "MAX", then
-- "max" and pass three checks.
--
-- 161 = 64 + 1 + 64, plus slack. utf8mb4 counts characters, not bytes, so this is
-- the character budget and not an overflow risk.
ALTER TABLE characters
  ADD UNIQUE KEY uq_characters_name (name_key);

-- ---------------------------------------------------------------------------
-- 3. The "created on the web, not finished in game" state
-- ---------------------------------------------------------------------------
--
-- `appearance` was already nullable, and that is the whole signal: a character
-- whose appearance IS NULL was created on the website and has never been through
-- the creator. The server opens the creator on exactly this condition, and the
-- creator runs again on every login until it completes.
--
-- No new column and no new state machine. A status enum here would be a second
-- way to say "not finished", and two ways to say the same thing drift.
-- ---------------------------------------------------------------------------