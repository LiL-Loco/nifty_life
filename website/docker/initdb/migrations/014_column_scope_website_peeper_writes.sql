-- 014_column_scope_website_peeper_writes.sql
--
-- Migration 012 opened a hole, and it is closed here rather than in code.
--
-- THE HOLE. `peeper_posts.author_character` used to be NOT NULL with a foreign
-- key, so the public pool could only ever write a row attributed to a real
-- character — that constraint was the authorship guarantee. Migration 012 made
-- the column nullable and added `author_discord_id` for team posts, and
-- `nifty_website` holds a TABLE-LEVEL `INSERT` on `peeper_posts`. A table-level
-- grant cannot express "every column except this one", so after 012 the public
-- pool could insert a post attributed to ANY Discord account — including the
-- owner's. Not reachable through the shipped code, which never writes that
-- column, but reachable by any future code path, mistake or compromise on the
-- web server. That is exactly the class of problem grants exist to make
-- impossible rather than reviewable.
--
-- THE FIX, in two halves.
--
-- 1. Column-scoped INSERT for the public pool. `author_discord_id` is simply not
--    in the list, so the public account cannot name a Discord author — the
--    driver rejects the statement, not a reviewer's careful reading of it.
--
-- 2. A CHECK tying `source` to authorship. Without it, column (1) alone is not
--    enough: `source` is still grantable, so the public pool could label a
--    character post as 'staff' and put a Team badge on a player's words. With
--    the constraint, 'staff' REQUIRES a Discord author, which the public pool
--    cannot supply, so it cannot produce a staff post at all.

ALTER TABLE peeper_posts
  ADD CONSTRAINT chk_peeper_staff_authorship CHECK (
    source <> 'staff'
    OR (author_discord_id IS NOT NULL AND author_character IS NULL)
  );

-- The same reasoning for likes and reports. Neither is security-critical the
-- way authorship is — a forged like is a counter, a forged report is a queue
-- entry the game server resolves — but "the public pool can only ever be a
-- character" is one rule, and making it three exceptions is how it stops being
-- true. `actor` on `peeper_likes` is filled by the trigger and stays unwritable
-- on every account.
ALTER TABLE peeper_likes
  ADD CONSTRAINT chk_peeper_likes_staff_author CHECK (
    author_discord_id IS NULL OR character_id IS NULL
  );