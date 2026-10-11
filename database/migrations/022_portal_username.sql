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
