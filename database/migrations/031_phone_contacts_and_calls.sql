-- ============================================================================
-- 031_phone_contacts_and_calls.sql
-- Nifty Life 2.0 — the two tables the phone was missing
--
-- WHY
--
-- ADR-0018, -0020, -0021 and -0022 were written before any of it ran, and three
-- of the four are already in the database: create_character_from_web assigns a
-- permanent `555-XXXX` number (ADR-0021), phone_messages carries the history,
-- phone_reports carries moderation. What never existed is the RESOURCE, and
-- building it surfaced two tables that the schema was missing rather than
-- tables that the design had overlooked.
--
-- CONTACTS
--
-- Contacts are explicit, not derived from who you happened to message. The
-- schema had phone_messages but nothing that could answer "who is in my phone
-- book" — which is a different question from "who have I written to", and the
-- difference is the whole point of a contacts list: a name YOU chose, for a
-- person, that you can revise.
--
-- The alias is per-direction. Two characters can each hold the other under
-- whatever name they like, and neither choice is visible to the other. Storing
-- one shared label would force a single truth about what somebody is called,
-- which is exactly the thing two players disagree about most often.
--
-- The UNIQUE on (owner_id, contact_id) makes "save this person" idempotent:
-- saving twice edits the alias instead of creating a second row.
--
-- CALLS
--
-- A call has to be a ROW and not a pair of booleans on two players. "Ringing"
-- is the state where a call is neither answered nor ended, and every way of
-- modelling that with flags on the participants has the same bug: the state
-- survives the process that created it. Two disconnect callbacks that do not
-- run, or one that never fires, leave two players ringing each other with no
-- way to hang up. A row with an end_reason that is NULL means ringing and
-- nothing else, and "is this call still live" is one indexed query.
--
-- end_reason is an ENUM rather than a free string because the set of ways a
-- call ends is closed and the UI branches on it. It has to distinguish
-- 'declined' from 'missed' — a declined call is a social act, a missed one is
-- not, and the call log renders them differently.
--
-- The voice transport is NOT in this schema. ADR-0020 puts calls on temporary
-- Teamspeak channels, which is a channel id and a pair of moves, not a column.
-- It arrives as a separate migration once the query credentials exist, and this
-- table is shaped so that adding it needs no column here.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Contacts
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS phone_contacts (
  owner_id   CHAR(36)      NOT NULL,
  contact_id CHAR(36)      NOT NULL,
  -- The name THIS owner gave this person. NULL means "never renamed", which
  -- renders as the character's own name rather than as an empty string — an
  -- empty alias is not the same claim as no alias.
  alias      VARCHAR(64)   NULL,
  created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  updated_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP() ON UPDATE CURRENT_TIMESTAMP(),

  PRIMARY KEY (`owner_id`, `contact_id`),
  -- Reverse lookup, for "who has my number saved". Cheap, and the only way to
  -- answer that without scanning every contact list on the server.
  KEY `ix_contacts_contact` (`contact_id`),
  KEY `ix_contacts_alias`  (`owner_id`, `alias`),

  CONSTRAINT `fk_contacts_owner`
    FOREIGN KEY (`owner_id`)   REFERENCES characters (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_contacts_contact`
    FOREIGN KEY (`contact_id`) REFERENCES characters (`id`) ON DELETE CASCADE,
  -- A contact list containing yourself is a bug in the client, not a state the
  -- database should store.
  CONSTRAINT `chk_contacts_not_self` CHECK (`owner_id` <> `contact_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Calls
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS phone_calls (
  id          CHAR(36)      NOT NULL,
  caller_id   CHAR(36)      NOT NULL,
  callee_id   CHAR(36)      NOT NULL,
  started_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  -- Set once the callee accepts. NULL before that.
  answered_at DATETIME      NULL,
  ended_at    DATETIME      NULL,
  -- NULL while the call is live (ringing or in progress). Every other value is
  -- terminal, which is what makes "is this still live" a single `IS NULL`.
  end_reason  ENUM('answered', 'declined', 'missed', 'busy', 'cancelled', 'unavailable')
              NULL DEFAULT NULL,
  -- Where the voice went, once ADR-0020 is implemented. Nullable and unused
  -- today, and deliberately so: a column that is always NULL is a claim the
  -- schema does not yet make.
  voice_ref   VARCHAR(128)  NULL,

  PRIMARY KEY (`id`),
  -- The two access paths, both "everything with this person, newest first".
  KEY `ix_calls_caller` (`caller_id`, `started_at`),
  KEY `ix_calls_callee` (`callee_id`, `started_at`),
  -- The live-call lookup. Partial index: it is tiny by construction, because a
  -- row is in it exactly while the call has no end_reason.
  KEY `ix_calls_live_caller` (`caller_id`, `end_reason`),
  KEY `ix_calls_live_callee` (`callee_id`, `end_reason`),

  CONSTRAINT `fk_calls_caller`
    FOREIGN KEY (`caller_id`) REFERENCES characters (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_calls_callee`
    FOREIGN KEY (`callee_id`) REFERENCES characters (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_calls_not_self`   CHECK (`caller_id` <> `callee_id`),
  -- A call that ended cannot have gone unanswered, and one that was answered
  -- cannot have no timestamp. The database catches the states the client is
  -- supposed to make impossible.
  CONSTRAINT `chk_calls_end_shape` CHECK (
    (  end_reason IS NULL                             AND ended_at IS NULL AND answered_at IS NULL)
    OR (end_reason IN ('answered', 'declined')        AND ended_at IS NOT NULL)
    OR (end_reason IN ('missed','busy','cancelled','unavailable')
                                                     AND ended_at IS NOT NULL AND answered_at IS NULL)
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- NOT APPLIED HERE — read this before assuming the phone is ready
--
-- These tables exist so the resource has somewhere to write. Nothing writes to
-- them until nifty-phone ships.
--
-- What is already in place, verified against the live schema rather than
-- assumed: `accounts.teamspeak_uid` EXISTS, so ADR-0020's one hard dependency is
-- satisfied — the column that maps a Teamspeak account to a FiveM player is
-- there. What is missing there is the CONTENT: no account has it filled, because
-- nothing has ever collected it.
--
-- So a call can be placed, answered and ended as soon as the resource ships, and
-- will carry no voice until the linking step exists. That is a deliberate split:
-- `voice_ref` is NULL, the column is nullable, and wiring the transport in is an
-- adapter rather than a migration.
-- ============================================================================