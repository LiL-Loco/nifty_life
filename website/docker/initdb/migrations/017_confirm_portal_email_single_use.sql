-- 017_confirm_portal_email_single_use.sql
--
-- Migration 016's procedure did not actually enforce single use.
--
-- THE BUG. It claimed the token with an UPDATE guarded by `used_at IS NULL`, then
-- read the user id back with a SELECT guarded only by `used_at IS NOT NULL`. The
-- second click therefore updated zero rows — the guard worked — and then found
-- the row anyway, because the first click had set used_at. It returned the user
-- id and reported success, for a link that had already been used.
--
-- It was caught by tools/portal-probe.js, not by review: the check
-- "the same token cannot be used twice" failed while everything around it
-- passed. A guard that is written but not connected to the value it guards
-- looks exactly like a guard when you read the file.
--
-- THE FIX. Capture ROW_COUNT() from the claiming UPDATE and refuse when it is
-- zero. The claim is the authorisation; reading the row is only finding out what
-- was claimed. Order matters and is now the only way it can be written:
--
--     claim -> did I claim anything? no -> NULL
--                        yes -> set verified, return the id
--
-- DROP and CREATE rather than a new name: a stale `confirm_portal_email` left
-- behind under a different name is a procedure nobody remembers checking.

DROP PROCEDURE IF EXISTS confirm_portal_email;

DELIMITER //

CREATE PROCEDURE confirm_portal_email(IN p_token_hash CHAR(64))
BEGIN
  DECLARE v_user_id CHAR(36) DEFAULT NULL;
  DECLARE v_claimed INT DEFAULT 0;

  -- 1. Claim the token. `used_at IS NULL` and `expires_at > NOW()` make this a
  --    single-use, time-limited claim.
  UPDATE portal_email_tokens
     SET used_at = NOW()
   WHERE token_hash = p_token_hash
     AND purpose = 'verify_email'
     AND used_at IS NULL
     AND expires_at > NOW();

  -- 2. The claim is the authorisation. Zero rows means somebody already used it,
  --    or it expired, or it never existed — and all three return NULL, on
  --    purpose, because each is a different statement about a value that leaked
  --    by being emailed.
  SET v_claimed = ROW_COUNT();

  IF v_claimed = 0 THEN
    SELECT NULL AS confirmed_user_id;
  ELSE
    SELECT user_id INTO v_user_id
      FROM portal_email_tokens
     WHERE token_hash = p_token_hash
     LIMIT 1;

    -- Writing the same value twice is harmless, so a SECOND confirmation link
    -- for an already-confirmed address still succeeds. That is intentional: a
    -- person who clicked a stale link should not be locked out by having
    -- already succeeded elsewhere.
    UPDATE portal_users
       SET email_verified_at = NOW()
     WHERE id = v_user_id
       AND email_verified_at IS NULL;

    SELECT v_user_id AS confirmed_user_id;
  END IF;
END//

DELIMITER ;

-- CORRECTION: the grant from migration 016 does NOT survive this DROP/CREATE.
-- MariaDB drops routine-level privileges along with the routine, so the
-- procedure ends up present and unexecutable. Migration 018 re-grants it. That
-- grant is idempotent, so a fresh install running both in order is fine.