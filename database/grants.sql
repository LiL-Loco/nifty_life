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

FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------------
-- Verify the boundary holds. All four of these should return zero rows or an
-- access-denied error. Run them after every credential change.
-- ---------------------------------------------------------------------------
-- SELECT * FROM nifty_life.wallets;        -- denied: no grant
-- UPDATE nifty_life.applications SET status='approved' WHERE id='x';  -- denied: no UPDATE
-- DELETE FROM nifty_life.accounts;         -- denied: no DELETE
-- INSERT INTO nifty_life.characters VALUES (...);  -- denied: no grant