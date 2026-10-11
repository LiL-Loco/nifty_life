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