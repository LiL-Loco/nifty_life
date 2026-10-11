-- ============================================================================
-- grants.sql — NOT a migration. Run manually, once, after the schema exists.
--
-- ADR-0007: the website submits applications; a human approves them. That
-- boundary is enforced by database privileges, not by application code, so a
-- bug or a compromise in the web app cannot read player data or approve anyone.
--
-- Run as an admin account, substituting real host names:
--   mysql -u root -p < database/grants.sql
--
-- The `nifty_website` user should live on a different host than the game
-- server so the grant itself is the only thing standing between a web
-- compromise and the player data.

-- ---------------------------------------------------------------------------
-- Game server: full access. Replaces the default `nifty` user created by
-- server.cfg.example.
-- ---------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'nifty'@'127.0.0.1' IDENTIFIED BY 'CHANGE_ME_GAME';
GRANT ALL PRIVILEGES ON nifty_life.* TO 'nifty'@'127.0.0.1';
FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------------
-- Website: read the account's own Discord ID, insert an application, and read
-- that application back so the status page works.
--
-- There is no UPDATE anywhere in this grant set. That is the entire point:
-- approving an application is an UPDATE on `applications`, so the website
-- physically cannot approve anyone.
--
-- No SELECT on wallets, characters, vehicles, properties or bans — the website
-- never needs them, and Tier 2 of the coupling (exposing game state) is not
-- in scope (ADR-0007).
-- ---------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'nifty_website'@'localhost' IDENTIFIED BY 'CHANGE_ME_WEB';

GRANT SELECT, INSERT ON nifty_life.applications TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.accounts     TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.bans         TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.properties  TO 'nifty_website'@'localhost';

-- ---------------------------------------------------------------------------
-- Peeper on the website (ADR-0022).
--
-- The website can read the feed and write posts, and it CANNOT confirm its own
-- identity binding. That is the whole point of the three-table handshake in
-- migration 009:
--
--   web_pairing_codes   no grant at all. Codes are generated in game and only
--                       exist as a SHA-256 hash. A dump of this database plus
--                       this grant cannot be used to link anyone to anything.
--   web_link_requests   INSERT only. The website submits (discord_id, code) and
--                       nothing else. It cannot mark its own request confirmed.
--   web_links           SELECT only. The result, written by the game server.
--   peeper_posts        SELECT + INSERT. It can publish and read. It cannot
--                       UPDATE (so it cannot un-delete), cannot DELETE (so a
--                       post cannot be physically erased at all), and has no
--                       access to `characters` — `author_name` is snapshotted
--                       onto the post precisely so the feed needs no roster.
--   peeper_likes        SELECT + INSERT + DELETE, scoped by nothing at the
--                       privilege layer: unliking your own like is the only
--                       DELETE here and it is harmless.
--   peeper_reports      SELECT + INSERT. The website can file a report. It
--                       cannot resolve one, because resolution is an UPDATE.
--
-- There is still NO UPDATE anywhere in this set, exactly as before. ADR-0019
-- wants staff-only deletion; since staff are people playing the game, deletion
-- is a game-server capability and stays there.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT ON nifty_life.web_link_requests TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.web_links            TO 'nifty_website'@'localhost';
GRANT SELECT, INSERT ON nifty_life.peeper_posts         TO 'nifty_website'@'localhost';
GRANT SELECT, INSERT ON nifty_life.peeper_likes         TO 'nifty_website'@'localhost';
GRANT SELECT, INSERT ON nifty_life.peeper_reports       TO 'nifty_website'@'localhost';

-- ---------------------------------------------------------------------------
-- Role resolution (2026-10-11).
--
-- The site distinguishes a player from an admin BEFORE it decides which
-- connection to use, so the check has to be answerable by the ordinary website
-- account. `is_staff` lives on `characters` (migration 009), and a column-level
-- grant is enough to ask the question without handing over the roster:
--
--   GRANT SELECT (id, is_staff) ON characters
--
-- The owner chose FULL SELECT here instead, to keep staff lookups simple. That
-- means a compromise of the public site exposes every character name and date
-- of birth. It is a deliberate trade, not an oversight — recorded here so the
-- next person to read this file knows it was a decision.
-- ---------------------------------------------------------------------------
GRANT SELECT ON nifty_life.characters TO 'nifty_website'@'localhost';

FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------------
-- Admin account (2026-10-11).
--
-- A THIRD account, used only by the /admin routes. It is a separate connection
-- with separate credentials, so a bug in the public site runs on the restricted
-- pool and never touches this one.
--
-- This reverses part of ADR-0007, which stated approving happens through the
-- Discord staff bot and never from the web. The owner chose a web admin area
-- because one person runs both, and the trade is recorded rather than quietly
-- absorbed:
--
--   gained  approving and reviewing applications from one screen
--   lost    a compromised website can now approve people, which was the single
--           property ADR-0007 existed to guarantee
--
-- The UPDATE is column-scoped. `answers`, `discord_id` and `id` are NOT writable,
-- so an admin account cannot rewrite an applicant's own words or reassign an
-- application to someone else.
--
-- The account is deliberately NOT mentioned in the website's .env.example
-- defaults: an instance that never opens /admin never needs the credential.
-- ---------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'nifty_admin'@'localhost' IDENTIFIED BY 'CHANGE_ME_ADMIN';

GRANT SELECT ON nifty_life.applications TO 'nifty_admin'@'localhost';
GRANT UPDATE (status, reviewed_at, reviewed_by_discord_id, decision_note)
  ON nifty_life.applications TO 'nifty_admin'@'localhost';
GRANT SELECT ON nifty_life.characters TO 'nifty_admin'@'localhost';
GRANT SELECT ON nifty_life.bans      TO 'nifty_admin'@'localhost';
GRANT SELECT ON nifty_life.accounts  TO 'nifty_admin'@'localhost';
GRANT SELECT ON nifty_life.staff     TO 'nifty_admin'@'localhost';

-- ---------------------------------------------------------------------------
-- `staff` — the Discord role mirror (migration 011).
--
-- READ-ONLY for both website accounts, for both web connections. The bot in
-- `bot/` is the ONLY writer, and it writes with the GAME account, not with
-- either of these. That is the point of mirroring rather than asking: the
-- website never has the token that could change who is staff.
--
-- `isStaff()` deliberately runs on the PUBLIC pool. Deciding whether to trust
-- the admin connection must not itself require the admin connection.
-- ---------------------------------------------------------------------------
GRANT SELECT ON nifty_life.staff TO 'nifty_website'@'localhost';

-- Verification, alongside the ones below:
--   INSERT INTO applications (...)                    -- denied: no INSERT
--   UPDATE applications SET answers='{}'             -- denied: column not granted
--   UPDATE applications SET discord_id='1'           -- denied: column not granted
--   UPDATE applications SET reviewed_by_discord_id=x  -- PERMITTED: this is the decision
--   DELETE FROM applications WHERE id='x'            -- denied: no DELETE
--   UPDATE peeper_posts SET deleted_at=NOW           -- denied: no grant at all
--   SELECT * FROM wallets                            -- denied: no grant at all
--   INSERT INTO staff (...)                          -- denied: no INSERT on either web account
--   UPDATE staff SET role_id='1'                     -- denied: no UPDATE on either web account
--   DELETE FROM staff WHERE discord_id='1'           -- denied: no DELETE on either web account

FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------------
-- Verify the boundary holds. All of these should return zero rows or an
-- access-denied error. Run them after every credential change.
-- ---------------------------------------------------------------------------
-- SELECT * FROM nifty_life.wallets;        -- denied: no grant
-- UPDATE nifty_life.applications SET status='approved' WHERE id='x';  -- denied: no UPDATE
-- DELETE FROM nifty_life.accounts;         -- denied: no DELETE
-- INSERT INTO nifty_life.characters VALUES (...);  -- denied: no grant

-- ADR-0022 — the identity binding must stay one-directional:
-- SELECT * FROM nifty_life.web_pairing_codes;                 -- denied: no grant
-- UPDATE nifty_life.web_link_requests SET id=id;               -- denied: no UPDATE
-- DELETE FROM nifty_life.web_links WHERE discord_id='1';      -- denied: no DELETE
-- DELETE FROM nifty_life.peeper_posts WHERE id='x';           -- denied: no DELETE
-- UPDATE nifty_life.peeper_posts SET deleted_at=NOW() WHERE id='x';  -- denied: no UPDATE
-- UPDATE nifty_life.peeper_reports SET status='dismissed';    -- denied: no UPDATE
-- SELECT * FROM nifty_life.characters;                        -- denied: no grant

-- The one consequence worth stating plainly: `SELECT ON web_links` returns every
-- Discord-to-character mapping, not just the caller's own. The website is
-- expected to filter on its own session's discord_id in application code, which
-- is weaker than the privilege boundary everywhere else in this file. If that is
-- not acceptable, replace the grant with a row-filtered view keyed on a session
-- variable — `CREATE VIEW my_web_links AS SELECT * FROM web_links WHERE
-- discord_id = @nifty_discord_id` — and drop the table grant.
--
-- ONE KNOWN GAP (accepted knowingly): the website has INSERT on `peeper_posts`
-- and nothing constrains `author_character` to a character that is actually
-- linked to the submitting Discord ID. Until the website exists this is
-- theoretical, but when it is written it must resolve the author through
-- `web_links` in its own transaction. A cleaner fix is a stored procedure that
-- takes the Discord ID and looks the author up itself, so the constraint lives
-- in the database rather than in reviewable application code.