-- ============================================================================
-- verify-boundary.sql - proof, not a migration.
--
-- ADR-0007 and ADR-0022 make two claims about what the website can and cannot
-- do. This file is how they are checked rather than believed.
--
-- Every statement in DENY must fail. Every statement in ALLOW must succeed.
-- Run as an admin account, or as nifty_website itself to prove the denial:
--
--   mariadb -u root -p nifty_life < website/sql/verify-boundary.sql
--
-- `grants.sql` already lists these checks as comments. They are a script here
-- because a comment is never run, and a boundary nobody executes is a boundary
-- nobody has.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ALLOW - the website must be able to do all of this.
-- ---------------------------------------------------------------------------

SELECT 'ALLOW: read the feed' AS check_name;
SELECT id, author_name, created_at FROM peeper_posts WHERE deleted_at IS NULL LIMIT 1;

SELECT 'ALLOW: submit an application' AS check_name;
INSERT INTO applications (id, discord_id, answers)
VALUES (UUID(), '000000000000000001', '{"boundary":"probe"}');

SELECT 'ALLOW: read that application back' AS check_name;
SELECT id, discord_id, status FROM applications
 WHERE discord_id = '000000000000000001' ORDER BY submitted_at DESC LIMIT 1;

SELECT 'ALLOW: see whether this account is banned' AS check_name;
SELECT COUNT(*) AS bans FROM bans WHERE discord_id = '000000000000000001';

SELECT 'ALLOW: submit a pairing request' AS check_name;
INSERT INTO web_link_requests (discord_id, code)
VALUES ('000000000000000001', 'PROBE00');

SELECT 'ALLOW: read the link it resolves to' AS check_name;
SELECT * FROM web_links WHERE discord_id = '000000000000000001';

-- ---------------------------------------------------------------------------
-- DENY - each of these MUST fail with an access error.
--
-- These are run by website/tools/verify-boundary.ps1, which asserts that every
-- one is refused. If any succeeds, the privilege boundary is gone.
-- ---------------------------------------------------------------------------

-- DENY: approve an application. This is the claim ADR-0007 exists to make.
UPDATE applications SET status = 'approved'
 WHERE discord_id = '000000000000000001';

-- DENY: confirm its own pairing request, which would link it to any character.
UPDATE web_link_requests SET code = code WHERE discord_id = '000000000000000001';

-- DENY: write a link directly.
INSERT INTO web_links (discord_id, character_id) VALUES ('000000000000000001', UUID());

-- DENY: read the pairing codes. A dump plus this grant would link anyone.
SELECT * FROM web_pairing_codes;

-- DENY: read player data. The website needs none of it (ADR-0007 Tier 2).
SELECT * FROM wallets;
SELECT * FROM characters;
SELECT * FROM bans WHERE discord_id IS NOT NULL AND 1 = 0;

-- DENY: erase or un-delete a post. Deletion is a game-server capability.
DELETE FROM peeper_posts WHERE id = 'nonexistent';
UPDATE peeper_posts SET deleted_at = NOW() WHERE id = 'nonexistent';

-- DENY: resolve a report it filed. Resolution is an UPDATE.
UPDATE peeper_reports SET status = 'dismissed' WHERE id = 'nonexistent';

-- DENY: remove somebody else's like. Only your own may go.
DELETE FROM peeper_likes WHERE character_id <> 'nonexistent';