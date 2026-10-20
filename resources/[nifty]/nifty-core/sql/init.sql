






















CREATE DATABASE IF NOT EXISTS nifty_life
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE nifty_life;

SET FOREIGN_KEY_CHECKS = 0;














CREATE TABLE IF NOT EXISTS schema_migrations (
  version     VARCHAR(64)  NOT NULL,
  applied_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;





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

INSERT IGNORE INTO settings (`key`, value, value_type, category, description) VALUES
  
  
  ('economy.stuetze.amount',          '250.00', 'decimal', 'economy', 'Stütze payout. Must stay below subsistence cost.'),
  ('economy.stuetze.interval_sec',    '900',    'int',     'economy', 'Seconds between Stütze payouts (15 min).'),
  ('economy.starting.cash',           '500.00', 'decimal', 'economy', 'Starting cash for a new character.'),
  ('economy.starting.bank',           '0.00',   'decimal', 'economy', 'Starting bank balance for a new character.'),

  
  
  ('economy.sink.apartment_rent',     '750.00', 'decimal', 'economy', 'Monthly rent, entry tier.'),
  ('economy.sink.house_rent',         '2500.00','decimal', 'economy', 'Monthly rent, premium tier.'),
  ('economy.sink.vehicle_fuel_unit',  '2.50',   'decimal', 'economy', 'Cost per unit of fuel.'),
  ('economy.sink.vehicle_insurance',  '150.00', 'decimal', 'economy', 'Vehicle insurance period cost.'),

  
  ('server.window.opening',           'fri 19:00', 'string', 'server', 'Window opens.'),
  ('server.window.closing',           'sun 22:00', 'string', 'server', 'Window closes.') ON DUPLICATE KEY UPDATE `key` = `key`;

























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




INSERT INTO job_defs (code, name, kind, is_emergency) VALUES
  ('police',  'Los Santos Police Department', 'department', 1),
  ('ems',     'Pillbox Medical',               'department', 1),
  ('taxi',    'Taxi Driver',                  'civilian',   0),
  ('mechanic','Mechanic',                     'civilian',   0)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);





























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
  
  
  
  CONSTRAINT fk_ledger_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE RESTRICT,
  CONSTRAINT chk_ledger_balance_non_negative CHECK (balance_after >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;









DROP TRIGGER IF EXISTS trg_ledger_no_update;
CREATE TRIGGER trg_ledger_no_update BEFORE UPDATE ON ledger FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ledger rows are immutable';

DROP TRIGGER IF EXISTS trg_ledger_no_delete;
CREATE TRIGGER trg_ledger_no_delete BEFORE DELETE ON ledger FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ledger rows are permanent';








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




INSERT IGNORE INTO settings (`key`, value, value_type, category, description) VALUES
  
  
  ('economy.price.phone',              '650.00', 'decimal', 'economy', 'Replacement handset (ADR-0018).'),
  ('economy.price.phone_sim',          '50.00',  'decimal', 'economy', 'SIM to activate a handset.'),

  
  
  ('economy.stuetze.max_per_session',  '8',      'int',     'economy', 'Ceiling on Stütze payouts per session.'),

  
  ('inventory.default_slots',         '24',     'int',     'inventory', 'Starting inventory slots.'),
  ('inventory.max_weight',            '50.000', 'decimal', 'inventory', 'Carry weight limit.') ON DUPLICATE KEY UPDATE `key` = `key`;


































INSERT INTO job_defs (code, name, kind, is_emergency, base_x, base_y, base_z) VALUES
  ('police',   'Los Santos Police Department', 'department', 1, 454.96, -1017.38, 28.38),
  ('ems',      'Pillbox Medical',               'department', 1, 309.06, -595.66, 43.26),
  ('taxi',     'Taxi Driver',                  'civilian',   0, -809.18, -1018.88, 26.40),
  ('mechanic', 'Mechanic',                     'civilian',   0, -338.87, -135.35, 39.03),
  ('trucker',  'LKW-Fahrer',                   'civilian',   0, -1150.53, 1789.02, 78.77),
  ('tow',      'Abschleppdienst',              'civilian',   0, 826.31, -1223.50, 41.51),
  ('fire',     'Feuerwehr',                    'department', 1, 1191.55, -1614.21, 34.86)
ON DUPLICATE KEY UPDATE
  
  
  `base_x` = VALUES(`base_x`),
  `base_y` = VALUES(`base_y`),
  `base_z` = VALUES(`base_z`);











INSERT IGNORE INTO settings (`key`, value, value_type, category, description) VALUES
  
  
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
















INSERT IGNORE INTO settings (`key`, value, value_type, category, description) VALUES
  ('economy.price.bread',       '12.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.water',       '8.00',  'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.coffee',      '15.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.bandage',     '40.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.painkillers', '35.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.lockpick',    '90.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).'),
  ('economy.price.screwdriver', '25.00', 'decimal', 'economy', 'Placeholder shop price (ADR-0009).')
ON DUPLICATE KEY UPDATE `key` = `key`;































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
  
  
  KEY ix_messages_recipient (recipient_id, sent_at),
  KEY ix_messages_sender (sender_id, sent_at),
  CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_messages_recipient FOREIGN KEY (recipient_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT chk_messages_not_self CHECK (sender_id <> recipient_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;












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





INSERT IGNORE INTO settings (`key`, value, value_type, category, description) VALUES
  ('phone.number.prefix',        '555-',  'string',  'phone', 'Prefix for server-assigned numbers (ADR-0021).'),
  ('phone.number.digits',        '4',     'int',     'phone', 'Random digits per number.'),
  ('phone.message.max_length',   '1000',  'int',     'phone', 'Hard cap on a message body; the column agrees.')
ON DUPLICATE KEY UPDATE `key` = `key`;






























































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

    
    
    
    
    
    
    UNION ALL SELECT 'dt-arcadius-rich',     'Arcadius - Executive Rich', 'Downtown', 'entry', 'ex_dt1_02_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-cool',     'Arcadius - Cool',           'Downtown', 'entry', 'ex_dt1_02_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-contrast', 'Arcadius - Contrast',       'Downtown', 'entry', 'ex_dt1_02_office_02a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-warm',     'Arcadius - Old Spice Warm', 'Downtown', 'entry', 'ex_dt1_01_office_01a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-classical','Arcadius - Classical',      'Downtown', 'entry', 'ex_dt1_01_office_01b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-arcadius-vintage',  'Arcadius - Vintage',        'Downtown', 'entry', 'ex_dt1_01_office_01c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-rich',     'Maze Bank Tower - Executive Rich', 'Downtown', 'entry', 'ex_dt1_11_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-cool',     'Maze Bank Tower - Cool',           'Downtown', 'entry', 'ex_dt1_11_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dt-mazebank-contrast', 'Maze Bank Tower - Contrast',       'Downtown', 'entry', 'ex_dt1_11_office_02a', NULL, NULL, NULL, 6, 1

    
    
    
    UNION ALL SELECT 'dp-lom-rich',          'Lom Bank - Executive Rich',      'Del Perro', 'entry', 'ex_sm_13_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-lom-cool',          'Lom Bank - Cool',                'Del Perro', 'entry', 'ex_sm_13_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-lom-contrast',      'Lom Bank - Contrast',            'Del Perro', 'entry', 'ex_sm_13_office_02a', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-rich',    'Maze Bank West - Executive Rich', 'Del Perro', 'entry', 'ex_sm_15_office_02b', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-cool',    'Maze Bank West - Cool',           'Del Perro', 'entry', 'ex_sm_15_office_02c', NULL, NULL, NULL, 6, 1
    UNION ALL SELECT 'dp-mazebankw-contrast','Maze Bank West - Contrast',       'Del Perro', 'entry', 'ex_sm_15_office_02a', NULL, NULL, NULL, 6, 1

    
    
    
    
    
    UNION ALL SELECT 'vinewood-michael', 'Michael''s House', 'Vinewood / Richman', 'standard', NULL, -85.00, -785.00, NULL, 10, 1
    UNION ALL SELECT 'nconker-2044', '2044 North Conker Avenue', 'Vinewood / Richman', 'standard', NULL, 340.94, 437.18, 149.39, 10, 0
    UNION ALL SELECT 'nconker-2045', '2045 North Conker Avenue', 'Vinewood / Richman', 'standard', NULL, 373.02, 416.11, 145.70, 10, 0
    UNION ALL SELECT 'madwayne-2133', '2133 Mad Wayne Thunder Drive', 'Vinewood / Richman', 'standard', NULL, -1288.00, 440.75, 97.69, 10, 0

    
    
    
    
    
    
    UNION ALL SELECT 'whispymound-3671', '3671 Whispymound Drive', 'Vinewood Hills', 'premium', NULL, -169.29, 486.49, 137.44, 15, 1
    UNION ALL SELECT 'wildoats-3655',   '3655 Wild Oats Drive',   'Vinewood Hills', 'premium', NULL, -169.29, 486.49, 137.44, 15, 0

    
    
    
    
    UNION ALL SELECT 'hillcrest-2862', '2862 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -676.13, 588.61, 145.17, 25, 0
    UNION ALL SELECT 'hillcrest-2868', '2868 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -763.11, 615.91, 144.14, 25, 0
    UNION ALL SELECT 'hillcrest-2874', '2874 Hillcrest Avenue', 'Rockford Hills', 'luxury', NULL, -857.80, 682.56, 152.65, 25, 0

    
    
    
    UNION ALL SELECT 'davis-aunt',        'Franklin''s Aunt House', 'Davis', 'standard', NULL, -67.00, -809.00, NULL, 10, 1
    UNION ALL SELECT 'davis-whispymound-2677', '2677 Whispymound Drive', 'Davis', 'standard', NULL, 120.50, 549.95, 184.10, 10, 0

    
    
    
    
    
    
    
    
    
    
    UNION ALL SELECT 'outskirts-trailer',  'Trevor''s Trailer',        'Outskirts', 'standard', NULL, 1975.55, 3820.54, 33.45, 10, 1
    UNION ALL SELECT 'outskirts-motel',    'The Motor Motel',          'Outskirts', 'standard', NULL, 152.26, -1004.47, -99.00, 10, 1
    UNION ALL SELECT 'outskirts-floyd',    'Floyd''s Apartment',       'Outskirts', 'standard', NULL, NULL, NULL, NULL, 10, 0
    UNION ALL SELECT 'outskirts-molina',   'Harvey Molina''s Apartment', 'Outskirts', 'standard', NULL, NULL, NULL, NULL, 10, 0
    UNION ALL SELECT 'outskirts-madrazos', 'Madrazos Ranch',           'Outskirts', 'outlier',  NULL, 1399.00, 1150.00, 115.00, 8, 0
    UNION ALL SELECT 'outskirts-oneil',    'O''Neil Ranch',            'Outskirts', 'outlier',  'farm', 2469.03, 4955.28, 45.12, 8, 1
    UNION ALL SELECT 'outskirts-casino',   'Diamond Casino Penthouse', 'Outskirts', 'luxury',   'vw_casino_penthouse', 976.64, 70.30, 115.16, 25, 1
    UNION ALL SELECT 'outskirts-lester',   'Lester''s House',          'Outskirts', 'standard', NULL, 1273.90, -1719.31, 54.77, 10, 1

    
    
    
    
    
    
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









CREATE TABLE IF NOT EXISTS web_link_requests (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  discord_id  VARCHAR(32)  NOT NULL,
  code        VARCHAR(16)  NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_web_link_requests_discord (discord_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;








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
















ALTER TABLE characters ADD COLUMN IF NOT EXISTS is_staff TINYINT(1) NOT NULL DEFAULT 0;




INSERT IGNORE INTO settings (`key`, value, value_type, category, description) VALUES
  ('peeper.post.max_length',    '280', 'int',     'social',   'Maximum characters in a Peeper post or reply.'),
  ('peeper.feed.page_size',     '25',  'int',     'social',   'Default page size for the feed.'),
  ('peeper.pairing.ttl_minutes','15',  'int',     'social',   'Lifetime of a web pairing code (ADR-0022).')
ON DUPLICATE KEY UPDATE `key` = `key`;












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
  
  
  
  
  
  CONSTRAINT fk_peeper_report_reporter FOREIGN KEY (reporter)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_peeper_report_post FOREIGN KEY (post_id)
    REFERENCES peeper_posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


























ALTER TABLE applications
  DROP INDEX IF EXISTS ix_applications_discord,
  ADD UNIQUE KEY IF NOT EXISTS uq_applications_discord (discord_id);






















































CREATE TABLE IF NOT EXISTS staff (
  discord_id VARCHAR(32) NOT NULL,
  role_id    VARCHAR(32) NOT NULL,
  synced_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (discord_id),
  KEY ix_staff_role (role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;






















ALTER TABLE applications
  ADD COLUMN IF NOT EXISTS reviewed_by_discord_id VARCHAR(32) NULL;

ALTER TABLE applications
  DROP COLUMN IF EXISTS reviewed_by;










































ALTER TABLE peeper_posts
  MODIFY author_character CHAR(36) NULL,
  MODIFY source ENUM('game','web','staff') NOT NULL DEFAULT 'game',
  ADD COLUMN IF NOT EXISTS author_discord_id VARCHAR(32) NULL AFTER author_character,
  ADD COLUMN IF NOT EXISTS deleted_by_discord_id VARCHAR(32) NULL AFTER deleted_by,
  ADD KEY IF NOT EXISTS ix_peeper_author_discord (author_discord_id, created_at),
  ADD CONSTRAINT IF NOT EXISTS chk_peeper_author CHECK (
    (author_character IS NULL) <> (author_discord_id IS NULL)
  );












































ALTER TABLE peeper_likes
  DROP PRIMARY KEY,
  ADD COLUMN IF NOT EXISTS id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT FIRST,
  MODIFY COLUMN character_id CHAR(36) NULL,
  ADD COLUMN IF NOT EXISTS author_discord_id VARCHAR(32) NULL AFTER character_id,
  ADD COLUMN IF NOT EXISTS actor VARCHAR(32) NULL,
  ADD PRIMARY KEY (id),
  ADD UNIQUE KEY IF NOT EXISTS uq_peeper_likes_actor (post_id, actor),
  ADD KEY IF NOT EXISTS ix_peeper_likes_discord (author_discord_id);



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









ALTER TABLE peeper_reports
  MODIFY COLUMN reporter CHAR(36) NULL,
  ADD COLUMN IF NOT EXISTS reporter_discord_id VARCHAR(32) NULL AFTER reporter,
  ADD KEY IF NOT EXISTS ix_peeper_reports_reporter_discord (reporter_discord_id),
  ADD CONSTRAINT IF NOT EXISTS chk_peeper_reporter CHECK (
    (reporter IS NULL) <> (reporter_discord_id IS NULL)
  );































ALTER TABLE peeper_posts
  ADD CONSTRAINT IF NOT EXISTS chk_peeper_staff_authorship CHECK (
    source <> 'staff'
    OR (author_discord_id IS NOT NULL AND author_character IS NULL)
  );







ALTER TABLE peeper_likes
  ADD CONSTRAINT IF NOT EXISTS chk_peeper_likes_staff_author CHECK (
    author_discord_id IS NULL OR character_id IS NULL
  );











































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


















ALTER TABLE applications
  ADD COLUMN IF NOT EXISTS user_id CHAR(36) NULL AFTER id;

ALTER TABLE applications
  ADD UNIQUE KEY IF NOT EXISTS uq_applications_user (user_id);



































DROP PROCEDURE IF EXISTS confirm_portal_email;

DELIMITER //

CREATE PROCEDURE confirm_portal_email(IN p_token_hash CHAR(64))
BEGIN
  DECLARE v_user_id CHAR(36) DEFAULT NULL;

  
  
  
  
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
    
    
    UPDATE portal_users
       SET email_verified_at = NOW()
     WHERE id = v_user_id
       AND email_verified_at IS NULL;
  END IF;

  SELECT v_user_id AS confirmed_user_id;
END//

GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email TO 'nifty_website'@'%';

DELIMITER ;



































DROP PROCEDURE IF EXISTS confirm_portal_email;

DELIMITER //

CREATE PROCEDURE confirm_portal_email(IN p_token_hash CHAR(64))
BEGIN
  DECLARE v_user_id CHAR(36) DEFAULT NULL;
  DECLARE v_claimed INT DEFAULT 0;

  
  
  UPDATE portal_email_tokens
     SET used_at = NOW()
   WHERE token_hash = p_token_hash
     AND purpose = 'verify_email'
     AND used_at IS NULL
     AND expires_at > NOW();

  
  
  
  
  SET v_claimed = ROW_COUNT();

  IF v_claimed = 0 THEN
    SELECT NULL AS confirmed_user_id;
  ELSE
    SELECT user_id INTO v_user_id
      FROM portal_email_tokens
     WHERE token_hash = p_token_hash
     LIMIT 1;

    
    
    
    
    UPDATE portal_users
       SET email_verified_at = NOW()
     WHERE id = v_user_id
       AND email_verified_at IS NULL;

    SELECT v_user_id AS confirmed_user_id;
  END IF;
END//

GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email TO 'nifty_website'@'%';

DELIMITER ;






















































INSERT IGNORE INTO settings (`key`, value, value_type, category, description) VALUES
  
  
  
  ('chat.radius',              '40',   'int',     'chat', 'Hearing radius in metres. Server-side OneSync distance check.'),

  
  
  
  
  ('chat.cooldown_ms',         '1200', 'int',     'chat', 'Minimum milliseconds between two messages from one player.'),

  
  
  
  ('chat.max_length',          '150',  'int',     'chat', 'Maximum characters in one chat message.'),

  
  
  
  ('chat.history',             '200',  'int',     'chat', 'Reserved: retained chat lines. Not read by the client yet.');




























































ALTER TABLE characters
  ADD COLUMN IF NOT EXISTS birthplace VARCHAR(96) NULL AFTER gender;




ALTER TABLE characters
  DROP INDEX IF EXISTS ix_characters_name;

ALTER TABLE characters
  ADD COLUMN IF NOT EXISTS name_key VARCHAR(161)
    GENERATED ALWAYS AS (
      CONCAT(TRIM(first_name), '|', TRIM(COALESCE(last_name, '')))
    ) STORED
    COMMENT 'Normalised name key. UNIQUE on this is what makes a name unclaimable.';







ALTER TABLE characters
  ADD UNIQUE KEY IF NOT EXISTS uq_characters_name (name_key);

















































































DROP PROCEDURE IF EXISTS create_character_from_web;

DELIMITER //

















CREATE PROCEDURE create_character_from_web(
  IN  p_discord_id     CHAR(64),
  IN  p_first_name     VARCHAR(255),
  IN  p_last_name      VARCHAR(255),
  IN  p_gender         VARCHAR(64),
  IN  p_date_of_birth  DATE,
  IN  p_birthplace     VARCHAR(255)
)


















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
    
    
    
    
    ROLLBACK;
    SELECT 0 AS ok, NULL AS character_id, 'error' AS code,
           'Der Charakter konnte nicht angelegt werden.' AS message;
  END;

  
  
  
  

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

  
  
  
  
  IF p_birthplace IS NOT NULL AND CHAR_LENGTH(p_birthplace) > 96 THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_birthplace' AS code,
           'Der Geburtsort ist zu lang (maximal 96 Zeichen).' AS message;
    LEAVE proc_main;
  END IF;

  
  
  
  IF p_gender IS NULL OR p_gender NOT IN ('male', 'female', 'nonbinary') THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_gender' AS code, 'Bitte ein Geschlecht angeben.' AS message;
    LEAVE proc_main;
  END IF;

  
  
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

  
  
  
  

  SELECT COUNT(*) INTO v_exists
    FROM characters c
   WHERE c.account_id = v_account_id;

  IF v_exists > 0 THEN
    SELECT 0 AS ok, NULL AS character_id, 'already_has_character' AS code,
           'Für dieses Konto existiert bereits ein Charakter.' AS message;
    LEAVE proc_main;
  END IF;

  
  
  
  
  
  
  
  
  
  
  
  
  

  SELECT COUNT(*) INTO v_exists
    FROM characters c
   WHERE CONCAT(TRIM(c.first_name), '|', TRIM(COALESCE(c.last_name, '')))
       = CONCAT(p_first_name, '|', COALESCE(p_last_name, ''));

  IF v_exists > 0 THEN
    SELECT 0 AS ok, NULL AS character_id, 'name_taken' AS code,
           'Dieser Name ist bereits vergeben. Bitte einen anderen wählen.' AS message;
    LEAVE proc_main;
  END IF;

  
  
  

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

GRANT EXECUTE ON PROCEDURE nifty_life.create_character_from_web TO 'nifty_website'@'%';

DELIMITER ;






































ALTER TABLE portal_users
  ADD COLUMN IF NOT EXISTS username VARCHAR(32) NULL AFTER email;









ALTER TABLE characters
  ADD COLUMN IF NOT EXISTS position JSON NULL AFTER appearance;
















































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







INSERT IGNORE INTO clothing_prices (kind, slot_id, collection, drawable, texture, name, price)
VALUES
  ('component', 11, '', 0, 0, 'Crew T-Shirt', 500),
  ('prop',       0, '', 0, 0, 'White Cap',   200);






























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


























ALTER TABLE character_clothing
  ADD COLUMN IF NOT EXISTS acquired_from VARCHAR(128) NULL AFTER source;

SET FOREIGN_KEY_CHECKS = 1;






