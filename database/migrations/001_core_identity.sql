-- ============================================================================
-- 001_core_identity.sql
-- Nifty Life 2.0 — accounts, characters, sessions
--
-- Invariants encoded here (do not remove, they are decisions, not preferences):
--   ADR-0001  No player-owned row is keyed by FiveM slot ID.
--   ADR-0008  One character per account, enforced by UNIQUE, not by app logic.
-- ============================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
  version     VARCHAR(64)  NOT NULL,
  applied_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- accounts — the human being. Owns exactly one character.
-- The Discord ID is the whitelist key (ADR-0007). Teamspeak UID gates voice.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS accounts (
  id            CHAR(36)     NOT NULL,
  discord_id    VARCHAR(32)  NOT NULL,
  teamspeak_uid VARCHAR(64)  NULL,
  status        ENUM('pending','active','suspended') NOT NULL DEFAULT 'pending',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_accounts_discord_id (discord_id),
  KEY ix_accounts_teamspeak (teamspeak_uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- characters — the primary entity. Owns money, inventory, property, vehicles.
-- uq_characters_account is what enforces "one character per person" (ADR-0008).
--
-- `appearance` holds the character-creator output. STRUCTURE (ADR-0017) — store
-- collection name + LOCAL index per slot, never a global drawable index:
--
--   {
--     "model": "mp_m_freemode_01",
--     "components": {
--       "0": { "collection": "", "drawable": 27, "texture": 0 },
--       "4": { "collection": "female_heist", "drawable": 9, "texture": 3 }
--     },
--     "props": {
--       "0": { "collection": "mp_f_bikerdlc_01", "drawable": 0, "texture": 0 }
--     }
--   }
--
-- Component ids run 0..12; prop anchor points run 0..12.
--
-- Global drawable indexes are deliberately NOT used: they shift on every Title
-- Update, which would silently restyle every existing character. Collection
-- names and local indexes stay stable across TUs, which is exactly what a
-- server that must keep working after the next game update needs.
--
-- Validation is the server's job. The collection natives are CLIENT-ONLY, so a
-- client can submit any JSON it likes — the server must check collection names
-- against an allowlist and index ranges per collection before storing.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS characters (
  id            CHAR(36)    NOT NULL,
  account_id    CHAR(36)    NOT NULL,
  first_name    VARCHAR(64) NOT NULL,
  last_name     VARCHAR(64) NULL,
  date_of_birth DATE        NULL,
  gender        ENUM('male','female','nonbinary') NULL,
  appearance    JSON        NULL,
  spawn_point   VARCHAR(64) NOT NULL DEFAULT 'default',
  created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_characters_account (account_id),
  KEY ix_characters_name (first_name, last_name),
  CONSTRAINT fk_characters_account FOREIGN KEY (account_id)
    REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- sessions — EPHEMERAL. This is the ONLY place a FiveM slot ID may appear.
--
-- ADR-0001: slot IDs are recycled by FiveM on Enhanced, so any row keyed by
-- them silently reassigns to a different player. Never promote fivem_slot_id
-- into a key, never copy it into another table, never persist anything that
-- outlives the session by reference to it.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessions (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  character_id     CHAR(36)        NOT NULL,
  fivem_slot_id    SMALLINT UNSIGNED NULL,
  fivem_license    VARCHAR(64)     NULL,
  connected_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disconnected_at  DATETIME        NULL,
  PRIMARY KEY (id),
  KEY ix_sessions_character (character_id),
  KEY ix_sessions_open (disconnected_at),
  CONSTRAINT fk_sessions_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;