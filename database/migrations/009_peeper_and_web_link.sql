-- ============================================================================
-- 009_peeper_and_web_link.sql
-- Nifty Life 2.0 — Peeper (ADR-0019) and the web↔character binding (ADR-0022)
--
-- ADR-0022: Peeper is reachable from the website, but a post is authored by a
-- CHARACTER whichever surface it was written on. There is exactly one author
-- identity per person. The alternative — web posts under the Discord login —
-- would give every player two identities and a ban that only covers one of them.
--
-- ---------------------------------------------------------------------------
-- The binding handshake, and why it is three tables
-- ---------------------------------------------------------------------------
-- A character and a Discord login have to be proven to belong to the same
-- person. The code is generated IN GAME and typed on the website, so possession
-- of the website account is never enough by itself and possession of the
-- character is never enough by itself.
--
--   web_pairing_codes   GAME writes.  One outstanding code per character, stored
--                                  as a SHA-256 hash. Expiring, single-use.
--   web_link_requests   WEBSITE writes (INSERT). A typed code, nothing else.
--   web_links           GAME writes. The result: discord_id <-> character_id.
--
-- The split exists so the website never needs UPDATE anywhere. Confirmation is
-- the game server's job and nobody else's — the same trick that makes ADR-0007's
-- application approval impossible for the website. If the website could UPDATE
-- `web_link_requests` it would simply mark its own request confirmed and link
-- itself to any character, which is the whole attack this split prevents.
--
-- ---------------------------------------------------------------------------
-- Posts carry a snapshot of the author's display name
-- ---------------------------------------------------------------------------
-- `author_name` is denormalised on purpose. It means the website needs no
-- SELECT on `characters` at all, so granting it access to the social feed does
-- not also grant it the player roster. It is also the semantically right answer:
-- a post shows the name it was published under, like any real timeline.
--
-- ---------------------------------------------------------------------------
-- There is no path to physically delete a post
-- ---------------------------------------------------------------------------
-- `deleted_at` / `deleted_by` / `deleted_reason` are written by the game server
-- and the row stays. ADR-0019 makes deletion staff-only and permanent-removal is
-- exactly what the server does not offer: soft deletion is enforced here by the
-- absence of any DELETE grant, so "a character cannot delete their own post" is
-- a property of the database, not of application code that could be miswritten.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- web_pairing_codes — outstanding codes, game server only.
--
-- Hashed, so a database dump does not hand an attacker a way to link a Discord
-- account to someone else's character. One live code per character: issuing a
-- new one supersedes the old, because a code that stays valid after the player
-- asked for a replacement is a code the player believes is dead.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS web_pairing_codes (
  character_id CHAR(36)     NOT NULL,
  code_hash    CHAR(64)     NOT NULL,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at   DATETIME     NOT NULL,
  PRIMARY KEY (character_id),
  KEY ix_web_pairing_expiry (expires_at),
  CONSTRAINT fk_pairing_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- web_link_requests — what the website submits. INSERT-only for it.
--
-- `code` is stored in the clear because it is short-lived, single-use and is
-- already worthless without the matching hash in the row above. `attempts` is
-- there so a caller can tell "wrong code" from "rate limited" without the game
-- server having to keep per-IP state.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS web_link_requests (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  discord_id  VARCHAR(32)  NOT NULL,
  code        VARCHAR(16)  NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_web_link_requests_discord (discord_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- web_links — the proven binding. Game server writes; the website only reads
-- this row for its OWN discord id.
--
-- UNIQUE on both columns. `discord_id` unique: one website login, one character.
-- `character_id` unique: a character cannot be linked to two Discord accounts.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS web_links (
  discord_id  VARCHAR(32) NOT NULL,
  character_id CHAR(36)    NOT NULL,
  linked_at   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (discord_id),
  UNIQUE KEY uq_web_links_character (character_id),
  KEY ix_web_links_character (character_id),
  CONSTRAINT fk_web_links_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Staff flag.
--
-- ADR-0019 makes deletion staff-only, and ADR-0008 removed job qualification
-- ("jobs are open to anyone"), so there is no existing way to express "is
-- staff". This column is that way, and it is deliberately NOT derivable from a
-- job: the police department is not the moderation team, and an officer who
-- could delete posts on a server with one moderator would be a second
-- moderator nobody appointed.
--
-- `IF NOT EXISTS` so re-running the migration is harmless.
--
-- The website cannot set it: `nifty_website` has no UPDATE on `characters` at
-- all, and never will — see database/grants.sql.
-- ---------------------------------------------------------------------------
ALTER TABLE characters ADD COLUMN IF NOT EXISTS is_staff TINYINT(1) NOT NULL DEFAULT 0;

-- Placeholder tuning, deliberately minimal. The body limit is the one number
-- that matters for moderation volume: a smaller cap means fewer walls of text
-- for one person to read.
INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  ('peeper.post.max_length',    '280', 'int',     'social',   'Maximum characters in a Peeper post or reply.'),
  ('peeper.feed.page_size',     '25',  'int',     'social',   'Default page size for the feed.'),
  ('peeper.pairing.ttl_minutes','15',  'int',     'social',   'Lifetime of a web pairing code (ADR-0022).')
ON DUPLICATE KEY UPDATE `key` = `key`;

-- ---------------------------------------------------------------------------
-- peeper_posts — the broadcast feed.
--
-- `source` records which surface wrote it. It is not cosmetic: moderation on a
-- one-person team needs to know whether a pattern of reports points at the game
-- or at the website, because they have completely different moderation costs.
--
-- `parent_id` makes replies a column rather than a table, which is honest: a
-- reply is the same thing as a post with a target, and a separate table would
-- be a second moderation surface to forget.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS peeper_posts (
  id               CHAR(36)     NOT NULL,
  author_character CHAR(36)     NOT NULL,
  author_name      VARCHAR(129) NOT NULL,
  parent_id        CHAR(36)     NULL,
  body             TEXT         NOT NULL,
  place_name       VARCHAR(64)  NULL,
  source           ENUM('game','web') NOT NULL DEFAULT 'game',
  created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at       DATETIME     NULL,
  deleted_by       CHAR(36)     NULL,
  deleted_reason   VARCHAR(255) NULL,
  PRIMARY KEY (id),
  KEY ix_peeper_feed (deleted_at, created_at),
  KEY ix_peeper_author (author_character, created_at),
  KEY ix_peeper_parent (parent_id),
  CONSTRAINT fk_peeper_author FOREIGN KEY (author_character)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_peeper_parent FOREIGN KEY (parent_id)
    REFERENCES peeper_posts (id) ON DELETE CASCADE,
  CONSTRAINT fk_peeper_deleted_by FOREIGN KEY (deleted_by)
    REFERENCES characters (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- peeper_follows — asymmetric by construction (ADR-0019). One row per directed
-- edge; PRIMARY KEY on the pair is what makes "cannot follow yourself" and
-- "cannot follow twice" database facts rather than checks somebody can forget.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS peeper_follows (
  follower  CHAR(36) NOT NULL,
  followee  CHAR(36) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (follower, followee),
  KEY ix_peeper_follows_followee (followee),
  CONSTRAINT fk_follows_follower FOREIGN KEY (follower)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_follows_followee FOREIGN KEY (followee)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT chk_follows_not_self CHECK (follower <> followee)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- peeper_likes — and reports.
--
-- A report always points at a post, never at a person. That is deliberate:
-- "report this character" produces an unactionable ticket (see ADR-0019 — the
-- report has to be answerable by a staff search), whereas "report this post"
-- is a specific piece of content with an owner and a timestamp attached.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS peeper_likes (
  post_id     CHAR(36) NOT NULL,
  character_id CHAR(36) NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (post_id, character_id),
  KEY ix_peeper_likes_character (character_id),
  CONSTRAINT fk_likes_post FOREIGN KEY (post_id)
    REFERENCES peeper_posts (id) ON DELETE CASCADE,
  CONSTRAINT fk_likes_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS peeper_reports (
  id               CHAR(36)     NOT NULL,
  reporter         CHAR(36)     NOT NULL,
  post_id          CHAR(36)     NOT NULL,
  reason           ENUM('spam','harassment','impersonation','other') NOT NULL DEFAULT 'other',
  status           ENUM('open','actioned','dismissed') NOT NULL DEFAULT 'open',
  created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at      DATETIME     NULL,
  resolution_note  VARCHAR(255) NULL,
  PRIMARY KEY (id),
  KEY ix_peeper_reports_post (post_id),
  KEY ix_peeper_reports_queue (status, created_at),
  -- Constraint names are unique per DATABASE in InnoDB, not per table. These
  -- started as `fk_reports_reporter` / `fk_reports_post`, which `phone_reports`
  -- (migration 007) already owns — the collision surfaces as
  -- `errno: 121 Duplicate key on write or update` on a table that is
  -- otherwise perfectly valid, naming neither of the two constraints involved.
  CONSTRAINT fk_peeper_report_reporter FOREIGN KEY (reporter)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_peeper_report_post FOREIGN KEY (post_id)
    REFERENCES peeper_posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;