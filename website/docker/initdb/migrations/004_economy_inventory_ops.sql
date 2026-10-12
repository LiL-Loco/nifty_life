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