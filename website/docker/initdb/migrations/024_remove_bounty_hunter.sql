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
