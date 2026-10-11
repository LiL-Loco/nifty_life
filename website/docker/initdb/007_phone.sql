-- ============================================================================
-- 007_phone.sql
-- Nifty Life 2.0 — phone accounts, numbers, message history
--
-- Invariants encoded here:
--   ADR-0018  The handset is an ordinary inventory item. The ACCOUNT — number,
--             messages, social — belongs to the character. Two characters can
--             hold two handsets and it changes nothing, because the phone is the
--             thing that matters and the thing is not the thing you carry.
--   ADR-0021  Numbers are server-assigned and permanent. UNIQUE is the backstop,
--             not the mechanism.
--   ADR-0004  Message history is permanent, exactly like money and property.
--
-- ON DELETION: a phone account is CASCADEd from the character. This is the one
-- place where losing history is accepted, because it only happens if someone
-- deletes a character, which the game offers no path to do. The alternative —
-- RESTRICT — would make character deletion impossible for the same reason it
-- does for the ledger, and that is a defensible position too; it is recorded
-- here rather than silently chosen.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- phone_accounts — one per character, created with the character.
--
-- `number` is public (ADR-0021): it appears in contacts and profiles, and it is
-- therefore part of what social content exposes. It is NOT a secret and must not
-- be treated as one.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_accounts (
  character_id  CHAR(36)      NOT NULL,
  number        VARCHAR(16)   NOT NULL,
  is_active     TINYINT(1)    NOT NULL DEFAULT 1,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (character_id),
  UNIQUE KEY uq_phone_accounts_number (number),
  CONSTRAINT fk_phone_account_character FOREIGN KEY (character_id)
    REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- phone_messages — permanent history.
--
-- Routing is by CHARACTER, not by number. ADR-0021 guarantees the number never
-- changes, so routing by number would also be stable — but routing by the
-- character is what the foreign keys can actually enforce, and an orphaned
-- message that nobody can be shown is worse than one that lost a number.
--
-- Deletion is per-recipient and per-sender (`cleared_by_*`). Deleting a message
-- is a private act: it hides it from you, and it does not reach into the other
-- person's inbox. Only staff can remove content outright (ADR-0019).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_messages (
  id                 CHAR(36)      NOT NULL,
  sender_id          CHAR(36)      NOT NULL,
  recipient_id       CHAR(36)      NOT NULL,
  body               VARCHAR(1000) NOT NULL,
  sent_at            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  read_at            DATETIME      NULL,
  cleared_by_sender  TINYINT(1)    NOT NULL DEFAULT 0,
  cleared_by_recipient TINYINT(1)  NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  -- The inbox query is "everything for me, newest first", so the index leads
  -- with the recipient.
  KEY ix_messages_recipient (recipient_id, sent_at),
  KEY ix_messages_sender (sender_id, sent_at),
  CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_messages_recipient FOREIGN KEY (recipient_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT chk_messages_not_self CHECK (sender_id <> recipient_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- phone_reports — moderation queue.
--
-- ADR-0019: players report, staff decide, and staff are the only ones who can
-- delete. This table is the handoff between those two halves; without it the
-- report button has nowhere to put anything.
--
-- The reporter is recorded so that abuse of the report button is itself
-- visible, and the target is recorded twice on purpose: the CHARACTER id (which
-- is what staff act on) and the MESSAGE id (which is what gets removed).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_reports (
  id             CHAR(36)      NOT NULL,
  reporter_id    CHAR(36)      NOT NULL,
  reported_char  CHAR(36)      NOT NULL,
  message_id     CHAR(36)      NULL,
  reason         VARCHAR(64)   NOT NULL,
  status         ENUM('open','actioned','dismissed') NOT NULL DEFAULT 'open',
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at    DATETIME      NULL,
  PRIMARY KEY (id),
  KEY ix_reports_status (status, created_at),
  KEY ix_reports_target (reported_char),
  CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_reports_target FOREIGN KEY (reported_char)
    REFERENCES characters (id) ON DELETE CASCADE,
  CONSTRAINT fk_reports_message FOREIGN KEY (message_id)
    REFERENCES phone_messages (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Number format. Placeholders (ADR-0021 says area coding can come later at no
-- structural cost, because this is the only thing that decides a number).
-- ---------------------------------------------------------------------------
INSERT INTO settings (`key`, value, value_type, category, description) VALUES
  ('phone.number.prefix',        '555-',  'string',  'phone', 'Prefix for server-assigned numbers (ADR-0021).'),
  ('phone.number.digits',        '4',     'int',     'phone', 'Random digits per number.'),
  ('phone.message.max_length',   '1000',  'int',     'phone', 'Hard cap on a message body; the column agrees.')
ON DUPLICATE KEY UPDATE `key` = `key`;