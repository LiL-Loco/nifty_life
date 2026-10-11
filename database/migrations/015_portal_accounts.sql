-- 015_portal_accounts.sql
--
-- The identity changes from "your Discord account" to "an account you made
-- here, with Discord attached".
--
-- WHY. Discord as the login was a consequence of the whitelist: the game server
-- gates on `accounts.discord_id`, so tying the website session to the Discord ID
-- made the linkage free. But it also means Discord is a hard dependency for
-- merely reading the site, and an applicant has no account at all until they
-- have already passed the thing they are applying for. Email and password is
-- the ordinary shape for a portal, and Discord moves to what it actually is
-- here: the key the GAME server knows you by, and the thing an application must
-- be tied to.
--
-- The invariant does not weaken. An application is still keyed on a Discord ID,
-- still one per person, and that ID now comes from a link the user proved by
-- logging into Discord. `portal_user_discord` is UNIQUE in both directions, so
-- one Discord account is one portal user, and one portal user has at most one
-- Discord account. There is still no path to a second application.

-- ---------------------------------------------------------------------------
-- portal_users — an account made on this site.
--
-- The password is scrypt with a per-user salt, from node:crypto, deliberately:
-- a dedicated dependency for it would be a package to keep patched for a
-- function the runtime already ships. Cost parameters live in the code rather
-- than here, because they are a property of the hash function's caller.
--
-- `email_verified_at` is NULL until the confirmation link is used. There is NO
-- code path that writes it other than `confirmEmail`.
--
-- The address is stored as given apart from case: emails are compared
-- case-insensitively, and MySQL's default collation already does that, so a
-- second registration differing only in case collides here rather than creating
-- a near-duplicate account.
--
-- `last_login_at` is written on every sign-in. It is the only thing that makes
-- "who registered and never came back" answerable, which is the first question
-- anybody asks about a signup list.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS portal_users (
  id                  CHAR(36)     NOT NULL,
  email               VARCHAR(254) NOT NULL,
  password_hash       CHAR(64)     NOT NULL,
  password_salt       CHAR(32)     NOT NULL,
  created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at       DATETIME     NULL,
  email_verified_at   DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_portal_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Email confirmation.
--
-- A separate table rather than two columns on portal_users, for one reason: the
-- hash must be DELETABLE and single-use. Keeping it beside the account invites a
-- row that is read, used and quietly left behind — where the next confirmation
-- would see a token as "already used" and refuse, or a resend would find two.
--
-- `token_hash` is a SHA-256 of the token, never the token itself. This mirrors
-- web_pairing_codes: the address that carries the link is read by whoever
-- receives the mail, so the database must not become the thing worth stealing.
--
-- `expires_at` is enforced by the confirm route, not by a cron. An unexpired
-- token that nobody used is harmless; an expired one is refused.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS portal_email_tokens (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     CHAR(36)     NOT NULL,
  purpose     ENUM('verify_email') NOT NULL DEFAULT 'verify_email',
  token_hash  CHAR(64)     NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at  DATETIME     NOT NULL,
  used_at     DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_portal_email_tokens_hash (token_hash),
  KEY ix_portal_email_tokens_user (user_id, purpose),
  CONSTRAINT fk_portal_email_tokens_user FOREIGN KEY (user_id)
    REFERENCES portal_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- portal_user_discord — the proven link.
--
-- UNIQUE on both columns, and that is the whole point. `discord_id` unique: a
-- Discord account belongs to exactly one portal user, so nobody can claim
-- someone else's Discord identity to apply under their name. `user_id` unique:
-- one account, one Discord. Without the second one a person could hold several
-- accounts and apply with each.
--
-- Written ONLY by the Discord OAuth callback, and only while a portal session
-- is signed in. That combination is what makes the link worth anything: you
-- cannot attach a Discord account without proving you are both the account
-- holder and the Discord account holder.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS portal_user_discord (
  user_id     CHAR(36)    NOT NULL,
  discord_id  VARCHAR(32) NOT NULL,
  username    VARCHAR(64) NOT NULL,
  linked_at   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_portal_user_discord_discord (discord_id),
  CONSTRAINT fk_portal_user_discord_user FOREIGN KEY (user_id)
    REFERENCES portal_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- applications.user_id
--
-- The application belongs to an account; the Discord ID it is keyed on is the
-- one that account linked. Both are kept because they answer different
-- questions: `user_id` is "whose application is this" for the portal, and
-- `discord_id` is "whose whitelist entry will be created" for the game server.
--
-- Nullable, because the one existing row predates portal accounts and has no
-- user behind it. The UNIQUE index is added the same way: a NULL user_id is
-- distinct from every other NULL in SQL, so that row does not collide with
-- anything and the index still bites for every real application.
--
-- One application per account, enforced the same way as one per Discord ID:
-- a UNIQUE index rather than application code, because two tabs or a retried
-- POST lose that race and the constraint does not.
-- ---------------------------------------------------------------------------
ALTER TABLE applications
  ADD COLUMN user_id CHAR(36) NULL AFTER id;

ALTER TABLE applications
  ADD UNIQUE KEY uq_applications_user (user_id);

-- Staff is read from `staff`, which is keyed by Discord ID. That still works
-- unchanged: isStaff() resolves the session's linked Discord ID first and asks
-- the mirror about it. No change to the bot, none to migration 011.