-- Per-character last-known world position. JSON `{x, y, z}` written by
-- nifty-world on every nifty:server:saveCharacter (autosave, disconnect,
-- explicit). Read by the same module on enterWorld: if non-null, the player
-- resumes there and the picker is skipped. Null means "first time after the
-- creator" and the picker opens.
ALTER TABLE characters
  ADD COLUMN position JSON NULL AFTER appearance;