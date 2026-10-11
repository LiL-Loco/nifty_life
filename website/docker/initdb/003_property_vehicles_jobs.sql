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