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