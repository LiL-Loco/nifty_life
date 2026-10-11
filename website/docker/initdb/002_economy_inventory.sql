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