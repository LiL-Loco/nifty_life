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