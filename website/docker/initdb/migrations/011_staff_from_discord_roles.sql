-- 011_staff_from_discord_roles.sql
--
-- Staff identity moves off the character and onto the Discord role.
--
-- WHY. Until now staff meant `characters.is_staff`, reached through `web_links`.
-- That makes "may approve an application" contingent on "has already played the
-- game", which is backwards: the moderation team is appointed by the people who
-- own the server, and the first of them to be appointed is by definition the one
-- who has been playing longest. It also meant the admin area could not be
-- exercised at all before the first client ever connected, so the approval path
-- would have shipped untested.
--
-- Discord roles are also where the team already lives. Nobody maintains a second
-- list in a database when the same answer is already written down in the Discord
-- server settings.
--
-- `staff` is a MIRROR, not a source of truth. Discord is the source of truth;
-- the bot in `bot/` is the only writer. The website only ever SELECTs it.
--
-- Roles, not users, are recorded. If the staff role is renamed or re-created the
-- role_id changes and the bot re-syncs; storing the role makes it visible in the
-- table that the mirror is a mirror of a role and not of a hand-maintained list.

-- ---------------------------------------------------------------------------
-- staff — who may use /admin, mirrored from the Discord staff role.
--
-- One row per Discord account currently holding a configured staff role. A
-- member who loses the role is DELETED, not flagged, so a stale row cannot keep
-- someone in the admin area after they were removed.
--
-- `synced_at` is written by the bot on every upsert. It is the only evidence
-- that the mirror is fresh: if a bot has been down for a week, this column says
-- so, which a boolean flag could not.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staff (
  discord_id VARCHAR(32) NOT NULL,
  role_id    VARCHAR(32) NOT NULL,
  synced_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (discord_id),
  KEY ix_staff_role (role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- applications.reviewed_by -> reviewed_by_discord_id
--
-- The column already fits a Discord ID: CHAR(36) is wider than the longest
-- Discord snowflake (20 digits). Only the NAME lies, and that is worth fixing
-- while nothing else is in flight: a column called `reviewed_by` invites a
-- caller to put a character UUID in it, and that mistake would be silent —
-- a valid-looking 36-character value in a CHAR(36) column, discoverable only by
-- reading back a decision nobody can attribute.
--
-- The data is empty for this rename to be lossy: no application has ever been
-- decided, because no client has ever connected.
-- ---------------------------------------------------------------------------
ALTER TABLE applications
  CHANGE COLUMN reviewed_by reviewed_by_discord_id VARCHAR(32) NULL;