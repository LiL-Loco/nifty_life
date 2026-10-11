-- 019_chat_settings.sql
--
-- Tunables for the in-game chat, which replaces the downloaded `chat` resource.
--
-- WHY A MIGRATION. ADR-0009 puts every tunable in `settings` so tuning is a data
-- change rather than a code change, and `GetSetting` warns loudly about a key that
-- is missing rather than falling back silently. A radius that only existed in
-- `sv_chat.lua` would be untunable without a code change and a resource restart,
-- which is the failure mode ADR-0009 was written to prevent.
--
-- These four are the SERVER-authoritative values. Two presentation values are not
-- here on purpose: `chat.log_lines` and `chat.fade_ms` never reach the server, so
-- putting them in a table the server owns would be a second source of truth for a
-- number only the browser ever reads. They live in `ui/app.js` with a comment
-- saying so.
--
-- `chat.radius` is the load-bearing one. A weekend whitelist server is not a
-- shooter: hearing somebody two kilometres away is not a feature, and it makes
-- every scene in the game a public channel.

INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  -- How far away a character can be and still be heard. OneSync is required
  -- (`/server:4500` in the nifty-core manifest) because this is a server-side
  -- distance check, not a client-side guess.
  ('chat.radius',              '40',   'int',     'chat', 'Hearing radius in metres. Server-side OneSync distance check.'),

  -- Minimum gap between two messages from one player. This is the spam guard and
  -- it is the reason the server is allowed to broadcast without a per-player
  -- bucket: 1200 ms keeps a conversation readable and caps one client at roughly
  -- 50 messages a minute.
  ('chat.cooldown_ms',         '1200', 'int',     'chat', 'Minimum milliseconds between two messages from one player.'),

  -- Hard ceiling on one message, enforced on the server. The client field is
  -- `maxlength="150"` for the typist's benefit and is not a rule: a client that
  -- lies here gets truncated, not rejected.
  ('chat.max_length',          '150',  'int',     'chat', 'Maximum characters in one chat message.'),

  -- Kept so an operator can widen the chat later without a code change. Deliberately
  -- generous: the anti-spam ceiling for a whitelist server is "annoying", and the
  -- cost of being slightly too strict is a confused player, not a security hole.
  ('chat.history',             '200',  'int',     'chat', 'Reserved: retained chat lines. Not read by the client yet.');