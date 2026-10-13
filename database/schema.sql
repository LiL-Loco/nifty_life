-- ============================================================================
-- schema.sql — Nifty Life 2.0 — komplettes DB-Schema in einer Datei
--
-- Diese Datei kombiniert alle 30 Migrations aus database/migrations/ in der
-- Reihenfolge, in der sie angewendet werden müssen. Sie ist die 'from-scratch'
-- Variante für eine frische MariaDB-Instanz.
--
-- Erstellt:
--   - Datenbank 'nifty_life' (utf8mb4 / utf8mb4_unicode_ci)
--   - schema_migrations Tabelle (für Migrations-Tracking)
--   - Alle 30 Migrationen zusammengeführt
--   - ~80 Tabellen, Views, Procedures, Functions, Triggers
--
-- Verwendung:
--   mysql -u root -p < database/schema.sql
--
-- Benutzer-Accounts (nifty, nifty_website, nifty_admin) werden NICHT hier
-- angelegt. Dafür database/grants.sql nach dem Schema-Lauf ausführen.
--
-- Stand: 2026-10-13 — Stand der Migrations: 030
-- ============================================================================

CREATE DATABASE IF NOT EXISTS nifty_life
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE nifty_life;

SET FOREIGN_KEY_CHECKS = 0;


-- --------------------------------------------------------------------------
-- 001_core_identity.sql
-- --------------------------------------------------------------------------
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
-- --------------------------------------------------------------------------
-- 002_economy_inventory.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 002_economy_inventory.sql
-- Nifty Life 2.0 — wallets, Stütze ledger, items, settings
--
-- Invariants encoded here:
--   ADR-0009  Every tunable number lives in `settings`, never in code.
--              Prices are placeholders until the economy pass (see ADR-0009).
--   Money is DECIMAL, never FLOAT or DOUBLE. Rounding a float balance is a bug.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- wallets — one row per character, created with the character.
-- CHECK constraints make negative money impossible at the engine level, so a
-- bug in the Lua layer cannot corrupt a balance even if it tries.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallets (
  character_id CHAR(36)     NOT NULL,
  cash         DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  bank         DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (character_id),
  CONSTRAINT fk_wallets_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT chk_wallet_cash_non_negative CHECK (cash >= 0),
  CONSTRAINT chk_wallet_bank_non_negative CHECK (bank >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- stuetze_payouts — audit trail for the unconditional Stütze (ADR-0009).
--
-- Payouts are unconditioned, so the ONLY protection against abuse is that the
-- amount stays below subsistence. This table is how we detect that assumption
-- being wrong, and how we reconcile money after an incident.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stuetze_payouts (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  character_id CHAR(36)        NOT NULL,
  session_id   BIGINT UNSIGNED NULL,
  amount       DECIMAL(14,2)   NOT NULL,
  paid_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_stuetze_character_time (character_id, paid_at),
  KEY ix_stuetze_session (session_id),
  CONSTRAINT fk_stuetze_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_stuetze_session FOREIGN KEY (session_id)
    REFERENCES sessions (id) ON DELETE SET NULL,
  CONSTRAINT chk_stuetze_amount_positive CHECK (amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- item_defs — the item catalogue. Reference data, not player state.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS item_defs (
  code         VARCHAR(64)    NOT NULL,
  name         VARCHAR(128)   NOT NULL,
  category     VARCHAR(64)    NOT NULL,
  weight       DECIMAL(10,3)  NOT NULL DEFAULT 0.000,
  stackable    TINYINT(1)     NOT NULL DEFAULT 1,
  max_stack    INT UNSIGNED   NOT NULL DEFAULT 1,
  is_weapon    TINYINT(1)     NOT NULL DEFAULT 0,
  metadata_schema JSON        NULL,
  PRIMARY KEY (code),
  KEY ix_item_defs_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- inventory_items — what a character is carrying.
-- (character_id, slot) is unique so two rows can never claim the same place;
-- duplicate-slot writes fail loudly instead of silently merging.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_items (
  id           CHAR(36)      NOT NULL,
  character_id CHAR(36)      NOT NULL,
  slot         SMALLINT UNSIGNED NOT NULL,
  item_code    VARCHAR(64)   NOT NULL,
  quantity     INT UNSIGNED  NOT NULL DEFAULT 1,
  metadata     JSON          NULL,
  created_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_inventory_slot (character_id, slot),
  KEY ix_inventory_item (item_code),
  CONSTRAINT fk_inventory_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_inventory_item_def FOREIGN KEY (item_code)
    REFERENCES item_defs (code) ON DELETE RESTRICT,
  CONSTRAINT chk_inventory_quantity CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- settings — every tunable number in the server lives here.
--
-- ADR-0009: prices are placeholders until the economy pass, so the first tuning
-- round will change most of them. Nothing below is a balance decision; they are
-- seeded values chosen only so the server boots.
--
-- `key` is quoted because KEY is a reserved word.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS settings (
  `key`       VARCHAR(128)   NOT NULL,
  value       VARCHAR(255)   NOT NULL,
  value_type  ENUM('int','decimal','bool','string') NOT NULL DEFAULT 'string',
  category    VARCHAR(64)    NOT NULL DEFAULT 'general',
  description VARCHAR(255)   NULL,
  updated_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`key`),
  KEY ix_settings_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  -- Stütze (ADR-0009). MUST stay below subsistence — at subsistence, idling
  -- becomes optimal and the whole jobs layer becomes decorative.
  ('economy.stuetze.amount',          '250.00', 'decimal', 'economy', 'Stütze payout. Must stay below subsistence cost.'),
  ('economy.stuetze.interval_sec',    '900',    'int',     'economy', 'Seconds between Stütze payouts (15 min).'),
  ('economy.starting.cash',           '500.00', 'decimal', 'economy', 'Starting cash for a new character.'),
  ('economy.starting.bank',           '0.00',   'decimal', 'economy', 'Starting bank balance for a new character.'),

  -- Sinks (ADR-0009): with no mandatory grinding, recurring costs do the
  -- balancing work. These scale with what a character owns.
  ('economy.sink.apartment_rent',     '750.00', 'decimal', 'economy', 'Monthly rent, entry tier.'),
  ('economy.sink.house_rent',         '2500.00','decimal', 'economy', 'Monthly rent, premium tier.'),
  ('economy.sink.vehicle_fuel_unit',  '2.50',   'decimal', 'economy', 'Cost per unit of fuel.'),
  ('economy.sink.vehicle_insurance',  '150.00', 'decimal', 'economy', 'Vehicle insurance period cost.'),

  -- Server operation (ADR-0010)
  ('server.window.opening',           'fri 19:00', 'string', 'server', 'Window opens.'),
  ('server.window.closing',           'sun 22:00', 'string', 'server', 'Window closes.') ON DUPLICATE KEY UPDATE `key` = `key`;
-- --------------------------------------------------------------------------
-- 003_property_vehicles_jobs.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 003_property_vehicles_jobs.sql
-- Nifty Life 2.0 — ownership primitive, vehicles, jobs, applications, bans
--
-- Invariants encoded here:
--   ADR-0013  Housing is data, configured from a catalogue — not code.
--   ADR-0007  `applications` is INSERT-only for the website DB user. The
--             website can submit and never approve.
--   ADR-0008  Jobs are open to anyone; no qualification, no application.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- properties — the ownership primitive.
--
-- Housing and businesses are both *places*: a static location with an interior,
-- an entrance, a district and a tier. One table, because they are the same
-- concept and later content should be a new row, not a new subsystem.
--
-- Vehicles are deliberately NOT in here: a vehicle is a mobile instance with a
-- mutable position, not a place. It gets its own table below. It shares the
-- same ownership semantics and the same rent/upkeep sink pattern.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS properties (
  id             CHAR(36)      NOT NULL,
  kind           ENUM('housing','business') NOT NULL,
  code           VARCHAR(64)   NOT NULL,
  name           VARCHAR(128)  NOT NULL,
  district       VARCHAR(64)   NOT NULL,
  tier           ENUM('outlier','entry','standard','premium','luxury') NOT NULL DEFAULT 'standard',
  interior_ipl   VARCHAR(128)  NULL,
  entrance_x     DOUBLE        NULL,
  entrance_y     DOUBLE        NULL,
  entrance_z     DOUBLE        NULL,
  exit_x         DOUBLE        NULL,
  exit_y         DOUBLE        NULL,
  exit_z         DOUBLE        NULL,
  storage_slots  SMALLINT UNSIGNED NOT NULL DEFAULT 10,
  rent_amount    DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  upkeep_amount  DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  is_active      TINYINT(1)    NOT NULL DEFAULT 1,
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_properties_code (code),
  KEY ix_properties_kind_district (kind, district),
  KEY ix_properties_tier (tier),
  CONSTRAINT chk_property_rent_non_negative CHECK (rent_amount >= 0),
  CONSTRAINT chk_property_upkeep_non_negative CHECK (upkeep_amount >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- property_owners — who owns what. Free to obtain (ADR-0013); the *tier*
-- governs rent and upkeep, which is where the sink lives (ADR-0009).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS property_owners (
  property_id  CHAR(36)     NOT NULL,
  character_id CHAR(36)     NOT NULL,
  acquired_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (property_id),
  KEY ix_property_owners_character (character_id),
  CONSTRAINT fk_po_property FOREIGN KEY (property_id)
    REFERENCES properties (id) ON DELETE CASCADE,
  CONSTRAINT fk_po_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- vehicles — persisted world state (ADR-0004: nothing is lost).
--
-- Vanilla GTA parked cars do NOT survive a restart. This table is the record:
-- model, position, fuel, damage and owner. Entities are recreated server-side on
-- boot and kept alive with SetEntityOrphanMode(entity, 2).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicles (
  id            CHAR(36)      NOT NULL,
  owner_id      CHAR(36)      NULL,
  model         VARCHAR(64)   NOT NULL,
  plate         VARCHAR(16)   NULL,
  x             DOUBLE        NOT NULL DEFAULT 0,
  y             DOUBLE        NOT NULL DEFAULT 0,
  z             DOUBLE        NOT NULL DEFAULT 0,
  heading       DOUBLE        NOT NULL DEFAULT 0,
  fuel          DECIMAL(6,2)  NOT NULL DEFAULT 100.00,
  engine_health DECIMAL(6,2)  NOT NULL DEFAULT 100.00,
  body_health   DECIMAL(6,2)  NOT NULL DEFAULT 100.00,
  is_stored     TINYINT(1)    NOT NULL DEFAULT 0,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_vehicles_plate (plate),
  KEY ix_vehicles_owner (owner_id),
  KEY ix_vehicles_position (x, y),
  CONSTRAINT fk_vehicles_owner FOREIGN KEY (owner_id)
    REFERENCES characters (id) ON DELETE SET NULL,
  CONSTRAINT chk_vehicle_fuel CHECK (fuel >= 0 AND fuel <= 100),
  CONSTRAINT chk_vehicle_health CHECK (engine_health >= 0 AND body_health >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- job_defs / character_jobs
-- No qualification column exists, on purpose (ADR-0008). Anyone may sign up,
-- which is what stops a department being permanently empty on a small server.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_defs (
  code         VARCHAR(64)  NOT NULL,
  name         VARCHAR(128) NOT NULL,
  kind         ENUM('department','civilian','criminal') NOT NULL DEFAULT 'civilian',
  is_emergency TINYINT(1)   NOT NULL DEFAULT 0,
  base_x       DOUBLE       NULL,
  base_y       DOUBLE       NULL,
  base_z       DOUBLE       NULL,
  PRIMARY KEY (code),
  KEY ix_job_defs_kind (kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS character_jobs (
  character_id CHAR(36)     NOT NULL,
  job_code     VARCHAR(64)  NOT NULL,
  is_duty      TINYINT(1)   NOT NULL DEFAULT 0,
  duty_since   DATETIME     NULL,
  PRIMARY KEY (character_id, job_code),
  KEY ix_character_jobs_job (job_code, is_duty),
  CONSTRAINT fk_cj_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_cj_job FOREIGN KEY (job_code)
    REFERENCES job_defs (code) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- applications — written by the website, approved by a human.
--
-- ADR-0007: the `website` DB user receives INSERT and SELECT on this table and
-- NOTHING else. It cannot approve, because approving is an UPDATE that the
-- website has no privilege to perform. The boundary is in the grant, not in
-- application code.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS applications (
  id            CHAR(36)      NOT NULL,
  discord_id    VARCHAR(32)   NOT NULL,
  status        ENUM('submitted','under_review','approved','rejected') NOT NULL DEFAULT 'submitted',
  answers       JSON          NOT NULL,
  submitted_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at   DATETIME      NULL,
  reviewed_by   CHAR(36)      NULL,
  decision_note TEXT          NULL,
  PRIMARY KEY (id),
  KEY ix_applications_queue (status, submitted_at),
  KEY ix_applications_discord (discord_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- bans — attach to the account, mirrored by Discord ID so a ban survives an
-- account that no longer exists.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bans (
  id          CHAR(36)     NOT NULL,
  account_id  CHAR(36)     NULL,
  discord_id  VARCHAR(32)  NOT NULL,
  reason      TEXT         NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at  DATETIME     NULL,
  revoked_at  DATETIME     NULL,
  revoked_by  CHAR(36)     NULL,
  PRIMARY KEY (id),
  KEY ix_bans_discord_active (discord_id, revoked_at, expires_at),
  KEY ix_bans_account (account_id),
  CONSTRAINT fk_bans_account FOREIGN KEY (account_id)
    REFERENCES accounts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Seed reference data. Job roster confirmed with the owner.
-- ---------------------------------------------------------------------------
INSERT INTO job_defs (code, name, kind, is_emergency) VALUES
  ('police',  'Los Santos Police Department', 'department', 1),
  ('ems',     'Pillbox Medical',               'department', 1),
  ('taxi',    'Taxi Driver',                  'civilian',   0),
  ('mechanic','Mechanic',                     'civilian',   0)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- NOTE: no migration runner exists yet. Migrations are applied by mounting this
-- directory into a fresh MariaDB, or manually, in filename order. `schema_migrations`
-- (created in 001) is the landing spot for a proper runner — once one exists, it
-- records versions itself and no migration should write to that table.
-- --------------------------------------------------------------------------
-- 004_economy_inventory_ops.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 004_economy_inventory_ops.sql
-- Nifty Life 2.0 — money ledger, inventory seed data
--
-- Invariants encoded here:
--   ADR-0009  Every money movement is recorded. The Stütze is unconditional,
--              so its record is the only way to detect the assumption that it
--              stays below subsistence being wrong.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ledger — append-only record of every money movement.
--
-- This is an audit trail, not a balance. `wallets` holds the authoritative
-- balance; this table explains how it got there. Never updated, never deleted —
-- if a balance is wrong, this is what says why.
--
-- `balance_after` is denormalised deliberately: reconciling a ledger against
-- current balances is the whole point, and it needs the running total at the
-- time of the write, not a reconstruction.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ledger (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  character_id   CHAR(36)        NOT NULL,
  account        ENUM('cash','bank')   NOT NULL,
  delta          DECIMAL(14,2)   NOT NULL,
  balance_after  DECIMAL(14,2)   NOT NULL,
  reason         VARCHAR(64)     NOT NULL,
  reference_type VARCHAR(32)     NULL,
  reference_id   CHAR(36)        NULL,
  created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_ledger_character (character_id, created_at),
  KEY ix_ledger_reference (reference_type, reference_id),
  -- RESTRICT, not CASCADE: deleting a character would delete the explanation of
  -- every euro they ever held. ADR-0004 is "nothing is lost" — that includes the
  -- history, so the deletion is refused rather than performed.
  CONSTRAINT fk_ledger_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE RESTRICT,
  CONSTRAINT chk_ledger_balance_non_negative CHECK (balance_after >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Append-only enforcement.
--
-- A comment saying "never updated" is a wish. These triggers make it the
-- database's opinion, which is the only kind that survives a tired maintainer
-- at 2am. Single-statement bodies, so no DELIMITER juggling is needed when the
-- entrypoint pipes this file into the client.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_ledger_no_update;
CREATE TRIGGER trg_ledger_no_update BEFORE UPDATE ON ledger FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ledger rows are immutable';

DROP TRIGGER IF EXISTS trg_ledger_no_delete;
CREATE TRIGGER trg_ledger_no_delete BEFORE DELETE ON ledger FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ledger rows are permanent';

-- ---------------------------------------------------------------------------
-- Seed inventory items.
--
-- `phone` is here because of ADR-0018: the handset is an ordinary inventory
-- item, and it is priced as a sink so that a broke character has a reason to
-- want money at all.
-- ---------------------------------------------------------------------------
INSERT INTO item_defs (code, name, category, weight, stackable, max_stack, is_weapon) VALUES
  ('phone',       'Handy',              'device',   0.250, 0, 1, 0),
  ('phone_sim',   'SIM-Karte',          'device',   0.050, 1, 1, 0),
  ('bread',       'Brot',               'food',     0.100, 1, 10, 0),
  ('water',       'Wasser',             'food',     0.500, 1, 10, 0),
  ('coffee',      'Kaffee',             'food',     0.200, 1, 10, 0),
  ('bandage',     'Verband',            'medical',  0.100, 1, 10, 0),
  ('painkillers', 'Schmerztabletten',   'medical',  0.100, 1, 10, 0),
  ('lockpick',    'Dietrich',           'tool',     0.050, 1, 5, 0),
  ('screwdriver', 'Schraubenzieher',    'tool',     0.300, 1, 1, 0),
  ('car_key',     'Autoschlüssel',      'tool',     0.050, 0, 1, 0),
  ('house_key',   'Hausschlüssel',      'tool',     0.050, 0, 1, 0),
  ('id_card',     'Personalausweis',    'document', 0.010, 0, 1, 0),
  ('drivers_licence', 'Führerschein',   'document', 0.010, 0, 1, 0)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- ---------------------------------------------------------------------------
-- Additional tunables. Placeholders (ADR-0009): structure fixed, numbers not.
-- ---------------------------------------------------------------------------
INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  -- ADR-0018: a handset must be bought and activated. This is the sink that
  -- gives a broke character a reason to want money.
  ('economy.price.phone',              '650.00', 'decimal', 'economy', 'Replacement handset (ADR-0018).'),
  ('economy.price.phone_sim',          '50.00',  'decimal', 'economy', 'SIM to activate a handset.'),

  -- Stütze accounting. `max_per_session` is the only brake on an unconditioned
  -- payout; it exists so a single long session cannot out-earn a working one.
  ('economy.stuetze.max_per_session',  '8',      'int',     'economy', 'Ceiling on Stütze payouts per session.'),

  -- Inventory capacity.
  ('inventory.default_slots',         '24',     'int',     'inventory', 'Starting inventory slots.'),
  ('inventory.max_weight',            '50.000', 'decimal', 'inventory', 'Carry weight limit.') ON DUPLICATE KEY UPDATE `key` = `key`;
-- --------------------------------------------------------------------------
-- 005_jobs_and_property_seed.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 005_jobs_and_property_seed.sql
-- Nifty Life 2.0 — job definitions, wages, first property rows
--
-- Invariants encoded here:
--   ADR-0008  Jobs are open to anyone. No qualification column exists, so none
--              can be added later without a schema change — that is deliberate.
--   ADR-0009  Wages are settings, not columns, so an economy pass is a data
--              change. They are placeholders until then.
--   ADR-0013  Housing is data. A new property is a new row, never new code.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Job definitions.
--
-- `kind` exists for one reason only: deciding which of them staff may hand out
-- radios and which are open to everyone. It is not a permission system, because
-- ADR-0008 removed the need for one — there is nothing to qualify for.
--
-- Wages deliberately do NOT live here. They live in settings keyed
-- `job.wage_per_hour.<code>`, so retuning the economy never touches this table
-- and adding a job never means remembering to add a price.
--
-- Migration 003 seeded the original roster with names confirmed by the owner:
-- police, ems, taxi, mechanic. Those four are left alone — not renamed, not
-- recoded. The ambulance job is `ems`, NOT `ambulance`; a second code for a job
-- that already exists would let a character sit in `character_jobs.ems` while the
-- wage table paid `job.wage_per_hour.ambulance`, and the shift would silently
-- earn nothing. This block only ADDS the jobs 003 did not have, and fills in
-- base coordinates that 003 left null.
-- ---------------------------------------------------------------------------
INSERT INTO job_defs (code, name, kind, is_emergency, base_x, base_y, base_z) VALUES
  ('police',   'Los Santos Police Department', 'department', 1, 454.96, -1017.38, 28.38),
  ('ems',      'Pillbox Medical',               'department', 1, 309.06, -595.66, 43.26),
  ('taxi',     'Taxi Driver',                  'civilian',   0, -809.18, -1018.88, 26.40),
  ('mechanic', 'Mechanic',                     'civilian',   0, -338.87, -135.35, 39.03),
  ('trucker',  'LKW-Fahrer',                   'civilian',   0, -1150.53, 1789.02, 78.77),
  ('tow',      'Abschleppdienst',              'civilian',   0, 826.31, -1223.50, 41.51),
  ('fire',     'Feuerwehr',                    'department', 1, 1191.55, -1614.21, 34.86)
ON DUPLICATE KEY UPDATE
  -- Coordinates only. `name` and `kind` are owned by migration 003 and must not
  -- drift from the confirmed roster.
  `base_x` = VALUES(`base_x`),
  `base_y` = VALUES(`base_y`),
  `base_z` = VALUES(`base_z`);

-- ---------------------------------------------------------------------------
-- Wages.
--
-- PLACEHOLDERS. The only relationships that matter yet:
--   * every wage must be meaningfully above `economy.stuetze.amount` per hour,
--     or ADR-0009's central assumption is false and idling beats working;
--   * criminal and civilian work must pay less than departments, or the Stütze
--     comparison inverts.
-- These numbers will be replaced by the economy pass and should not be defended.
-- ---------------------------------------------------------------------------
INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  -- Keys are job CODES, not display names. 'ems' is the code; 'ambulance' would
  -- create a wage nobody can ever be paid.
  ('job.wage_per_hour.mechanic',   '85.00',  'decimal', 'economy', 'Placeholder hourly wage (ADR-0009).'),
  ('job.wage_per_hour.taxi',       '70.00',  'decimal', 'economy', 'Placeholder hourly wage (ADR-0009).'),
  ('job.wage_per_hour.trucker',    '95.00',  'decimal', 'economy', 'Placeholder hourly wage (ADR-0009).'),
  ('job.wage_per_hour.tow',        '80.00',  'decimal', 'economy', 'Placeholder hourly wage (ADR-0009).'),
  ('job.wage_per_hour.police',     '110.00', 'decimal', 'economy', 'Placeholder hourly wage (ADR-0009).'),
  ('job.wage_per_hour.ems',        '115.00', 'decimal', 'economy', 'Placeholder hourly wage (ADR-0009).'),
  ('job.wage_per_hour.fire',       '115.00', 'decimal', 'economy', 'Placeholder hourly wage (ADR-0009).'),
  ('job.duty.min_seconds',         '300',    'int',     'economy', 'Minimum on-duty time before a shift pays out.'),
  ('economy.price.payslip',        '25.00',  'decimal', 'economy', 'Fee to start a shift (ADR-0009 sink).')
ON DUPLICATE KEY UPDATE `key` = `key`;
-- --------------------------------------------------------------------------
-- 006_shop_prices.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 006_shop_prices.sql
-- Nifty Life 2.0 — shop catalogue
--
-- Prices are settings, keyed by ITEM CODE. The shop has no price table: a price
-- is a tunable like any other (ADR-0009), so the economy pass edits rows here and
-- nothing in code.
--
-- Every price is a PLACEHOLDER. The one relationship that already matters: a
-- day's food must cost meaningfully more than `economy.stuetze.amount`, or the
-- Stütze stops being a floor and becomes an income.
-- ============================================================================

INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  ('economy.price.bread',       '12.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.water',       '8.00',  'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.coffee',      '15.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.bandage',     '40.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.painkillers', '35.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.lockpick',    '90.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.screwdriver', '25.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).')
ON DUPLICATE KEY UPDATE `key` = `key`;
-- --------------------------------------------------------------------------
-- 007_phone.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 007_phone.sql
-- Nifty Life 2.0 — phone accounts, numbers, message history
--
-- Invariants encoded here:
--   ADR-0018  The handset is an ordinary inventory item. The ACCOUNT — number,
--             messages, social — belongs to the character. Two characters can
--             hold two handsets and it changes nothing, because the phone is the
--             thing that matters and the thing is not the thing you carry.
--   ADR-0021  Numbers are server-assigned and permanent. UNIQUE is the backstop,
--             not the mechanism.
--   ADR-0004  Message history is permanent, exactly like money and property.
--
-- ON DELETION: a phone account is CASCADEd from the character. This is the one
-- place where losing history is accepted, because it only happens if someone
-- deletes a character, which the game offers no path to do. The alternative —
-- RESTRICT — would make character deletion impossible for the same reason it
-- does for the ledger, and that is a defensible position too; it is recorded
-- here rather than silently chosen.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- phone_accounts — one per character, created with the character.
--
-- `number` is public (ADR-0021): it appears in contacts and profiles, and it is
-- therefore part of what social content exposes. It is NOT a secret and must not
-- be treated as one.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_accounts (
  character_id  CHAR(36)      NOT NULL,
  number        VARCHAR(16)   NOT NULL,
  is_active     TINYINT(1)    NOT NULL DEFAULT 1,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (character_id),
  UNIQUE KEY uq_phone_accounts_number (number),
  CONSTRAINT fk_phone_account_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- phone_messages — permanent history.
--
-- Routing is by CHARACTER, not by number. ADR-0021 guarantees the number never
-- changes, so routing by number would also be stable — but routing by the
-- character is what the foreign keys can actually enforce, and an orphaned
-- message that nobody can be shown is worse than one that lost a number.
--
-- Deletion is per-recipient and per-sender (`cleared_by_*`). Deleting a message
-- is a private act: it hides it from you, and it does not reach into the other
-- person's inbox. Only staff can remove content outright (ADR-0019).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_messages (
  id                 CHAR(36)      NOT NULL,
  sender_id          CHAR(36)      NOT NULL,
  recipient_id       CHAR(36)      NOT NULL,
  body               VARCHAR(1000) NOT NULL,
  sent_at            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  read_at            DATETIME      NULL,
  cleared_by_sender  TINYINT(1)    NOT NULL DEFAULT 0,
  cleared_by_recipient TINYINT(1)  NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  -- The inbox query is "everything for me, newest first", so the index leads
  -- with the recipient.
  KEY ix_messages_recipient (recipient_id, sent_at),
  KEY ix_messages_sender (sender_id, sent_at),
  CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_messages_recipient FOREIGN KEY (recipient_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT chk_messages_not_self CHECK (sender_id <> recipient_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- phone_reports — moderation queue.
--
-- ADR-0019: players report, staff decide, and staff are the only ones who can
-- delete. This table is the handoff between those two halves; without it the
-- report button has nowhere to put anything.
--
-- The reporter is recorded so that abuse of the report button is itself
-- visible, and the target is recorded twice on purpose: the CHARACTER id (which
-- is what staff act on) and the MESSAGE id (which is what gets removed).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_reports (
  id             CHAR(36)      NOT NULL,
  reporter_id    CHAR(36)      NOT NULL,
  reported_char  CHAR(36)      NOT NULL,
  message_id     CHAR(36)      NULL,
  reason         VARCHAR(64)   NOT NULL,
  status         ENUM('open','actioned','dismissed') NOT NULL DEFAULT 'open',
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at    DATETIME      NULL,
  PRIMARY KEY (id),
  KEY ix_reports_status (status, created_at),
  KEY ix_reports_target (reported_char),
  CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_reports_target FOREIGN KEY (reported_char)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_reports_message FOREIGN KEY (message_id)
    REFERENCES phone_messages (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Number format. Placeholders (ADR-0021 says area coding can come later at no
-- structural cost, because this is the only thing that decides a number).
-- ---------------------------------------------------------------------------
INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  ('phone.number.prefix',        '555-',  'string',  'phone', 'Prefix for server-assigned numbers (ADR-0021).'),
  ('phone.number.digits',        '4',     'int',     'phone', 'Random digits per number.'),
  ('phone.message.max_length',   '1000',  'int',     'phone', 'Hard cap on a message body; the column agrees.')
ON DUPLICATE KEY UPDATE `key` = `key`;
-- --------------------------------------------------------------------------
-- 008_property_catalogue.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 008_property_catalogue.sql
-- Nifty Life 2.0 — the housing catalogue (ADR-0013)
--
-- ADR-0013: housing is DATA. A new residence is a new row in this table, never a
-- new Lua file, never a new subsystem. Everything below is stock GTA V geometry
-- (ADR-0012 — no purchased assets, no MLO).
--
-- ---------------------------------------------------------------------------
-- IDs are DERIVED, not random
-- ---------------------------------------------------------------------------
-- `properties.id` is CHAR(36). Nothing here uses UUID(), because a random UUID
-- would be re-issued on every re-run of this file and would orphan every row in
-- `property_owners` pointing at it. Ownership is a ROW (ADR-0013); a re-seed that
-- changes the property ID silently destroys the link and leaves a house that
-- belongs to nobody while the owner still believes otherwise.
--
-- So the ID is SHA1('nl2:housing:' || code), reshaped into UUID version 5 form
-- (the 13th hex digit forced to '5', the 17th to 'a'). Deterministic: same code
-- always yields the same ID, on every machine, in every environment.
--
-- ---------------------------------------------------------------------------
-- is_active is the verification flag, and is deliberately NOT updated on re-run
-- ---------------------------------------------------------------------------
-- `is_active = 0` means "the interior is not confirmed loadable yet" — the ⚠
-- entries in docs/housing-catalogue.md. `Ownership.listProperties` filters on
-- `is_active = 1`, so unverified houses are invisible rather than half-working:
-- an interior that silently fails to load gives no error, and a player who walks
-- into one finds himself standing in the world with no walls.
--
-- Bob74_IPL (ADR-0016) is how these get confirmed. A curator flips 0 -> 1 once
-- an interior has been seen to load. That flip must SURVIVE re-running this
-- file, so `is_active` is intentionally absent from the ON DUPLICATE clause.
-- Every other catalogue column IS updated, because the catalogue is their
-- source of truth.
--
-- ---------------------------------------------------------------------------
-- Deliberately empty columns
-- ---------------------------------------------------------------------------
-- `entrance_x/y/z` are NULL wherever docs/housing-catalogue.md records an
-- approximate coordinate (`(-141.x, -620.9, 168.8)`). Writing a rounded-off guess
-- into a DOUBLE makes it indistinguishable from a measured value, and a player
-- standing 40m from the door learns nothing about why.
--
-- `exit_x/y/z` are NULL for ALL rows. Teleporting into an IPL that has not been
-- confirmed to load puts the player in the void; the exit coordinates are part of
-- that verification, not before it. See ADR-0013.
--
-- `rent_amount` / `upkeep_amount` are 0.00. Ownership is free to obtain
-- (ADR-0013) and the TIER is supposed to govern the recurring sink (ADR-0009),
-- but the numbers themselves are a deferred economy pass (docs/PLAN.md). Writing
-- invented figures now would put fake numbers behind a live rent mechanic. They
-- are per-tier, so the pass is one UPDATE per tier.
--
-- COUNT: 61 residences. The catalogue document says 60; its District 8 heading
-- claimed 9 entries while listing 8, and its tier table counted Madrazos Ranch
-- twice. What is actually written down is 61, and that is what is seeded here.
-- ============================================================================

INSERT INTO properties
  (id, kind, code, name, district, tier, interior_ipl,
   entrance_x, entrance_y, entrance_z, storage_slots, is_active)
SELECT
  id,
  'housing', code, name, district, tier, ipl, x, y, z, slots, is_active
FROM (
  SELECT
    CONCAT(
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)),  1,  8), '-',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)),  9,  4), '-5',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)), 14,  3), '-a',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)), 18,  3), '-',
      SUBSTR(SHA1(CONCAT('nl2:housing:', code)), 21, 12)
    ) AS id,
    code, name, district, tier, ipl, x, y, z, slots, is_active
  FROM (
    -- -----------------------------------------------------------------------
    -- District 1 — Eclipse Towers, Pillbox (24) · premium
    -- All eight styles x three variants. Three entrance doors exist in the
    -- building; which door belongs to which variant is NOT confirmed, so
    -- variants 1/2/3 map to doors A/B/C in order. This is the single assumption
    -- in this migration that Bob74_IPL must check first.
    -- -----------------------------------------------------------------------
    SELECT 'ecl-modern-1' AS code, 'Eclipse Towers - Modern 1' AS name, 'Eclipse Towers' AS district,
           'premium' AS tier, 'apa_v_mp_h_01_a' AS ipl,
           -786.87 AS x, 315.72 AS y, 217.63 AS z, 15 AS slots, 1 AS is_active
    UNION ALL SELECT 'ecl-modern-2', 'Eclipse Towers - Modern 2', 'Eclipse Towers', 'premium', 'apa_v_mp_h_01_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-modern-3', 'Eclipse Towers - Modern 3', 'Eclipse Towers', 'premium', 'apa_v_mp_h_01_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-mody-1',    'Eclipse Towers - Mody 1',    'Eclipse Towers', 'premium', 'apa_v_mp_h_02_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-mody-2',    'Eclipse Towers - Mody 2',    'Eclipse Towers', 'premium', 'apa_v_mp_h_02_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-mody-3',    'Eclipse Towers - Mody 3',    'Eclipse Towers', 'premium', 'apa_v_mp_h_02_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-vibrant-1', 'Eclipse Towers - Vibrant 1', 'Eclipse Towers', 'premium', 'apa_v_mp_h_03_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-vibrant-2', 'Eclipse Towers - Vibrant 2', 'Eclipse Towers', 'premium', 'apa_v_mp_h_03_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-vibrant-3', 'Eclipse Towers - Vibrant 3', 'Eclipse Towers', 'premium', 'apa_v_mp_h_03_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-sharp-1',   'Eclipse Towers - Sharp 1',   'Eclipse Towers', 'premium', 'apa_v_mp_h_04_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-sharp-2',   'Eclipse Towers - Sharp 2',   'Eclipse Towers', 'premium', 'apa_v_mp_h_04_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-sharp-3',   'Eclipse Towers - Sharp 3',   'Eclipse Towers', 'premium', 'apa_v_mp_h_04_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-mono-1',    'Eclipse Towers - Monochrome 1',    'Eclipse Towers', 'premium', 'apa_v_mp_h_05_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-mono-2',    'Eclipse Towers - Monochrome 2',    'Eclipse Towers', 'premium', 'apa_v_mp_h_05_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-mono-3',    'Eclipse Towers - Monochrome 3',    'Eclipse Towers', 'premium', 'apa_v_mp_h_05_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-seductive-1', 'Eclipse Towers - Seductive 1', 'Eclipse Towers', 'premium', 'apa_v_mp_h_06_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-seductive-2', 'Eclipse Towers - Seductive 2', 'Eclipse Towers', 'premium', 'apa_v_mp_h_06_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-seductive-3', 'Eclipse Towers - Seductive 3', 'Eclipse Towers', 'premium', 'apa_v_mp_h_06_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-regal-1',   'Eclipse Towers - Regal 1',   'Eclipse Towers', 'premium', 'apa_v_mp_h_07_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-regal-2',   'Eclipse Towers - Regal 2',   'Eclipse Towers', 'premium', 'apa_v_mp_h_07_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-regal-3',   'Eclipse Towers - Regal 3',   'Eclipse Towers', 'premium', 'apa_v_mp_h_07_b', -774.02, 342.07, 196.69, 15, 1
    UNION ALL SELECT 'ecl-aqua-1',    'Eclipse Towers - Aqua 1',    'Eclipse Towers', 'premium', 'apa_v_mp_h_08_a', -786.87, 315.72, 217.63, 15, 1
    UNION ALL SELECT 'ecl-aqua-2',    'Eclipse Towers - Aqua 2',    'Eclipse Towers', 'premium', 'apa_v_mp_h_08_c', -786.93, 315.68, 187.91, 15, 1
    UNION ALL SELECT 'ecl-aqua-3',    'Eclipse Towers - Aqua 3',    'Eclipse Towers', 'premium', 'apa_v_mp_h_08_b', -774.02, 342.07, 196.69, 15, 1

    -- -----------------------------------------------------------------------
    -- District 2 — Downtown studios (9) · entry
    -- Office interiors reused as studios. Entrance coordinates are NULL: the
    -- catalogue records them only as (-141.x, -620.9, 168.8) and the .x is an
    -- ellipsis, not a truncated digit.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'dt-arcadius-rich',     'Arcadius - Executive Rich', 'Downtown', 'entry', 'ex_dt1_02_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-cool',     'Arcadius - Cool',           'Downtown', 'entry', 'ex_dt1_02_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-contrast', 'Arcadius - Contrast',       'Downtown', 'entry', 'ex_dt1_02_office_02a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-warm',     'Arcadius - Old Spice Warm', 'Downtown', 'entry', 'ex_dt1_01_office_01a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-classical','Arcadius - Classical',      'Downtown', 'entry', 'ex_dt1_01_office_01b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-vintage',  'Arcadius - Vintage',        'Downtown', 'entry', 'ex_dt1_01_office_01c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-rich',     'Maze Bank Tower - Executive Rich', 'Downtown', 'entry', 'ex_dt1_11_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-cool',     'Maze Bank Tower - Cool',           'Downtown', 'entry', 'ex_dt1_11_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-contrast', 'Maze Bank Tower - Contrast',       'Downtown', 'entry', 'ex_dt1_11_office_02a', NULL, NULL, NULL, 6, 1

    -- -----------------------------------------------------------------------
    -- District 3 — Del Perro studios (6) · entry
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'dp-lom-rich',          'Lom Bank - Executive Rich',      'Del Perro', 'entry', 'ex_sm_13_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-lom-cool',          'Lom Bank - Cool',                'Del Perro', 'entry', 'ex_sm_13_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-lom-contrast',      'Lom Bank - Contrast',            'Del Perro', 'entry', 'ex_sm_13_office_02a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-rich',    'Maze Bank West - Executive Rich', 'Del Perro', 'entry', 'ex_sm_15_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-cool',    'Maze Bank West - Cool',           'Del Perro', 'entry', 'ex_sm_15_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-contrast','Maze Bank West - Contrast',       'Del Perro', 'entry', 'ex_sm_15_office_02a', NULL, NULL, NULL, 6, 1

    -- -----------------------------------------------------------------------
    -- District 4 — Vinewood & Richman (4) · standard
    -- The three shells are marked `NO IPL` in the reference: the building exists
    -- in the map geometry, the interior is unconfirmed. Hence is_active = 0.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'vinewood-michael', 'Michael''s House', 'Vinewood / Richman', 'standard', NULL, -85.00, -785.00, NULL, 10, 1
    UNION ALL SELECT 'nconker-2044', '2044 North Conker Avenue', 'Vinewood / Richman', 'standard', NULL, 340.94, 437.18, 149.39, 10, 0
    UNION ALL SELECT 'nconker-2045', '2045 North Conker Avenue', 'Vinewood / Richman', 'standard', NULL, 373.02, 416.11, 145.70, 10, 0
    UNION ALL SELECT 'madwayne-2133', '2133 Mad Wayne Thunder Drive', 'Vinewood / Richman', 'standard', NULL, -1288.00, 440.75, 97.69, 10, 0

    -- -----------------------------------------------------------------------
    -- District 5 — Vinewood Hills (2) · premium
    -- Wild Oats carries the catalogue's warning that its coordinates sit almost
    -- exactly on top of Franklin's Mansion — probable transcription error, so
    -- it stays inactive until someone stands in both and finds out.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'whispymound-3671', '3671 Whispymound Drive', 'Vinewood Hills', 'premium', NULL, -169.29, 486.49, 137.44, 15, 1
    UNION ALL SELECT 'wildoats-3655',   '3655 Wild Oats Drive',   'Vinewood Hills', 'premium', NULL, -169.29, 486.49, 137.44, 15, 0

    -- -----------------------------------------------------------------------
    -- District 6 — Rockford Hills / Hillcrest (3) · luxury
    -- Shell entries, same reason as District 4.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'hillcrest-2862', '2862 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -676.13, 588.61, 145.17, 25, 0
    UNION ALL SELECT 'hillcrest-2868', '2868 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -763.11, 615.91, 144.14, 25, 0
    UNION ALL SELECT 'hillcrest-2874', '2874 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -857.80, 682.56, 152.65, 25, 0

    -- -----------------------------------------------------------------------
    -- District 7 — Davis (2) · standard
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'davis-aunt',        'Franklin''s Aunt House', 'Davis', 'standard', NULL, -67.00, -809.00, NULL, 10, 1
    UNION ALL SELECT 'davis-whispymound-2677', '2677 Whispymound Drive', 'Davis', 'standard', NULL, 120.50, 549.95, 184.10, 10, 0

    -- -----------------------------------------------------------------------
    -- District 8 — Outskirts & rural (8)
    -- The catalogue heading says 9. It lists 8. These 8 are what is written
    -- down, so these 8 are what exists.
    --
    -- Trevor's Trailer carries a note worth keeping: `TrevorsMP` and
    -- `TrevorsTrailerTidy` are the dirty and clean STATES of one trailer, not
    -- two residences. interior_ipl stays NULL because the interior is part of
    -- the base map and is entered by walking, not by loading an IPL.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'outskirts-trailer',  'Trevor''s Trailer',        'Outskirts', 'standard', NULL, 1975.55, 3820.54, 33.45, 10, 1
    UNION ALL SELECT 'outskirts-motel',    'The Motor Motel',          'Outskirts', 'standard', NULL, 152.26, -1004.47, -99.00, 10, 1
    UNION ALL SELECT 'outskirts-floyd',    'Floyd''s Apartment',       'Outskirts', 'standard', NULL, NULL, NULL, NULL, 10, 0
    UNION ALL SELECT 'outskirts-molina',   'Harvey Molina''s Apartment', 'Outskirts', 'standard', NULL, NULL, NULL, NULL, 10, 0
    UNION ALL SELECT 'outskirts-madrazos', 'Madrazos Ranch',           'Outskirts', 'outlier',  NULL, 1399.00, 1150.00, 115.00, 8, 0
    UNION ALL SELECT 'outskirts-oneil',    'O''Neil Ranch',            'Outskirts', 'outlier',  'farm', 2469.03, 4955.28, 45.12, 8, 1
    UNION ALL SELECT 'outskirts-casino',   'Diamond Casino Penthouse', 'Outskirts', 'luxury',   'vw_casino_penthouse', 976.64, 70.30, 115.16, 25, 1
    UNION ALL SELECT 'outskirts-lester',   'Lester''s House',          'Outskirts', 'standard', NULL, 1273.90, -1719.31, 54.77, 10, 1

    -- -----------------------------------------------------------------------
    -- District 9 — Northern Los Santos (3) · outlier
    -- North is structurally starved: bunkers are the only stock interior up
    -- there. Framed as rough hideouts rather than pretending the north has
    -- housing.
    -- -----------------------------------------------------------------------
    UNION ALL SELECT 'bunker-paleto',    'Paleto Bunker',    'Northern Los Santos', 'outlier', 'gr_case7_bunkerclosed',  -783.08, 5934.69, 24.31, 8, 1
    UNION ALL SELECT 'bunker-grapeseed', 'Grapeseed Bunker', 'Northern Los Santos', 'outlier', 'gr_case5_bunkerclosed', 1823.96, 4708.14, 42.50, 8, 1
    UNION ALL SELECT 'bunker-chumash',   'Chumash Bunker',   'Northern Los Santos', 'outlier', 'gr_case11_bunkerclosed', -3180.47, 1374.19, 19.96, 8, 1
  ) AS seed
) AS property
ON DUPLICATE KEY UPDATE
  `name`          = VALUES(`name`),
  `district`      = VALUES(`district`),
  `tier`          = VALUES(`tier`),
  `interior_ipl`  = VALUES(`interior_ipl`),
  `entrance_x`    = VALUES(`entrance_x`),
  `entrance_y`    = VALUES(`entrance_y`),
  `entrance_z`    = VALUES(`entrance_z`),
  `storage_slots` = VALUES(`storage_slots`);
  -- `is_active` is intentionally NOT in this list — see the header. Re-running
  -- this migration must not undo an interior that Bob74_IPL has since confirmed.
-- --------------------------------------------------------------------------
-- 009_peeper_and_web_link.sql
-- --------------------------------------------------------------------------
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
-- --------------------------------------------------------------------------
-- 010_one_application_per_person.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 010_one_application_per_person.sql
-- One application per person, ever.
--
-- The rule is that a submitted application is the application. There is no
-- second attempt: a rejection is not something you re-apply over, it is
-- something you take up with the team in Discord.
--
-- Enforced as a UNIQUE index rather than in application code, for the same
-- reason ADR-0008 puts a UNIQUE on `characters.account_id`: "one of these per
-- person" is a property of the data, not of a check somebody forgot to write.
-- Application code also loses races — two tabs, a double click, a retry — and a
-- whitelist that can be entered twice is a whitelist that will be.
--
-- `ix_applications_discord` becomes redundant: a UNIQUE index on the same
-- column serves every lookup the plain index served, plus this constraint.
--
-- The error this produces surfaces as ER_DUP_ENTRY (1062) on INSERT. That is
-- deliberately not swallowed into a generic failure — `submitApplication`
-- recognises it and reports "you have already applied".
-- ============================================================================

-- Only one application per Discord ID may ever exist.
ALTER TABLE applications
  DROP INDEX ix_applications_discord,
  ADD UNIQUE KEY uq_applications_discord (discord_id);

-- ---------------------------------------------------------------------------
-- Verify (all four should return exactly the rows described):
--
--   INSERT INTO applications (id, discord_id, answers)
--     VALUES (UUID(), '<an id already in the table>', '{}');   -- denied: 1062
--
--   SELECT COUNT(*) FROM applications
--    WHERE discord_id = '<a fresh id>';                        -- 0
--
--   INSERT INTO applications (id, discord_id, answers)
--     VALUES (UUID(), '<a fresh id>', '{}');                  -- allowed
--
--   SELECT status FROM applications
--    WHERE discord_id = '<the rejected one>';                 -- still rejected
--     nothing was overwritten by the failed insert
-- ---------------------------------------------------------------------------
-- --------------------------------------------------------------------------
-- 011_staff_from_discord_roles.sql
-- --------------------------------------------------------------------------
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
-- --------------------------------------------------------------------------
-- 012_staff_peeper_authorship.sql
-- --------------------------------------------------------------------------
-- 012_staff_peeper_authorship.sql
--
-- The moderation team may write to P&R without ever having played the game.
--
-- WHY. Migration 009 made `peeper_posts.author_character` NOT NULL with a foreign
-- key to `characters`, which encoded a single rule: a post has an author, and the
-- author is a character. That rule is right for players and wrong for the team.
-- A moderator who has not created a character could not post, and the only ways
-- to give them one were both bad — hand them a real in-game character (which the
-- game server would then pay a Stütze to, and which appears in every character
-- list as a person who does not exist) or drop the foreign key and let posts
-- have no owner at all. Neither is worth it.
--
-- So authorship becomes explicitly two-sided: EITHER a character OR a Discord
-- account, never neither, never both. The CHECK constraint below is what makes
-- that a database fact rather than a convention, and it is why a staff post is
-- still attributable — which is the entire point of ADR-0022.
--
-- Nothing is dropped here. Every existing row keeps its `author_character` and
-- `author_discord_id` is NULL on all of them, so the constraint is satisfied by
-- construction.
--
-- DELETION. The team can now delete a post. It is a SOFT delete through the
-- `deleted_at` / `deleted_by` / `deleted_reason` columns that migration 009
-- already created for exactly this, and not a physical DELETE: this project does
-- not throw things away, and a removed post is evidence three months later when
-- somebody asks why a comment vanished. The row stays.
--
-- Migration 013 continues this for likes and reports.

-- ---------------------------------------------------------------------------
-- peeper_posts — authorship is character OR Discord account.
--
-- `source` gains 'staff' rather than reusing 'web'. The existing comment on that
-- column is right: a pattern of reports has to point at a surface, because the
-- game and the website have completely different moderation costs. A staff post
-- is a third surface again — nobody reports those, and the team needs to tell
-- its own announcements apart from a player's web post at a glance.
-- ---------------------------------------------------------------------------
ALTER TABLE peeper_posts
  MODIFY author_character CHAR(36) NULL,
  MODIFY source ENUM('game','web','staff') NOT NULL DEFAULT 'game',
  ADD COLUMN IF NOT EXISTS author_discord_id VARCHAR(32) NULL AFTER author_character,
  ADD COLUMN IF NOT EXISTS deleted_by_discord_id VARCHAR(32) NULL AFTER deleted_by,
  ADD KEY IF NOT EXISTS ix_peeper_author_discord (author_discord_id, created_at),
  ADD CONSTRAINT IF NOT EXISTS chk_peeper_author CHECK (
    (author_character IS NULL) <> (author_discord_id IS NULL)
  );
-- --------------------------------------------------------------------------
-- 013_staff_peeper_likes_and_reports.sql
-- --------------------------------------------------------------------------
-- 013_staff_peeper_likes_and_reports.sql
--
-- Continues migration 012 for the two tables that also key on a character.
--
-- THE PROBLEM WITH A NULL KEY. `peeper_likes` was PRIMARY KEY (post_id,
-- character_id). Making character_id nullable breaks a primary key outright,
-- because NULL is not allowed in a key column. Switching to
-- UNIQUE(post_id, author_discord_id) does not help either: in SQL, NULL is
-- distinct from NULL, so the same moderator could like the same post fifty times
-- and every one of them would be a "unique" row.
--
-- THE FIX. A BEFORE INSERT trigger fills `actor` — one non-null string that is
-- the character id for a player and the Discord id for the team — and the unique
-- key lands on that. One rule, both identities, no NULL semantics anywhere.
--
-- A generated column would be tidier, and this file started that way:
--
--   actor VARCHAR(32) GENERATED ALWAYS AS (COALESCE(character_id, author_discord_id)) STORED
--   ERROR 1901 (HY000): Function or expression 'coalesce(...)' cannot be used
--   in the GENERATED ALWAYS AS clause of `actor`
--
-- MariaDB accepts only a restricted set of deterministic built-in functions
-- there, and COALESCE is not among them. The trigger is the portable answer and
-- has the advantage of holding the CHECK too, so a row that somehow arrived
-- with neither identity is rejected by the database rather than stored.

-- ---------------------------------------------------------------------------
-- peeper_likes — the PK becomes a surrogate, the uniqueness moves to `actor`.
-- ---------------------------------------------------------------------------
ALTER TABLE peeper_likes
  DROP PRIMARY KEY,
  ADD COLUMN id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST,
  MODIFY character_id CHAR(36) NULL,
  ADD COLUMN author_discord_id VARCHAR(32) NULL AFTER character_id,
  ADD COLUMN actor VARCHAR(32) NULL,
  ADD UNIQUE KEY uq_peeper_likes_actor (post_id, actor),
  ADD KEY ix_peeper_likes_discord (author_discord_id);
-- `ix_peeper_likes_character` already exists from migration 009 and stays: a
-- nullable column still uses that index for player likes.

DROP TRIGGER IF EXISTS trg_peeper_likes_actor;

DELIMITER //
CREATE TRIGGER trg_peeper_likes_actor BEFORE INSERT ON peeper_likes
FOR EACH ROW
BEGIN
  IF NEW.character_id IS NULL AND NEW.author_discord_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'a like needs either a character or a discord account';
  END IF;

  SET NEW.actor = COALESCE(NEW.character_id, NEW.author_discord_id);
END//
DELIMITER ;

-- ---------------------------------------------------------------------------
-- peeper_reports — a team member reporting a player's post is a normal thing
-- that should be possible. Reports have a surrogate PK already, so this is only
-- the authorship side.
--
-- No trigger needed: nothing here is keyed on the identity, so the CHECK alone
-- is enough to keep it honest.
-- ---------------------------------------------------------------------------
ALTER TABLE peeper_reports
  MODIFY reporter CHAR(36) NULL,
  ADD COLUMN reporter_discord_id VARCHAR(32) NULL AFTER reporter,
  ADD KEY ix_peeper_reports_reporter_discord (reporter_discord_id),
  ADD CONSTRAINT chk_peeper_reporter CHECK (
    (reporter IS NULL) <> (reporter_discord_id IS NULL)
  );
-- --------------------------------------------------------------------------
-- 014_column_scope_website_peeper_writes.sql
-- --------------------------------------------------------------------------
-- 014_column_scope_website_peeper_writes.sql
--
-- Migration 012 opened a hole, and it is closed here rather than in code.
--
-- THE HOLE. `peeper_posts.author_character` used to be NOT NULL with a foreign
-- key, so the public pool could only ever write a row attributed to a real
-- character — that constraint was the authorship guarantee. Migration 012 made
-- the column nullable and added `author_discord_id` for team posts, and
-- `nifty_website` holds a TABLE-LEVEL `INSERT` on `peeper_posts`. A table-level
-- grant cannot express "every column except this one", so after 012 the public
-- pool could insert a post attributed to ANY Discord account — including the
-- owner's. Not reachable through the shipped code, which never writes that
-- column, but reachable by any future code path, mistake or compromise on the
-- web server. That is exactly the class of problem grants exist to make
-- impossible rather than reviewable.
--
-- THE FIX, in two halves.
--
-- 1. Column-scoped INSERT for the public pool. `author_discord_id` is simply not
--    in the list, so the public account cannot name a Discord author — the
--    driver rejects the statement, not a reviewer's careful reading of it.
--
-- 2. A CHECK tying `source` to authorship. Without it, column (1) alone is not
--    enough: `source` is still grantable, so the public pool could label a
--    character post as 'staff' and put a Team badge on a player's words. With
--    the constraint, 'staff' REQUIRES a Discord author, which the public pool
--    cannot supply, so it cannot produce a staff post at all.

ALTER TABLE peeper_posts
  ADD CONSTRAINT chk_peeper_staff_authorship CHECK (
    source <> 'staff'
    OR (author_discord_id IS NOT NULL AND author_character IS NULL)
  );

-- The same reasoning for likes and reports. Neither is security-critical the
-- way authorship is — a forged like is a counter, a forged report is a queue
-- entry the game server resolves — but "the public pool can only ever be a
-- character" is one rule, and making it three exceptions is how it stops being
-- true. `actor` on `peeper_likes` is filled by the trigger and stays unwritable
-- on every account.
ALTER TABLE peeper_likes
  ADD CONSTRAINT chk_peeper_likes_staff_author CHECK (
    author_discord_id IS NULL OR character_id IS NULL
  );
-- --------------------------------------------------------------------------
-- 015_portal_accounts.sql
-- --------------------------------------------------------------------------
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
-- --------------------------------------------------------------------------
-- 016_confirm_portal_email.sql
-- --------------------------------------------------------------------------
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
-- --------------------------------------------------------------------------
-- 017_confirm_portal_email_single_use.sql
-- --------------------------------------------------------------------------
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
-- --------------------------------------------------------------------------
-- 018_regrant_confirm_procedure.sql
-- --------------------------------------------------------------------------
-- 018_regrant_confirm_procedure.sql
--
-- Restores the EXECUTE grant dropped by migration 017.
--
-- WHAT I GOT WRONG. Migration 017 ends with the comment "The grant from 016
-- survives a DROP/CREATE: privileges on routines are by name, not by body." That
-- is false in MariaDB. Dropping a routine DOES drop its routine-level
-- privileges, so recreating it leaves the procedure present and unexecutable —
-- and the failure arrives as
--
--   ERROR 1142 (42000): EXECUTE command denied to user 'nifty_website'@'localhost'
--   for routine 'nifty_life.confirm_portal_email'
--
-- The confirmation probe caught it on the next run. Which is the second time in
-- this feature that a claim made in a comment turned out to be wrong and only a
-- test noticed; the first was reading the wrong result set. The rule is not "trust
-- the comment", it is "if a comment asserts something the database can check, the
-- comment does not get to be the evidence".
--
-- GRANT is idempotent, so running this on a fresh install where 016's grant is
-- still intact does nothing.

GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email TO 'nifty_website'@'localhost';

FLUSH PRIVILEGES;
-- --------------------------------------------------------------------------
-- 019_chat_settings.sql
-- --------------------------------------------------------------------------
-- 019_chat_settings.sql
--
-- Tunables for the in-game chat, which replaces the downloaded `chat` resource.
--
-- WHY A MIGRATION. ADR-0009 puts every tunable in `settings` so tuning is a data
-- change rather than a code change, and `GetSetting` warns loudly about a key that
-- is missing rather than falling back silently. A radius that only existed in
-- `sv_chat.lua` would be untunable without a code change and a resource restart,
-- which is the failure mode ADR-0009 was written to prevent.
--
-- These four are the SERVER-authoritative values. Two presentation values are not
-- here on purpose: `chat.log_lines` and `chat.fade_ms` never reach the server, so
-- putting them in a table the server owns would be a second source of truth for a
-- number only the browser ever reads. They live in `ui/app.js` with a comment
-- saying so.
--
-- `chat.radius` is the load-bearing one. A weekend whitelist server is not a
-- shooter: hearing somebody two kilometres away is not a feature, and it makes
-- every scene in the game a public channel.

INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  -- How far away a character can be and still be heard. OneSync is required
  -- (`/server:4500` in the nifty-core manifest) because this is a server-side
  -- distance check, not a client-side guess.
  ('chat.radius',              '40',   'int',     'chat', 'Hearing radius in metres. Server-side OneSync distance check.'),

  -- Minimum gap between two messages from one player. This is the spam guard and
  -- it is the reason the server is allowed to broadcast without a per-player
  -- bucket: 1200 ms keeps a conversation readable and caps one client at roughly
  -- 50 messages a minute.
  ('chat.cooldown_ms',         '1200', 'int',     'chat', 'Minimum milliseconds between two messages from one player.'),

  -- Hard ceiling on one message, enforced on the server. The client field is
  -- `maxlength="150"` for the typist's benefit and is not a rule: a client that
  -- lies here gets truncated, not rejected.
  ('chat.max_length',          '150',  'int',     'chat', 'Maximum characters in one chat message.'),

  -- Kept so an operator can widen the chat later without a code change. Deliberately
  -- generous: the anti-spam ceiling for a whitelist server is "annoying", and the
  -- cost of being slightly too strict is a confused player, not a security hole.
  ('chat.history',             '200',  'int',     'chat', 'Reserved: retained chat lines. Not read by the client yet.');
-- --------------------------------------------------------------------------
-- 020_character_identity_on_web.sql
-- --------------------------------------------------------------------------
-- 020_character_identity_on_web.sql
--
-- The character is created on the WEBSITE, not in the game. The player gives name,
-- gender, date of birth and birthplace there; the in-game creator is left with
-- appearance alone. This migration gives the database the two things that flow
-- requires and that 001 could not have: a birthplace, and a name that is actually
-- UNIQUE.
--
-- WHY THIS FILE EXISTS SEPARATELY. 001 is applied to existing databases too, and
-- a migration that is edited after the fact changes the meaning of a historical
-- schema. Everything here is additive.
--
-- ---------------------------------------------------------------------------
-- 1. birthplace
-- ---------------------------------------------------------------------------
--
-- Asked on the website alongside the rest of the identity. A free-text VARCHAR
-- rather than a lookup table: this is a weekend roleplay server for dozens of
-- characters, the answer is only ever displayed as text, and normalising real
-- place names into a table would buy nothing but a second source of truth.
--
-- NULL because it is nullable in the application too — a player may leave it out,
-- and inventing a default would put a lie in everyone's character sheet.
--
-- ---------------------------------------------------------------------------
-- 2. Name uniqueness — the important half
-- ---------------------------------------------------------------------------
--
-- The requirement is "the website tells the player when a name is taken". A check
-- in the website can do that for the person standing in front of the form. It
-- cannot do it for the person who submits two seconds later: between the SELECT
-- and the INSERT another player can take the same name, and the second INSERT
-- simply succeeds. `ix_characters_name` from 001 is a plain index — it makes
-- lookups fast and enforces nothing.
--
-- So uniqueness has to live in the database, and the website's check becomes an
-- optimization (better error message, no failed insert) rather than the guarantee.
--
-- The generated column exists for ONE reason: `last_name` is NULLABLE, and in
-- SQL NULL never equals NULL in a unique index. "Lena" with no surname would
-- therefore be insertable any number of times while "Lena Mustermann" was not.
-- Coalescing into a single non-null key closes that hole without forcing a
-- surname on players who do not want one.
--
-- TRIM is there because 'Max ' and 'Max' are the same name to a human and two
-- different rows to a plain index.
--
-- Collation does the case- and accent-insensitive part for free: the table is
-- utf8mb4_unicode_ci, where 'MAX' = 'max' and 'Müller' = 'Muller'. That is the
-- behaviour we want — one name, one character, however it was typed.
--
-- STORED, not VIRTUAL, because a UNIQUE index on a virtual column is rebuilt on
-- every read in some MySQL/MariaDB versions, and this key is written on every
-- character creation.

-- ---------------------------------------------------------------------------

ALTER TABLE characters
  ADD COLUMN birthplace VARCHAR(96) NULL AFTER gender;

-- Dropped and replaced by uq_characters_name below. Keeping both would cost a
-- second index over the same two columns for no query that the unique one does not
-- already serve.
ALTER TABLE characters
  DROP INDEX ix_characters_name;

ALTER TABLE characters
  ADD COLUMN name_key VARCHAR(161)
    GENERATED ALWAYS AS (
      CONCAT(TRIM(first_name), '|', TRIM(COALESCE(last_name, '')))
    ) STORED
    COMMENT 'Normalised name key. UNIQUE on this is what makes a name unclaimable.';

-- The generated column carries utf8mb4_unicode_ci from the table, so this index is
-- case- and accent-insensitive. A player cannot register "Max", then "MAX", then
-- "max" and pass three checks.
--
-- 161 = 64 + 1 + 64, plus slack. utf8mb4 counts characters, not bytes, so this is
-- the character budget and not an overflow risk.
ALTER TABLE characters
  ADD UNIQUE KEY uq_characters_name (name_key);

-- ---------------------------------------------------------------------------
-- 3. The "created on the web, not finished in game" state
-- ---------------------------------------------------------------------------
--
-- `appearance` was already nullable, and that is the whole signal: a character
-- whose appearance IS NULL was created on the website and has never been through
-- the creator. The server opens the creator on exactly this condition, and the
-- creator runs again on every login until it completes.
--
-- No new column and no new state machine. A status enum here would be a second
-- way to say "not finished", and two ways to say the same thing drift.
-- ---------------------------------------------------------------------------
-- --------------------------------------------------------------------------
-- 021_create_character_from_web.sql
-- --------------------------------------------------------------------------
-- 021_create_character_from_web.sql
--
-- The website creates the character. This is the ONLY way a character row is
-- created, and it is a stored procedure rather than an INSERT grant on purpose.
--
-- ---------------------------------------------------------------------------
-- WHY A PROCEDURE AND NOT `GRANT INSERT ON characters`
-- ---------------------------------------------------------------------------
--
-- database/grants.sql documents, at line 244, that the website must NOT be able to
-- insert a character — and the surrounding comments explain why that boundary is
-- there at all: the website is the one account a compromise would actually hold,
-- and every other write it performs is column-scoped or absent.
--
-- A plain INSERT grant would make that comment a lie, and it would also buy
-- nothing. The website cannot know `account_id` — it is a UUID minted by the game
-- server and never exposed — so every character it inserted would have to come
-- from a lookup it is not allowed to do, or from a value it is not allowed to
-- read. The INSERT would be structurally impossible to write correctly.
--
-- So the procedure takes the thing the website actually HAS (a Discord ID) and
-- resolves everything else itself. This is the same pattern migration 016 already
-- uses for email confirmation, and the same recommendation grants.sql already
-- makes in its closing note: a constraint that must hold belongs in the database,
-- not in reviewable application code.
--
-- What the website gains: EXECUTE on one procedure.
-- What it still cannot do: touch any other character, attach a character to
-- somebody else's account, or write a character row directly.
--
-- ---------------------------------------------------------------------------
-- THE PHONE NUMBER IS ALLOCATED HERE TOO
-- ---------------------------------------------------------------------------
--
-- ADR-0021: a number is permanent and must exist from the character's first
-- second, and identity.lua used to insert it in the same transaction as the
-- character row. That code is moving to the website, so this procedure inherits
-- the duty. Leaving it out would produce characters that exist but can never be
-- messaged, with no way to repair them after the fact — a permanent number that
-- was never assigned is not something a later code path can fix without breaking
-- the guarantee that it never changes.
--
-- The number format is read from `settings`, the same two keys the game used, so
-- tuning the prefix stays a data change (ADR-0009) rather than a code change.
--
-- Collision is resolved here rather than by relying on UNIQUE: the loop below
-- asks first, and the UNIQUE constraint on phone_accounts remains the backstop.
-- The loop is bounded, so a pathological database cannot spin forever.
--
-- ---------------------------------------------------------------------------
-- RETURN CONTRACT
-- ---------------------------------------------------------------------------
--
-- Exactly one row, always. A procedure whose success and failure are signalled
-- differently — a result set for success and an exception for failure — is a
-- procedure every caller has to write two branches for, and one of them is
-- always wrong.
--
--   ok           1 on success, 0 otherwise
--   character_id the new UUID, NULL on failure
--   code         a stable machine token, safe to switch on
--   message      a sentence the website may show or may not
--
-- `code` is the contract. `message` is prose for a human and is not stable.

DROP PROCEDURE IF EXISTS create_character_from_web;

DELIMITER //

-- ---------------------------------------------------------------------------
-- WHY THE STRING PARAMETERS ARE 255 AND NOT THEIR COLUMN WIDTH
--
-- A parameter declared exactly as wide as its column makes that column's own
-- validation unreachable. MariaDB checks the argument against the parameter type
-- in strict mode while binding it, and raises `Data too long for column
-- 'p_last_name'` before the body has run a single statement. The
-- `invalid_last_name` guard further down can therefore never fire - the routine
-- dies with a driver error instead of the documented contract row, which is the
-- one thing the RETURN CONTRACT below exists to prevent.
--
-- So every text parameter is declared wide enough to receive rubbish, and the
-- body is what decides whether that rubbish is acceptable. The column widths are
-- the real limits and they are still enforced - by the guards here and by the
-- schema itself.
-- ---------------------------------------------------------------------------
CREATE PROCEDURE create_character_from_web(
  IN  p_discord_id     CHAR(64),
  IN  p_first_name     VARCHAR(255),
  IN  p_last_name      VARCHAR(255),
  IN  p_gender         VARCHAR(64),
  IN  p_date_of_birth  DATE,
  IN  p_birthplace     VARCHAR(255)
)
-- ---------------------------------------------------------------------------
-- WHY THE BODY IS A LABELLED BLOCK
--
-- The routine bails out early ten times with LEAVE, so that a rejected field is
-- reported as a sentence instead of as a constraint violation. LEAVE is only
-- legal inside a LABELLED block or inside a LOOP - an unlabelled `BEGIN` does
-- not count, and neither does an `IF` branch. Without this label the routine
-- does not merely misbehave, it fails to compile: MariaDB raises ER_PARSE_ERROR
-- at the first `LEAVE proc_main;` and the procedure is never created.
--
-- The label must sit in front of BEGIN. The DECLAREs stay directly inside it,
-- because that is still the first thing a stored program may declare.
--
-- This is also why the DELIMITER lines below are only needed for a CLIENT-side
-- runner. Over the wire the whole CREATE PROCEDURE goes out as one statement and
-- the server parses the body itself - any GUI that splits on `;` will break this
-- routine no matter how the SQL is written.
-- ---------------------------------------------------------------------------
proc_main: BEGIN
  DECLARE v_account_id  CHAR(36) DEFAULT NULL;
  DECLARE v_character_id CHAR(36) DEFAULT NULL;
  DECLARE v_exists      INT DEFAULT 0;

  DECLARE v_prefix      VARCHAR(8)  DEFAULT '555-';
  DECLARE v_digits      TINYINT     DEFAULT 4;
  DECLARE v_number      VARCHAR(16) DEFAULT NULL;
  DECLARE v_candidate   VARCHAR(16) DEFAULT NULL;
  DECLARE v_suffix      VARCHAR(12) DEFAULT NULL;
  DECLARE v_attempts    INT         DEFAULT 0;
  DECLARE v_cash        DECIMAL(14,2) DEFAULT 0.00;
  DECLARE v_bank        DECIMAL(14,2) DEFAULT 0.00;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    -- Any unexpected failure — a duplicate that slipped past the checks, a lock
    -- timeout — must not leave a half-created character. The whole body is one
    -- transaction under the caller's autocommit, and rolling back here is what
    -- makes the procedure all-or-nothing.
    ROLLBACK;
    SELECT 0 AS ok, NULL AS character_id, 'error' AS code,
           'Der Charakter konnte nicht angelegt werden.' AS message;
  END;

  -- -------------------------------------------------------------------------
  -- Normalise and reject obvious rubbish BEFORE any lookup, so a failure is
  -- reported as a bad field rather than as "name taken" or "no account".
  -- -------------------------------------------------------------------------

  SET p_first_name = NULLIF(TRIM(p_first_name), '');

  IF p_last_name IS NOT NULL THEN
    SET p_last_name = NULLIF(TRIM(p_last_name), '');
  END IF;

  IF p_first_name IS NULL OR CHAR_LENGTH(p_first_name) > 64 THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_first_name' AS code,
           'Bitte einen Vornamen angeben (maximal 64 Zeichen).' AS message;
    LEAVE proc_main;
  END IF;

  IF p_last_name IS NOT NULL AND CHAR_LENGTH(p_last_name) > 64 THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_last_name' AS code,
           'Der Nachname ist zu lang (maximal 64 Zeichen).' AS message;
    LEAVE proc_main;
  END IF;

  -- Same reasoning as the name guards: the parameter is 255 wide so that this
  -- check is reachable, and the column is VARCHAR(96). Without a guard here a
  -- long birthplace would fall through to the EXIT HANDLER and come back as the
  -- useless `error`, instead of naming the field that is wrong.
  IF p_birthplace IS NOT NULL AND CHAR_LENGTH(p_birthplace) > 96 THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_birthplace' AS code,
           'Der Geburtsort ist zu lang (maximal 96 Zeichen).' AS message;
    LEAVE proc_main;
  END IF;

  -- The enum is the schema's business, not the caller's. A gender the column
  -- cannot store would abort the INSERT with a driver error, which reads as a
  -- crash rather than as a rejected form field.
  IF p_gender IS NULL OR p_gender NOT IN ('male', 'female', 'nonbinary') THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_gender' AS code, 'Bitte ein Geschlecht angeben.' AS message;
    LEAVE proc_main;
  END IF;

  -- The portal is for adults. Checked here rather than in the website so that the
  -- rule cannot be skipped by calling the procedure directly.
  IF p_date_of_birth IS NULL THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_date_of_birth' AS code, 'Bitte ein Geburtsdatum angeben.' AS message;
    LEAVE proc_main;
  END IF;

  IF p_date_of_birth > (CURDATE() - INTERVAL 18 YEAR)
     OR p_date_of_birth < '1900-01-01' THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_date_of_birth' AS code,
           'Für einen Charakter muss man am Tag der Registrierung volljährig sein.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Resolve the account. This is the whole reason the procedure exists: the
  -- website passes a Discord ID because that is what it has, and the UUID link to
  -- the account never crosses the privilege boundary.
  -- -------------------------------------------------------------------------

  SELECT a.id INTO v_account_id
    FROM accounts a
   WHERE a.discord_id = p_discord_id
     AND a.status = 'active'
     AND NOT EXISTS (
       SELECT 1 FROM bans b
        WHERE b.discord_id = a.discord_id
          AND b.revoked_at IS NULL
          AND (b.expires_at IS NULL OR b.expires_at > NOW())
     )
   LIMIT 1;

  IF v_account_id IS NULL THEN
    SELECT 0 AS ok, NULL AS character_id, 'no_account' AS code,
           'Dazu wurde kein freigegebenes Konto gefunden.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- One character per account (ADR-0008). uq_characters_account enforces it too;
  -- this check exists to turn a constraint violation into a sentence.
  -- -------------------------------------------------------------------------

  SELECT COUNT(*) INTO v_exists
    FROM characters c
   WHERE c.account_id = v_account_id;

  IF v_exists > 0 THEN
    SELECT 0 AS ok, NULL AS character_id, 'already_has_character' AS code,
           'Für dieses Konto existiert bereits ein Charakter.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Is the name free?
  --
  -- Checked here AND enforced by uq_characters_name (migration 020). The index is
  -- the guarantee; this SELECT is what turns a race into a readable message for
  -- the one player who lost it.
  --
  -- The comparison deliberately uses the same normalisation the generated
  -- name_key column uses — TRIM, and a case- and accent-insensitive collation —
  -- so that "MAX", "max" and "Max " are one name here exactly as they are one
  -- name to the index. Comparing raw first_name/last_name instead would let the
  -- check pass and the INSERT fail, which is the worst of both.
  -- -------------------------------------------------------------------------

  SELECT COUNT(*) INTO v_exists
    FROM characters c
   WHERE CONCAT(TRIM(c.first_name), '|', TRIM(COALESCE(c.last_name, '')))
       = CONCAT(p_first_name, '|', COALESCE(p_last_name, ''));

  IF v_exists > 0 THEN
    SELECT 0 AS ok, NULL AS character_id, 'name_taken' AS code,
           'Dieser Name ist bereits vergeben. Bitte einen anderen wählen.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Allocate the permanent phone number (ADR-0021, ADR-0018).
  -- -------------------------------------------------------------------------

  SELECT COALESCE(value, '555-') INTO v_prefix
    FROM settings WHERE `key` = 'phone.number.prefix' LIMIT 1;

  SELECT COALESCE(value, '4') INTO v_digits
    FROM settings WHERE `key` = 'phone.number.digits' LIMIT 1;

  SET v_digits = LEAST(8, GREATEST(4, v_digits));

  WHILE v_number IS NULL AND v_attempts < 25 DO
    SET v_attempts = v_attempts + 1;

    SET v_suffix = LPAD(FLOOR(RAND() * POW(10, v_digits)), v_digits, '0');
    SET v_candidate = CONCAT(v_prefix, v_suffix);

    SELECT COUNT(*) INTO v_exists
      FROM phone_accounts p
     WHERE p.number = v_candidate;

    IF v_exists = 0 THEN
      SET v_number = v_candidate;
    END IF;
  END WHILE;

  IF v_number IS NULL THEN
    SELECT 0 AS ok, NULL AS character_id, 'no_number_available' AS code,
           'Es ist gerade keine Telefonnummer frei. Bitte später erneut versuchen.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Insert. Both rows, one transaction.
  --
  -- UUID() is version 1, not 4. The codebase mints v4 in Lua because two rapid
  -- calls once collided (see LEARNINGS.md), but this is a single server-side call
  -- in a stored procedure — there is no second generator racing it, so the version
  -- bit does not matter here. Uniqueness does, and UUID() guarantees it.
  --
  -- `appearance` is left NULL on purpose: that is the signal the game server reads
  -- to open the character creator. The character exists from this moment and is
  -- finished in game, or not at all.
  -- -------------------------------------------------------------------------

  SET v_character_id = UUID();

  INSERT INTO characters (
    id, account_id, first_name, last_name, gender, date_of_birth, birthplace,
    appearance, spawn_point
  ) VALUES (
    v_character_id, v_account_id, p_first_name, p_last_name, p_gender,
    p_date_of_birth, NULLIF(TRIM(p_birthplace), ''), NULL, 'default'
  );

  INSERT INTO phone_accounts (character_id, number, is_active)
  VALUES (v_character_id, v_number, 1);

  -- -------------------------------------------------------------------------
  -- The wallet.
  --
  -- `Identity.createCharacter` wrote the character row AND its wallet in one
  -- transaction, with the comment "a character without a wallet is an unplayable
  -- state". That comment was never enforced by the schema - `wallets.character_id`
  -- is nullable and nothing requires the row to exist - so it was enforced by the
  -- only code path that made characters. Moving character creation to the website
  -- removed that path, and every character created since would have entered the
  -- world with no wallet at all: `Economy.get` returns nil, `Economy:push` sends
  -- nothing, and the player has no money and no error explaining why.
  --
  -- The starting amounts come from `settings`, the same two keys the Lua path used,
  -- so tuning them stays a data change (ADR-0009). GREATEST(..., 0) because
  -- `chk_wallet_cash_non_negative` would otherwise turn a mistyped setting into a
  -- procedure that fails for everybody instead of one that starts at zero.
  --
  -- NOT written here: the starting inventory. That is the item catalogue's business
  -- (ADR-0018), it lives in Lua, and the game server grants it idempotently when
  -- the character enters the world.
  -- -------------------------------------------------------------------------

  SET v_cash = COALESCE((
    SELECT CAST(COALESCE(`value`, '0.00') AS DECIMAL(14,2))
      FROM settings WHERE `key` = 'economy.starting.cash' LIMIT 1), 0.00);

  SET v_bank = COALESCE((
    SELECT CAST(COALESCE(`value`, '0.00') AS DECIMAL(14,2))
      FROM settings WHERE `key` = 'economy.starting.bank' LIMIT 1), 0.00);

  INSERT INTO wallets (character_id, cash, bank)
  VALUES (v_character_id, GREATEST(v_cash, 0.00), GREATEST(v_bank, 0.00));

  SELECT 1 AS ok, v_character_id AS character_id, 'ok' AS code,
         'Charakter angelegt.' AS message;
END//

DELIMITER ;

-- ---------------------------------------------------------------------------
-- Grants: EXECUTE only. No INSERT, no UPDATE, no DELETE, on any table here.
--
-- Apply these by hand as admin, alongside the rest of grants.sql — the file is
-- documentation as much as it is a script, and this section is the one that
-- describes what the website may do from now on.
--
--   GRANT EXECUTE ON PROCEDURE nifty_life.create_character_from_web
--     TO 'nifty_website'@'localhost';
--
-- Verification, to run after applying:
--   CALL create_character_from_web('0', 'Test', 'User', 'male', '1990-01-01', 'X');
--     -> ok=0, code='no_account'
--   INSERT INTO characters (...) VALUES (...);
--     -> denied: still no grant, exactly as grants.sql line 244 claims
--   UPDATE characters SET first_name='X' WHERE id='...';
--     -> denied: no UPDATE anywhere
--   SELECT * FROM create_character_from_web;
--     -> denied: not a table
-- ---------------------------------------------------------------------------
-- --------------------------------------------------------------------------
-- 022_portal_username.sql
-- --------------------------------------------------------------------------
-- 022_portal_username.sql
--
-- A display name chosen at registration, separate from the email.
--
-- The portal needs SOMETHING to show in the navbar and the account header
-- other than the email, because the email is private and the Discord
-- username is only present once Discord is linked. This column is the
-- always-present display name.
--
-- NULL for existing rows: the column is added now, and legacy accounts
-- registered before this migration did not pick a username. New rows
-- are written by the website's INSERT and carry a value from the
-- registration form.

ALTER TABLE portal_users
  ADD COLUMN username VARCHAR(32) NULL AFTER email;

-- --------------------------------------------------------------------------
-- 023_add_character_position.sql
-- --------------------------------------------------------------------------
-- Per-character last-known world position. JSON `{x, y, z}` written by
-- nifty-world on every nifty:server:saveCharacter (autosave, disconnect,
-- explicit). Read by the same module on enterWorld: if non-null, the player
-- resumes there and the picker is skipped. Null means "first time after the
-- creator" and the picker opens.
ALTER TABLE characters
  ADD COLUMN position JSON NULL AFTER appearance;
-- --------------------------------------------------------------------------
-- 024_remove_bounty_hunter.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 024_remove_bounty_hunter.sql
-- Nifty Life 2.0 — drop the bounty hunter job
--
-- Bounty hunter was added in migration 005 (jobs_and_property_seed) as a
-- placeholder civilian job. It is not part of the roster the owner wanted
-- to ship - the roster is police, ems, taxi, mechanic, trucker, tow, fire -
-- and the only reason it existed was that 005 inserted the four jobs 003 had
-- already seeded (police/ems/taxi/mechanic) plus a handful of extras, and
-- bounty was one of those extras.
--
-- 005 has been edited to drop the INSERT lines for 'bounty' and for the
-- 'job.wage_per_hour.bounty' setting, so a FRESH install (where 005 is run
-- for the first time) will never have a bounty hunter. This migration handles
-- the EXISTING install case: any database that already ran 005 has the
-- bounty row and the wage setting, and we want them gone.
--
-- character_jobs entries pointing at 'bounty' are deleted too. A character
-- who joined bounty before this migration simply falls back to having no
-- job, which is the same outcome as if the job had never existed - the
-- character_jobs table is a list of which jobs a character has signed up
-- for, not a list of which jobs exist, so a row pointing at a non-existent
-- job is meaningless and harmless to remove.
-- ============================================================================

DELETE FROM job_defs         WHERE code = 'bounty';
DELETE FROM settings         WHERE `key` = 'job.wage_per_hour.bounty';
DELETE FROM character_jobs   WHERE job_code = 'bounty';

-- --------------------------------------------------------------------------
-- 025_character_clothing.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 025_character_clothing.sql
-- Nifty Life 2.0 — per-character ownership of clothing pieces
--
-- WHY THIS TABLE
--
-- Before this migration, a character's clothing was one JSON blob on
-- `characters.appearance` with no per-piece identity. That made the creator
-- (pick an outfit once) and the hood toggle (swap one variant of a single top)
-- work, but it stopped matching the moment we wanted:
--
--   * a wardrobe UI that re-equips anything the character owns, for free
--   * clothing stores that hide pieces the character already owns
--   * creator picks to be persisted as a set of individual owned pieces,
--     not as one anonymous outfit
--
-- This table is the per-piece ownership list. `characters.appearance` keeps
-- its role: it stores the CURRENTLY-EQUIPPED loadout, exactly as it does
-- today, and the world's `applyAppearance` reads it unchanged.
--
-- SHAPE
--
-- One row per owned piece. The natural key is
-- (character_id, kind, slot_id, collection, drawable, texture): two
-- characters owning the same shirt each get their own row, and the same
-- character owning the same shirt twice is the same row (PRIMARY KEY dedupes).
--
-- `kind` distinguishes components from props at the schema layer because
-- their slot-id ranges overlap in places and the validation logic does not.
--
-- `source` is for audit only: 'creator' for the first-time outfit,
-- 'purchase' for buys from a clothing store, 'seed' for the migration.
-- No gameplay decision in V1 reads from it.
--
-- `ON DELETE CASCADE` mirrors `characters` (ADR-0001): a row that owns
-- rows must die with its owner.
--
-- Backfill of existing characters is handled in Lua at server boot
-- (nifty-core/server/clothing.lua), not in this file. SQL UNNEST over
-- JSON objects is awkward and version-fragile across MariaDB minors;
-- a Lua pass over `characters.appearance` reuses the same JSON library
-- the rest of the project already uses and writes through `Owned.grant`,
-- so the INSERT and the running code share one path.
-- ============================================================================

CREATE TABLE IF NOT EXISTS character_clothing (
  character_id  CHAR(36)        NOT NULL,
  kind          ENUM('component','prop') NOT NULL,
  slot_id       TINYINT UNSIGNED NOT NULL,
  collection    VARCHAR(64)     NOT NULL,
  drawable      INT UNSIGNED    NOT NULL,
  texture       INT UNSIGNED    NOT NULL,
  source        ENUM('creator','purchase','seed') NOT NULL DEFAULT 'seed',
  acquired_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (character_id, kind, slot_id, collection, drawable, texture),
  KEY ix_character_clothing_character (character_id),
  CONSTRAINT fk_character_clothing_character
    FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- 026_character_outfits.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 026_character_outfits.sql
-- Nifty Life 2.0 — saved outfits per character
--
-- WHY THIS TABLE
--
-- The wardrobe re-equips pieces, but a player also wants named presets
-- ("Alltag", "Dienst", "Schwarz") so they can switch whole looks with one
-- pick. Outfits are a NAMED list of (kind, slot_id, collection, drawable,
-- texture) tuples the character has already owned. They reference the owned
-- pieces; they do not duplicate them. An outfit whose pieces the character
-- does not own cannot be applied — apply re-validates before writing.
--
-- SHAPE
--
-- Two tables. `character_outfits` is the named root (one row per outfit).
-- `character_outfit_pieces` is the body (one row per slot filled in the
-- outfit), keyed by (outfit_id, kind, slot_id) so each slot has at most one
-- piece in an outfit. The natural key is the same one Owned.has uses, so
-- an outfit save can re-use the check by name.
--
-- `applied_at` is just the last time the player picked this outfit at the
-- wardrobe. Not used for any rule in V1; recorded because "what did I last
-- wear before the meeting" is a question the audit log might one day answer.
--
-- UNIQUE (character_id, name) prevents two outfits with the same name on one
-- character. Rename / overwrite handles the "the user already had 'Dienst'"
-- case, which is what they almost certainly want.
--
-- `ON DELETE CASCADE` mirrors characters: an outfit dies with its owner.
-- pieces cascades from outfits.
-- ============================================================================

CREATE TABLE IF NOT EXISTS character_outfits (
  id           CHAR(36)        NOT NULL,
  character_id CHAR(36)        NOT NULL,
  name         VARCHAR(64)     NOT NULL,
  created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  applied_at   DATETIME        NULL,
  PRIMARY KEY (id),
  KEY ix_character_outfits_character (character_id),
  UNIQUE KEY uq_character_outfits_character_name (character_id, name),
  CONSTRAINT fk_character_outfits_character
    FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS character_outfit_pieces (
  outfit_id    CHAR(36)        NOT NULL,
  kind         ENUM('component','prop') NOT NULL,
  slot_id      TINYINT UNSIGNED NOT NULL,
  collection   VARCHAR(64)     NOT NULL,
  drawable     INT UNSIGNED    NOT NULL,
  texture      INT UNSIGNED    NOT NULL,
  PRIMARY KEY (outfit_id, kind, slot_id),
  CONSTRAINT fk_character_outfit_pieces_outfit
    FOREIGN KEY (outfit_id) REFERENCES character_outfits (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- 027_clothing_prices.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 027_clothing_prices.sql
-- Nifty Life 2.0 — per-(drawable, texture) clothing prices in the database
--
-- WHY THIS TABLE
--
-- The Lua `prices.lua` ships curated defaults. They are the floor: any piece
-- the catalogue knows about has SOME price, even on a fresh database. The
-- trade-off is that the file has to be edited and the resource reloaded for
-- any pricing change.
--
-- This table is for everything that comes AFTER the floor. Staff sets a row
-- for a specific (kind, slot_id, collection, drawable, texture) tuple and
-- that price is used the next time a player opens the wardrobe or the
-- store. Fabvariations get their own rows: drawing 4 in fabric 2 can be a
-- different price from drawing 4 in fabric 0.
--
-- The combination is the natural key, which mirrors Owned's ownership shape:
-- one row per (variant, fabric) and you cannot accidentally book the same
-- variant at two prices.
--
-- `name` carries the localized label so staff can read what they are
-- pricing. The Lua fallback files do not have a "no row exists" mode -
-- every drawable is in the table; only the `price` column is empty until
-- staff sets it.
--
-- `updated_at` is the last touch; useful for "what did pricing change this
-- week" reports. No gameplay code reads it.
-- ============================================================================

CREATE TABLE IF NOT EXISTS clothing_prices (
  kind        ENUM('component','prop') NOT NULL,
  slot_id     TINYINT UNSIGNED NOT NULL,
  collection  VARCHAR(64)     NOT NULL,
  drawable    INT UNSIGNED    NOT NULL,
  texture     INT UNSIGNED    NOT NULL,
  name        VARCHAR(128)    NOT NULL,
  price       INT UNSIGNED    NULL,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (kind, slot_id, collection, drawable, texture),
  KEY ix_clothing_prices_collection (kind, slot_id, collection)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed: just two pricing rows so a brand new DB has something that proves
-- the chain end-to-end. The full catalogue is filled by the boot-time scan
-- in nifty-core/server/clothing.lua's Price.scanCatalogue(), which reads
-- the JSON data files from nifty-creator and inserts one row per
-- (slot_id, drawable, texture) with the localized name and a NULL price.
-- Staff then sets the price column on the rows they want to sell.
INSERT IGNORE INTO clothing_prices (kind, slot_id, collection, drawable, texture, name, price)
VALUES
  ('component', 11, '', 0, 0, 'Crew T-Shirt', 500),
  ('prop',       0, '', 0, 0, 'White Cap',   200);

-- --------------------------------------------------------------------------
-- 028_clothing_outfit_item.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 028_clothing_outfit_item.sql
-- Nifty Life 2.0 — clothing_outfit item definition
--
-- WHY
--
-- Outfits (migration 026's `character_outfits` table) are named loadouts.
-- The user wants players to *pack* an outfit into the inventory, hold it
-- like any other stackable item, and *use* it from there to apply. That
-- requires an item definition the inventory accepts.
--
-- `clothing_outfit` is one code per outfit-as-an-item. Its metadata is the
-- outfit_id (a CHAR(36) referencing character_outfits.id on a specific
-- character). The item exists separately from the outfit row: deleting
-- the row breaks the item, but holding the item does not delete the row.
-- This matches phone/id_card whose data lives on the character's row, not
-- in the inventory.
--
-- Stackable, max 10 - lets the player keep a small set of favourite
-- outfits on hand without filling a slot each. Weight 0.05: an outfit
-- is invisible in your pocket.
--
-- `metadata_schema` documents the shape so future inventory UIs can
-- render outfit items correctly without hardcoding knowledge here.
-- ============================================================================

INSERT INTO item_defs
  (code, name, category, weight, stackable, max_stack, is_weapon, metadata_schema)
VALUES
  ('clothing_outfit', 'Outfit', 'clothing', 0.050, 1, 10, 0,
   JSON_OBJECT(
     'type', 'object',
     'required', JSON_ARRAY('outfit_id'),
     'properties', JSON_OBJECT(
       'outfit_id', JSON_OBJECT('type', 'string', 'description', 'character_outfits.id')
     )
   ))
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  category = VALUES(category),
  weight = VALUES(weight),
  stackable = VALUES(stackable),
  max_stack = VALUES(max_stack),
  metadata_schema = VALUES(metadata_schema);

-- --------------------------------------------------------------------------
-- 029_clothing_accessory_items.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 029_clothing_accessory_items.sql
-- Nifty Life 2.0 — per-piece accessory item definitions
--
-- WHY
--
-- The wardrobe's "Anziehen" for masks, glasses, watches, rings, hats, etc.
-- is supposed to also create an inventory item the player carries. The
-- item exists for the lifetime of the wear — auto-created on equip, NOT
-- removed by the wardrobe's "Ablegen" (the item stays in the bag), and
-- only disappears via an explicit drop / give.
--
-- Each of these has max_stack=1 and stackable=0 so two copies of "the same
-- hat in the same colour" never coexist. Different fabrics live as
-- different items via metadata (collection, drawable, texture). A
-- Clothing-wardrobe key in the item_defs.metadata_schema flags what
-- metadata is carried.
--
-- slot -> code mapping (driven by the free-mode slot list):
--   component 1      -> clothing_mask
--   prop     0       -> clothing_hat
--   prop     1       -> clothing_glasses
--   prop     2       -> clothing_earring
--   prop     6       -> clothing_ring       (Schmuck / bracelet)
--   prop     7       -> clothing_watch
--
-- Halsketten (necklace) is not a free-mode slot - the game lacks a stand-
-- alone necklace anchor on the male/female ped model. Skipped on purpose
-- rather than mapped to a wrong slot.
-- ============================================================================

INSERT INTO item_defs
  (code, name, category, weight, stackable, max_stack, is_weapon, metadata_schema)
VALUES
  ('clothing_mask',     'Maske',         'clothing', 0.050, 0, 1, 0,
   JSON_OBJECT(
     'type', 'object',
     'required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'),
     'properties', JSON_OBJECT(
       'kind', JSON_OBJECT('type', 'string', 'enum', JSON_ARRAY('component','prop')),
       'slot_id', JSON_OBJECT('type', 'integer'),
       'collection', JSON_OBJECT('type', 'string'),
       'drawable', JSON_OBJECT('type', 'integer'),
       'texture', JSON_OBJECT('type', 'integer')
     ))),
  ('clothing_hat',      'Kopfbedeckung', 'clothing', 0.100, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_glasses',  'Brille',        'clothing', 0.050, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_earring',  'Ohrring',       'clothing', 0.020, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_ring',     'Ring',          'clothing', 0.020, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_watch',    'Uhr',           'clothing', 0.100, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture')))
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  category = VALUES(category),
  weight = VALUES(weight),
  stackable = VALUES(stackable),
  max_stack = VALUES(max_stack),
  metadata_schema = VALUES(metadata_schema);

-- --------------------------------------------------------------------------
-- 030_clothing_acquired_from.sql
-- --------------------------------------------------------------------------
-- ============================================================================
-- 030_clothing_acquired_from.sql
-- Nifty Life 2.0 — provenance column on character_clothing
--
-- WHY
--
-- A character receives a clothing item from another character (trade, drop
-- etc.) and saves it into their own wardrobe. The owned piece is theirs
-- forever, but its name carries the giver so the wardrobe UI can label it
-- "T-Shirt #4 (von Max)" - a record of where the piece came from.
--
-- `acquired_from` is a free-form display string (the giver's character
-- name, e.g. "Max Mustermann"). It is not a foreign key: the giver's
-- character row may be deleted, renamed, or never linked to the items we
-- hold. The column reads on display and would just become "(von einem
-- Spieler)" or similar if cleaned up - a future migration can drop the
-- column, the wardrobe can detect NULL and hide the suffix.
--
-- Existing rows get NULL; the wardrobe renders "(von X)" only when the
-- column has a value.
-- ============================================================================

ALTER TABLE character_clothing
  ADD COLUMN acquired_from VARCHAR(128) NULL AFTER source;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- Schema-Lauf abgeschlossen. Nächste Schritte:
--   1. User-Accounts anlegen:    mysql -u root -p < database/grants.sql
--   2. mariadn-Verify laufen:    powershell database/verify.ps1
-- ============================================================================
