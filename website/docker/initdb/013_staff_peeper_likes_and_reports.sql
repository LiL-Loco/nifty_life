-- 013_staff_peeper_likes_and_reports.sql
--
-- Continues migration 012 for the two tables that also key on a character.
--
-- THE PROBLEM WITH A NULL KEY. `peeper_likes` was PRIMARY KEY (post_id,
-- character_id). Making character_id nullable breaks a primary key outright,
-- because NULL is not allowed in a key column. Switching to
-- UNIQUE(post_id, author_discord_id) does not help either: in SQL, NULL is
-- distinct from NULL, so the same moderator could like the same post fifty times
-- and every one of them would be a "unique" row.
--
-- THE FIX. A BEFORE INSERT trigger fills `actor` — one non-null string that is
-- the character id for a player and the Discord id for the team — and the unique
-- key lands on that. One rule, both identities, no NULL semantics anywhere.
--
-- A generated column would be tidier, and this file started that way:
--
--   actor VARCHAR(32) GENERATED ALWAYS AS (COALESCE(character_id, author_discord_id)) STORED
--   ERROR 1901 (HY000): Function or expression 'coalesce(...)' cannot be used
--   in the GENERATED ALWAYS AS clause of `actor`
--
-- MariaDB accepts only a restricted set of deterministic built-in functions
-- there, and COALESCE is not among them. The trigger is the portable answer and
-- has the advantage of holding the CHECK too, so a row that somehow arrived
-- with neither identity is rejected by the database rather than stored.

-- ---------------------------------------------------------------------------
-- peeper_likes — the PK becomes a surrogate, the uniqueness moves to `actor`.
-- ---------------------------------------------------------------------------
ALTER TABLE peeper_likes
  DROP PRIMARY KEY,
  ADD COLUMN id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST,
  MODIFY character_id CHAR(36) NULL,
  ADD COLUMN author_discord_id VARCHAR(32) NULL AFTER character_id,
  ADD COLUMN actor VARCHAR(32) NULL,
  ADD UNIQUE KEY uq_peeper_likes_actor (post_id, actor),
  ADD KEY ix_peeper_likes_discord (author_discord_id);
-- `ix_peeper_likes_character` already exists from migration 009 and stays: a
-- nullable column still uses that index for player likes.

DROP TRIGGER IF EXISTS trg_peeper_likes_actor;

DELIMITER //
CREATE TRIGGER trg_peeper_likes_actor BEFORE INSERT ON peeper_likes
FOR EACH ROW
BEGIN
  IF NEW.character_id IS NULL AND NEW.author_discord_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'a like needs either a character or a discord account';
  END IF;

  SET NEW.actor = COALESCE(NEW.character_id, NEW.author_discord_id);
END//
DELIMITER ;

-- ---------------------------------------------------------------------------
-- peeper_reports — a team member reporting a player's post is a normal thing
-- that should be possible. Reports have a surrogate PK already, so this is only
-- the authorship side.
--
-- No trigger needed: nothing here is keyed on the identity, so the CHECK alone
-- is enough to keep it honest.
-- ---------------------------------------------------------------------------
ALTER TABLE peeper_reports
  MODIFY reporter CHAR(36) NULL,
  ADD COLUMN reporter_discord_id VARCHAR(32) NULL AFTER reporter,
  ADD KEY ix_peeper_reports_reporter_discord (reporter_discord_id),
  ADD CONSTRAINT chk_peeper_reporter CHECK (
    (reporter IS NULL) <> (reporter_discord_id IS NULL)
  );