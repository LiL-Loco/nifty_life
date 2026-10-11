-- 016_confirm_portal_email.sql
--
-- The confirmation link has to actually confirm.
--
-- THE PROBLEM. `confirmEmail()` consumed the token and then could not write
-- `portal_users.email_verified_at`, because migration 015 deliberately does NOT
-- grant the website account UPDATE on that column. The reasoning was sound — a
-- sign-up form must not be able to mark itself as having proved an address — but
-- the effect was a confirmation link that proves nothing, and an account column
-- that can only ever be NULL. That is not a safe default, it is a broken
-- feature wearing one.
--
-- THE FIX. A stored procedure with DEFINER rights, owned by the database, not by
-- the website. The web account gets EXECUTE and nothing else: it can ask
-- "confirm this token" and cannot ask "set email_verified_at to NOW()". The
-- column stays ungrantable, the proof stays inside the procedure, and the
-- check-then-write is atomic because it is one transaction.
--
-- This is the same shape `database/grants.sql` already recommends for the
-- Peeper author gap — "a stored procedure that takes the ID and looks the
-- author up itself, so the constraint lives in the database rather than in
-- reviewable application code". It is the first place that advice was actually
-- taken.
--
-- RETURNS the user id on success and NULL on every failure mode. The caller
-- cannot distinguish "unknown token" from "expired" from "already used", which is
-- deliberate: each of those is a statement about a token that leaked.

DROP PROCEDURE IF EXISTS confirm_portal_email;

DELIMITER //

CREATE PROCEDURE confirm_portal_email(IN p_token_hash CHAR(64))
BEGIN
  DECLARE v_user_id CHAR(36) DEFAULT NULL;

  -- 1. Claim the token. `used_at IS NULL` plus `expires_at > NOW()` makes this a
  --    single-use, time-limited claim, and the UPDATE-then-read order means two
  --    simultaneous clicks cannot both succeed: the loser's WHERE matches zero
  --    rows.
  UPDATE portal_email_tokens
     SET used_at = NOW()
   WHERE token_hash = p_token_hash
     AND purpose = 'verify_email'
     AND used_at IS NULL
     AND expires_at > NOW();

  SELECT user_id INTO v_user_id
    FROM portal_email_tokens
   WHERE token_hash = p_token_hash
     AND used_at IS NOT NULL
     AND expires_at > NOW()
   LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    -- 2. Confirm. Writing the same value twice is harmless: a second valid token
    --    for an already-confirmed address changes nothing.
    UPDATE portal_users
       SET email_verified_at = NOW()
     WHERE id = v_user_id
       AND email_verified_at IS NULL;
  END IF;

  SELECT v_user_id AS confirmed_user_id;
END//

DELIMITER ;

-- EXECUTE only. No SELECT on portal_users' UPDATE, no INSERT, nothing that lets
-- the web account write the column directly.
GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email TO 'nifty_website'@'localhost';

-- Procedure bodies run as their DEFINER, so the web account gets exactly the
-- two UPDATEs above and nothing else — no UPDATE privilege on either table is
-- created by this grant.
FLUSH PRIVILEGES;