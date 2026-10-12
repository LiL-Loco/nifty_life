-- 012_staff_peeper_authorship.sql
--
-- The moderation team may write to P&R without ever having played the game.
--
-- WHY. Migration 009 made `peeper_posts.author_character` NOT NULL with a foreign
-- key to `characters`, which encoded a single rule: a post has an author, and the
-- author is a character. That rule is right for players and wrong for the team.
-- A moderator who has not created a character could not post, and the only ways
-- to give them one were both bad — hand them a real in-game character (which the
-- game server would then pay a Stütze to, and which appears in every character
-- list as a person who does not exist) or drop the foreign key and let posts
-- have no owner at all. Neither is worth it.
--
-- So authorship becomes explicitly two-sided: EITHER a character OR a Discord
-- account, never neither, never both. The CHECK constraint below is what makes
-- that a database fact rather than a convention, and it is why a staff post is
-- still attributable — which is the entire point of ADR-0022.
--
-- Nothing is dropped here. Every existing row keeps its `author_character` and
-- `author_discord_id` is NULL on all of them, so the constraint is satisfied by
-- construction.
--
-- DELETION. The team can now delete a post. It is a SOFT delete through the
-- `deleted_at` / `deleted_by` / `deleted_reason` columns that migration 009
-- already created for exactly this, and not a physical DELETE: this project does
-- not throw things away, and a removed post is evidence three months later when
-- somebody asks why a comment vanished. The row stays.
--
-- Migration 013 continues this for likes and reports.

-- ---------------------------------------------------------------------------
-- peeper_posts — authorship is character OR Discord account.
--
-- `source` gains 'staff' rather than reusing 'web'. The existing comment on that
-- column is right: a pattern of reports has to point at a surface, because the
-- game and the website have completely different moderation costs. A staff post
-- is a third surface again — nobody reports those, and the team needs to tell
-- its own announcements apart from a player's web post at a glance.
-- ---------------------------------------------------------------------------
ALTER TABLE peeper_posts
  MODIFY author_character CHAR(36) NULL,
  MODIFY source ENUM('game','web','staff') NOT NULL DEFAULT 'game',
  ADD COLUMN IF NOT EXISTS author_discord_id VARCHAR(32) NULL AFTER author_character,
  ADD COLUMN IF NOT EXISTS deleted_by_discord_id VARCHAR(32) NULL AFTER deleted_by,
  ADD KEY IF NOT EXISTS ix_peeper_author_discord (author_discord_id, created_at),
  ADD CONSTRAINT IF NOT EXISTS chk_peeper_author CHECK (
    (author_character IS NULL) <> (author_discord_id IS NULL)
  );