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