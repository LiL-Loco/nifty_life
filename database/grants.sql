-- ============================================================================
CREATE USER IF NOT EXISTS 'nifty'@'%' IDENTIFIED BY 'CHANGE_ME_GAME';
GRANT ALL PRIVILEGES ON nifty_life.* TO 'nifty'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- ----------------------------------------------------------------------------
-- The website user MUST exist for both 'localhost' and '127.0.0.1' in addition
-- to '%'. Reason: MariaDB with `skip_name_resolve=0` rewrites a TCP connection
-- to 127.0.0.1 as coming from host 'localhost'. The '%' grant does NOT match
-- 'localhost', so without these mirror users the pool authenticates but inherits
-- no grants and every query fails with "SELECT command denied to user
-- 'nifty_website'@'localhost'". Same goes for Unix-socket connections that
-- arrive as 'localhost'. Defining the user with `IDENTIFIED BY PASSWORD` so the
-- hash stays in sync with '%' once the credential template is applied.
--
-- This block is duplicated below for the actual GRANTs - the helper at the
-- bottom of the file relies on a convention we keep stable across blocks.
CREATE USER IF NOT EXISTS 'nifty_website'@'localhost' IDENTIFIED BY 'CHANGE_ME_WEB';
CREATE USER IF NOT EXISTS 'nifty_website'@'127.0.0.1' IDENTIFIED BY 'CHANGE_ME_WEB';

CREATE USER IF NOT EXISTS 'nifty_website'@'%' IDENTIFIED BY 'CHANGE_ME_WEB';

GRANT SELECT, INSERT ON nifty_life.applications TO 'nifty_website'@'%';
GRANT SELECT         ON nifty_life.accounts     TO 'nifty_website'@'%';
GRANT SELECT         ON nifty_life.bans         TO 'nifty_website'@'%';
GRANT SELECT         ON nifty_life.properties  TO 'nifty_website'@'%';

GRANT SELECT, INSERT ON nifty_life.web_link_requests TO 'nifty_website'@'%';
GRANT SELECT         ON nifty_life.web_links            TO 'nifty_website'@'%';
GRANT SELECT         ON nifty_life.peeper_posts         TO 'nifty_website'@'%';
GRANT SELECT         ON nifty_life.peeper_likes         TO 'nifty_website'@'%';
GRANT SELECT, INSERT ON nifty_life.peeper_reports       TO 'nifty_website'@'%';

GRANT INSERT (id, author_character, author_name, parent_id, body, place_name, source)
  ON nifty_life.peeper_posts TO 'nifty_website'@'%';
GRANT INSERT (post_id, character_id)
  ON nifty_life.peeper_likes TO 'nifty_website'@'%';
GRANT INSERT (id, reporter, post_id, reason)
  ON nifty_life.peeper_reports TO 'nifty_website'@'%';

GRANT SELECT ON nifty_life.characters TO 'nifty_website'@'%';

FLUSH PRIVILEGES;

CREATE USER IF NOT EXISTS 'nifty_admin'@'%' IDENTIFIED BY 'CHANGE_ME_ADMIN';

GRANT SELECT ON nifty_life.applications TO 'nifty_admin'@'%';
GRANT UPDATE (status, reviewed_at, reviewed_by_discord_id, decision_note)
  ON nifty_life.applications TO 'nifty_admin'@'%';
GRANT SELECT ON nifty_life.characters TO 'nifty_admin'@'%';
GRANT SELECT ON nifty_life.bans      TO 'nifty_admin'@'%';
GRANT SELECT ON nifty_life.accounts  TO 'nifty_admin'@'%';
GRANT SELECT ON nifty_life.staff     TO 'nifty_admin'@'%';

GRANT SELECT ON nifty_life.staff TO 'nifty_website'@'%';

GRANT SELECT, INSERT ON nifty_life.peeper_posts TO 'nifty_admin'@'%';
GRANT UPDATE (deleted_at, deleted_by, deleted_by_discord_id, deleted_reason)
  ON nifty_life.peeper_posts TO 'nifty_admin'@'%';
GRANT SELECT, INSERT ON nifty_life.peeper_likes TO 'nifty_admin'@'%';
GRANT SELECT, INSERT ON nifty_life.peeper_reports TO 'nifty_admin'@'%';

GRANT SELECT ON nifty_life.portal_users        TO 'nifty_admin'@'%';
GRANT SELECT ON nifty_life.portal_user_discord TO 'nifty_admin'@'%';
GRANT SELECT ON nifty_life.portal_email_tokens TO 'nifty_admin'@'%';

GRANT SELECT ON nifty_life.portal_users TO 'nifty_website'@'%';

-- last_login_at is written on every successful sign-in; email_verified_at is
-- written when the user clicks the confirmation link. Both need UPDATE, both
-- are columns that the public pool has no business inventing for itself.
GRANT UPDATE (last_login_at, email_verified_at)
  ON nifty_life.portal_users TO 'nifty_website'@'%';

GRANT INSERT (id, email, username, password_hash, password_salt, last_login_at)
  ON nifty_life.portal_users TO 'nifty_website'@'%';

GRANT UPDATE (last_login_at) ON nifty_life.portal_users TO 'nifty_website'@'%';

GRANT SELECT, INSERT ON nifty_life.portal_email_tokens TO 'nifty_website'@'%';

GRANT SELECT, INSERT, UPDATE ON nifty_life.portal_user_discord TO 'nifty_website'@'%';


FLUSH PRIVILEGES;

GRANT EXECUTE ON PROCEDURE nifty_life.create_character_from_web
  TO 'nifty_website'@'%';

FLUSH PRIVILEGES;

-- ============================================================================
-- MIRROR GRANTS FOR localhost + 127.0.0.1
--
-- When MariaDB resolves a TCP connection to 127.0.0.1 as the host 'localhost'
-- (the default with skip_name_resolve=0), the '%' wildcard does NOT match and
-- the session authenticates with NO grants - queries fail with
-- "SELECT command denied to user 'nifty_website'@'localhost'".
--
-- Unix-socket connections always arrive as 'localhost' for the same reason.
--
-- The fix is to repeat every grant above for both 'localhost' and '127.0.0.1'
-- so the '%'-style connection-string in the application works regardless of
-- whether the resolver rewrites 127.0.0.1 -> localhost or not. When you add a
-- new grant for 'nifty_website' above, add it here too.
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT ON nifty_life.applications TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.accounts     TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.bans         TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.properties  TO 'nifty_website'@'localhost';

GRANT SELECT, INSERT ON nifty_life.web_link_requests TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.web_links            TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.peeper_posts         TO 'nifty_website'@'localhost';
GRANT SELECT         ON nifty_life.peeper_likes         TO 'nifty_website'@'localhost';
GRANT SELECT, INSERT ON nifty_life.peeper_reports       TO 'nifty_website'@'localhost';

GRANT INSERT (id, author_character, author_name, parent_id, body, place_name, source)
  ON nifty_life.peeper_posts TO 'nifty_website'@'localhost';
GRANT INSERT (post_id, character_id)
  ON nifty_life.peeper_likes TO 'nifty_website'@'localhost';
GRANT INSERT (id, reporter, post_id, reason)
  ON nifty_life.peeper_reports TO 'nifty_website'@'localhost';

GRANT SELECT ON nifty_life.characters TO 'nifty_website'@'localhost';
GRANT SELECT ON nifty_life.staff     TO 'nifty_website'@'localhost';

GRANT SELECT ON nifty_life.portal_users        TO 'nifty_website'@'localhost';
GRANT UPDATE (last_login_at) ON nifty_life.portal_users TO 'nifty_website'@'localhost';

GRANT SELECT, INSERT ON nifty_life.portal_email_tokens TO 'nifty_website'@'localhost';
GRANT SELECT, INSERT, UPDATE ON nifty_life.portal_user_discord TO 'nifty_website'@'localhost';

GRANT EXECUTE ON PROCEDURE nifty_life.create_character_from_web TO 'nifty_website'@'localhost';
GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email     TO 'nifty_website'@'localhost';

GRANT SELECT, INSERT ON nifty_life.applications TO 'nifty_website'@'127.0.0.1';
GRANT SELECT         ON nifty_life.accounts     TO 'nifty_website'@'127.0.0.1';
GRANT SELECT         ON nifty_life.bans         TO 'nifty_website'@'127.0.0.1';
GRANT SELECT         ON nifty_life.properties  TO 'nifty_website'@'127.0.0.1';

GRANT SELECT, INSERT ON nifty_life.web_link_requests TO 'nifty_website'@'127.0.0.1';
GRANT SELECT         ON nifty_life.web_links            TO 'nifty_website'@'127.0.0.1';
GRANT SELECT         ON nifty_life.peeper_posts         TO 'nifty_website'@'127.0.0.1';
GRANT SELECT         ON nifty_life.peeper_likes         TO 'nifty_website'@'127.0.0.1';
GRANT SELECT, INSERT ON nifty_life.peeper_reports       TO 'nifty_website'@'127.0.0.1';

GRANT INSERT (id, author_character, author_name, parent_id, body, place_name, source)
  ON nifty_life.peeper_posts TO 'nifty_website'@'127.0.0.1';
GRANT INSERT (post_id, character_id)
  ON nifty_life.peeper_likes TO 'nifty_website'@'127.0.0.1';
GRANT INSERT (id, reporter, post_id, reason)
  ON nifty_life.peeper_reports TO 'nifty_website'@'127.0.0.1';

GRANT SELECT ON nifty_life.characters TO 'nifty_website'@'127.0.0.1';
GRANT SELECT ON nifty_life.staff     TO 'nifty_website'@'127.0.0.1';

GRANT SELECT ON nifty_life.portal_users        TO 'nifty_website'@'127.0.0.1';
GRANT UPDATE (last_login_at) ON nifty_life.portal_users TO 'nifty_website'@'127.0.0.1';

GRANT SELECT, INSERT ON nifty_life.portal_email_tokens TO 'nifty_website'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE ON nifty_life.portal_user_discord TO 'nifty_website'@'127.0.0.1';

GRANT EXECUTE ON PROCEDURE nifty_life.create_character_from_web TO 'nifty_website'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email     TO 'nifty_website'@'127.0.0.1';

FLUSH PRIVILEGES;

