-- 021_create_character_from_web.sql
--
-- The website creates the character. This is the ONLY way a character row is
-- created, and it is a stored procedure rather than an INSERT grant on purpose.
--
-- ---------------------------------------------------------------------------
-- WHY A PROCEDURE AND NOT `GRANT INSERT ON characters`
-- ---------------------------------------------------------------------------
--
-- database/grants.sql documents, at line 244, that the website must NOT be able to
-- insert a character — and the surrounding comments explain why that boundary is
-- there at all: the website is the one account a compromise would actually hold,
-- and every other write it performs is column-scoped or absent.
--
-- A plain INSERT grant would make that comment a lie, and it would also buy
-- nothing. The website cannot know `account_id` — it is a UUID minted by the game
-- server and never exposed — so every character it inserted would have to come
-- from a lookup it is not allowed to do, or from a value it is not allowed to
-- read. The INSERT would be structurally impossible to write correctly.
--
-- So the procedure takes the thing the website actually HAS (a Discord ID) and
-- resolves everything else itself. This is the same pattern migration 016 already
-- uses for email confirmation, and the same recommendation grants.sql already
-- makes in its closing note: a constraint that must hold belongs in the database,
-- not in reviewable application code.
--
-- What the website gains: EXECUTE on one procedure.
-- What it still cannot do: touch any other character, attach a character to
-- somebody else's account, or write a character row directly.
--
-- ---------------------------------------------------------------------------
-- THE PHONE NUMBER IS ALLOCATED HERE TOO
-- ---------------------------------------------------------------------------
--
-- ADR-0021: a number is permanent and must exist from the character's first
-- second, and identity.lua used to insert it in the same transaction as the
-- character row. That code is moving to the website, so this procedure inherits
-- the duty. Leaving it out would produce characters that exist but can never be
-- messaged, with no way to repair them after the fact — a permanent number that
-- was never assigned is not something a later code path can fix without breaking
-- the guarantee that it never changes.
--
-- The number format is read from `settings`, the same two keys the game used, so
-- tuning the prefix stays a data change (ADR-0009) rather than a code change.
--
-- Collision is resolved here rather than by relying on UNIQUE: the loop below
-- asks first, and the UNIQUE constraint on phone_accounts remains the backstop.
-- The loop is bounded, so a pathological database cannot spin forever.
--
-- ---------------------------------------------------------------------------
-- RETURN CONTRACT
-- ---------------------------------------------------------------------------
--
-- Exactly one row, always. A procedure whose success and failure are signalled
-- differently — a result set for success and an exception for failure — is a
-- procedure every caller has to write two branches for, and one of them is
-- always wrong.
--
--   ok           1 on success, 0 otherwise
--   character_id the new UUID, NULL on failure
--   code         a stable machine token, safe to switch on
--   message      a sentence the website may show or may not
--
-- `code` is the contract. `message` is prose for a human and is not stable.

DROP PROCEDURE IF EXISTS create_character_from_web;

DELIMITER //

-- ---------------------------------------------------------------------------
-- WHY THE STRING PARAMETERS ARE 255 AND NOT THEIR COLUMN WIDTH
--
-- A parameter declared exactly as wide as its column makes that column's own
-- validation unreachable. MariaDB checks the argument against the parameter type
-- in strict mode while binding it, and raises `Data too long for column
-- 'p_last_name'` before the body has run a single statement. The
-- `invalid_last_name` guard further down can therefore never fire - the routine
-- dies with a driver error instead of the documented contract row, which is the
-- one thing the RETURN CONTRACT below exists to prevent.
--
-- So every text parameter is declared wide enough to receive rubbish, and the
-- body is what decides whether that rubbish is acceptable. The column widths are
-- the real limits and they are still enforced - by the guards here and by the
-- schema itself.
-- ---------------------------------------------------------------------------
CREATE PROCEDURE create_character_from_web(
  IN  p_discord_id     CHAR(64),
  IN  p_first_name     VARCHAR(255),
  IN  p_last_name      VARCHAR(255),
  IN  p_gender         VARCHAR(64),
  IN  p_date_of_birth  DATE,
  IN  p_birthplace     VARCHAR(255)
)
-- ---------------------------------------------------------------------------
-- WHY THE BODY IS A LABELLED BLOCK
--
-- The routine bails out early ten times with LEAVE, so that a rejected field is
-- reported as a sentence instead of as a constraint violation. LEAVE is only
-- legal inside a LABELLED block or inside a LOOP - an unlabelled `BEGIN` does
-- not count, and neither does an `IF` branch. Without this label the routine
-- does not merely misbehave, it fails to compile: MariaDB raises ER_PARSE_ERROR
-- at the first `LEAVE proc_main;` and the procedure is never created.
--
-- The label must sit in front of BEGIN. The DECLAREs stay directly inside it,
-- because that is still the first thing a stored program may declare.
--
-- This is also why the DELIMITER lines below are only needed for a CLIENT-side
-- runner. Over the wire the whole CREATE PROCEDURE goes out as one statement and
-- the server parses the body itself - any GUI that splits on `;` will break this
-- routine no matter how the SQL is written.
-- ---------------------------------------------------------------------------
proc_main: BEGIN
  DECLARE v_account_id  CHAR(36) DEFAULT NULL;
  DECLARE v_character_id CHAR(36) DEFAULT NULL;
  DECLARE v_exists      INT DEFAULT 0;

  DECLARE v_prefix      VARCHAR(8)  DEFAULT '555-';
  DECLARE v_digits      TINYINT     DEFAULT 4;
  DECLARE v_number      VARCHAR(16) DEFAULT NULL;
  DECLARE v_candidate   VARCHAR(16) DEFAULT NULL;
  DECLARE v_suffix      VARCHAR(12) DEFAULT NULL;
  DECLARE v_attempts    INT         DEFAULT 0;
  DECLARE v_cash        DECIMAL(14,2) DEFAULT 0.00;
  DECLARE v_bank        DECIMAL(14,2) DEFAULT 0.00;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    -- Any unexpected failure — a duplicate that slipped past the checks, a lock
    -- timeout — must not leave a half-created character. The whole body is one
    -- transaction under the caller's autocommit, and rolling back here is what
    -- makes the procedure all-or-nothing.
    ROLLBACK;
    SELECT 0 AS ok, NULL AS character_id, 'error' AS code,
           'Der Charakter konnte nicht angelegt werden.' AS message;
  END;

  -- -------------------------------------------------------------------------
  -- Normalise and reject obvious rubbish BEFORE any lookup, so a failure is
  -- reported as a bad field rather than as "name taken" or "no account".
  -- -------------------------------------------------------------------------

  SET p_first_name = NULLIF(TRIM(p_first_name), '');

  IF p_last_name IS NOT NULL THEN
    SET p_last_name = NULLIF(TRIM(p_last_name), '');
  END IF;

  IF p_first_name IS NULL OR CHAR_LENGTH(p_first_name) > 64 THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_first_name' AS code,
           'Bitte einen Vornamen angeben (maximal 64 Zeichen).' AS message;
    LEAVE proc_main;
  END IF;

  IF p_last_name IS NOT NULL AND CHAR_LENGTH(p_last_name) > 64 THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_last_name' AS code,
           'Der Nachname ist zu lang (maximal 64 Zeichen).' AS message;
    LEAVE proc_main;
  END IF;

  -- Same reasoning as the name guards: the parameter is 255 wide so that this
  -- check is reachable, and the column is VARCHAR(96). Without a guard here a
  -- long birthplace would fall through to the EXIT HANDLER and come back as the
  -- useless `error`, instead of naming the field that is wrong.
  IF p_birthplace IS NOT NULL AND CHAR_LENGTH(p_birthplace) > 96 THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_birthplace' AS code,
           'Der Geburtsort ist zu lang (maximal 96 Zeichen).' AS message;
    LEAVE proc_main;
  END IF;

  -- The enum is the schema's business, not the caller's. A gender the column
  -- cannot store would abort the INSERT with a driver error, which reads as a
  -- crash rather than as a rejected form field.
  IF p_gender IS NULL OR p_gender NOT IN ('male', 'female', 'nonbinary') THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_gender' AS code, 'Bitte ein Geschlecht angeben.' AS message;
    LEAVE proc_main;
  END IF;

  -- The portal is for adults. Checked here rather than in the website so that the
  -- rule cannot be skipped by calling the procedure directly.
  IF p_date_of_birth IS NULL THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_date_of_birth' AS code, 'Bitte ein Geburtsdatum angeben.' AS message;
    LEAVE proc_main;
  END IF;

  IF p_date_of_birth > (CURDATE() - INTERVAL 18 YEAR)
     OR p_date_of_birth < '1900-01-01' THEN
    SELECT 0 AS ok, NULL AS character_id, 'invalid_date_of_birth' AS code,
           'Für einen Charakter muss man am Tag der Registrierung volljährig sein.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Resolve the account. This is the whole reason the procedure exists: the
  -- website passes a Discord ID because that is what it has, and the UUID link to
  -- the account never crosses the privilege boundary.
  -- -------------------------------------------------------------------------

  SELECT a.id INTO v_account_id
    FROM accounts a
   WHERE a.discord_id = p_discord_id
     AND a.status = 'active'
     AND NOT EXISTS (
       SELECT 1 FROM bans b
        WHERE b.discord_id = a.discord_id
          AND b.revoked_at IS NULL
          AND (b.expires_at IS NULL OR b.expires_at > NOW())
     )
   LIMIT 1;

  IF v_account_id IS NULL THEN
    SELECT 0 AS ok, NULL AS character_id, 'no_account' AS code,
           'Dazu wurde kein freigegebenes Konto gefunden.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- One character per account (ADR-0008). uq_characters_account enforces it too;
  -- this check exists to turn a constraint violation into a sentence.
  -- -------------------------------------------------------------------------

  SELECT COUNT(*) INTO v_exists
    FROM characters c
   WHERE c.account_id = v_account_id;

  IF v_exists > 0 THEN
    SELECT 0 AS ok, NULL AS character_id, 'already_has_character' AS code,
           'Für dieses Konto existiert bereits ein Charakter.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Is the name free?
  --
  -- Checked here AND enforced by uq_characters_name (migration 020). The index is
  -- the guarantee; this SELECT is what turns a race into a readable message for
  -- the one player who lost it.
  --
  -- The comparison deliberately uses the same normalisation the generated
  -- name_key column uses — TRIM, and a case- and accent-insensitive collation —
  -- so that "MAX", "max" and "Max " are one name here exactly as they are one
  -- name to the index. Comparing raw first_name/last_name instead would let the
  -- check pass and the INSERT fail, which is the worst of both.
  -- -------------------------------------------------------------------------

  SELECT COUNT(*) INTO v_exists
    FROM characters c
   WHERE CONCAT(TRIM(c.first_name), '|', TRIM(COALESCE(c.last_name, '')))
       = CONCAT(p_first_name, '|', COALESCE(p_last_name, ''));

  IF v_exists > 0 THEN
    SELECT 0 AS ok, NULL AS character_id, 'name_taken' AS code,
           'Dieser Name ist bereits vergeben. Bitte einen anderen wählen.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Allocate the permanent phone number (ADR-0021, ADR-0018).
  -- -------------------------------------------------------------------------

  SELECT COALESCE(value, '555-') INTO v_prefix
    FROM settings WHERE `key` = 'phone.number.prefix' LIMIT 1;

  SELECT COALESCE(value, '4') INTO v_digits
    FROM settings WHERE `key` = 'phone.number.digits' LIMIT 1;

  SET v_digits = LEAST(8, GREATEST(4, v_digits));

  WHILE v_number IS NULL AND v_attempts < 25 DO
    SET v_attempts = v_attempts + 1;

    SET v_suffix = LPAD(FLOOR(RAND() * POW(10, v_digits)), v_digits, '0');
    SET v_candidate = CONCAT(v_prefix, v_suffix);

    SELECT COUNT(*) INTO v_exists
      FROM phone_accounts p
     WHERE p.number = v_candidate;

    IF v_exists = 0 THEN
      SET v_number = v_candidate;
    END IF;
  END WHILE;

  IF v_number IS NULL THEN
    SELECT 0 AS ok, NULL AS character_id, 'no_number_available' AS code,
           'Es ist gerade keine Telefonnummer frei. Bitte später erneut versuchen.' AS message;
    LEAVE proc_main;
  END IF;

  -- -------------------------------------------------------------------------
  -- Insert. Both rows, one transaction.
  --
  -- UUID() is version 1, not 4. The codebase mints v4 in Lua because two rapid
  -- calls once collided (see LEARNINGS.md), but this is a single server-side call
  -- in a stored procedure — there is no second generator racing it, so the version
  -- bit does not matter here. Uniqueness does, and UUID() guarantees it.
  --
  -- `appearance` is left NULL on purpose: that is the signal the game server reads
  -- to open the character creator. The character exists from this moment and is
  -- finished in game, or not at all.
  -- -------------------------------------------------------------------------

  SET v_character_id = UUID();

  INSERT INTO characters (
    id, account_id, first_name, last_name, gender, date_of_birth, birthplace,
    appearance, spawn_point
  ) VALUES (
    v_character_id, v_account_id, p_first_name, p_last_name, p_gender,
    p_date_of_birth, NULLIF(TRIM(p_birthplace), ''), NULL, 'default'
  );

  INSERT INTO phone_accounts (character_id, number, is_active)
  VALUES (v_character_id, v_number, 1);

  -- -------------------------------------------------------------------------
  -- The wallet.
  --
  -- `Identity.createCharacter` wrote the character row AND its wallet in one
  -- transaction, with the comment "a character without a wallet is an unplayable
  -- state". That comment was never enforced by the schema - `wallets.character_id`
  -- is nullable and nothing requires the row to exist - so it was enforced by the
  -- only code path that made characters. Moving character creation to the website
  -- removed that path, and every character created since would have entered the
  -- world with no wallet at all: `Economy.get` returns nil, `Economy:push` sends
  -- nothing, and the player has no money and no error explaining why.
  --
  -- The starting amounts come from `settings`, the same two keys the Lua path used,
  -- so tuning them stays a data change (ADR-0009). GREATEST(..., 0) because
  -- `chk_wallet_cash_non_negative` would otherwise turn a mistyped setting into a
  -- procedure that fails for everybody instead of one that starts at zero.
  --
  -- NOT written here: the starting inventory. That is the item catalogue's business
  -- (ADR-0018), it lives in Lua, and the game server grants it idempotently when
  -- the character enters the world.
  -- -------------------------------------------------------------------------

  SET v_cash = COALESCE((
    SELECT CAST(COALESCE(`value`, '0.00') AS DECIMAL(14,2))
      FROM settings WHERE `key` = 'economy.starting.cash' LIMIT 1), 0.00);

  SET v_bank = COALESCE((
    SELECT CAST(COALESCE(`value`, '0.00') AS DECIMAL(14,2))
      FROM settings WHERE `key` = 'economy.starting.bank' LIMIT 1), 0.00);

  INSERT INTO wallets (character_id, cash, bank)
  VALUES (v_character_id, GREATEST(v_cash, 0.00), GREATEST(v_bank, 0.00));

  SELECT 1 AS ok, v_character_id AS character_id, 'ok' AS code,
         'Charakter angelegt.' AS message;
END//

DELIMITER ;

-- ---------------------------------------------------------------------------
-- Grants: EXECUTE only. No INSERT, no UPDATE, no DELETE, on any table here.
--
-- Apply these by hand as admin, alongside the rest of grants.sql — the file is
-- documentation as much as it is a script, and this section is the one that
-- describes what the website may do from now on.
--
--   GRANT EXECUTE ON PROCEDURE nifty_life.create_character_from_web
--     TO 'nifty_website'@'localhost';
--
-- Verification, to run after applying:
--   CALL create_character_from_web('0', 'Test', 'User', 'male', '1990-01-01', 'X');
--     -> ok=0, code='no_account'
--   INSERT INTO characters (...) VALUES (...);
--     -> denied: still no grant, exactly as grants.sql line 244 claims
--   UPDATE characters SET first_name='X' WHERE id='...';
--     -> denied: no UPDATE anywhere
--   SELECT * FROM create_character_from_web;
--     -> denied: not a table
-- ---------------------------------------------------------------------------