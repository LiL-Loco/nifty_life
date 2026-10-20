--[[
  The phone account: the number, and the two ways of getting from a number to a
  character and back.

  WHY THIS FILE DOES NOT ASSIGN NUMBERS

  ADR-0021 says a character gets a permanent number at creation, and that is
  already true — `create_character_from_web` in
  database/migrations/021_create_character_from_web.sql generates `555-XXXX`
  inside a bounded collision loop and inserts into phone_accounts before the
  transaction commits. Number assignment therefore lives in SQL, next to the
  INSERT that creates the character it belongs to, and this file only reads.

  That is worth stating plainly because the obvious alternative — "the phone
  resource assigns a number the first time somebody uses it" — is one line and
  wrong. It makes the number a property of using the phone rather than of being
  a character, so a character who never opens it has no number, and the one who
  does has a number that depends on when they got round to it. A number is an
  address; an address that materialises on first use is not an address.
]]

local Db = Nifty.Db

local RESOURCE = GetCurrentResourceName()

Phone = Phone or {}

-- ---------------------------------------------------------------------------
-- The account
-- ---------------------------------------------------------------------------

--- The caller's own account, or nil with a reason.
---
--- Returns two values deliberately: every caller here has to decide what to tell
--- the player when it is nil, and a bare nil makes that an implicit nil-check
--- three lines later that then has no message to send.
--- @return table|nil, string|nil
function Phone.accountFor(characterId)
  if type(characterId) ~= 'string' or characterId == '' then
    return nil, 'no character'
  end

  local row = Db.one([[
    SELECT pa.character_id, pa.number, pa.is_active, pa.created_at,
           c.first_name, c.last_name
      FROM phone_accounts pa
      JOIN characters c ON c.id = pa.character_id
     WHERE pa.character_id = ?
  ]], { characterId }, 'phone:accountFor')

  if not row then
    -- A character without a phone_accounts row can only predate the procedure, or
    -- come from somewhere that bypassed it. It is worth a loud line rather than a
    -- silent "no phone": this is the case where a player says their number is
    -- missing and there would otherwise be nothing in the log to look at.
    print(('[%s] character %s has no phone_accounts row — created outside create_character_from_web?'):format(
      RESOURCE, characterId))
    return nil, 'no phone account'
  end

  return {
    number    = row.number,
    -- `is_active` is the flag the account was suspended (staff action), NOT
    -- whether the character is holding a handset. Those are two different
    -- questions and conflating them is how a character with a working phone in
    -- their pocket ends up told they have no account.
    active    = row.is_active == 1,
    firstName = row.first_name,
    lastName  = row.last_name,
  }
end

-- ---------------------------------------------------------------------------
-- Number <-> character
-- ---------------------------------------------------------------------------

--- Who owns this number?
--- @return string|nil characterId, table|nil row
function Phone.characterByNumber(number)
  if type(number) ~= 'string' or number == '' then return nil end

  local row = Db.one([[
    SELECT pa.character_id, pa.is_active, c.first_name, c.last_name
      FROM phone_accounts pa
      JOIN characters c ON c.id = pa.character_id
     WHERE pa.number = ?
  ]], { number }, 'phone:characterByNumber')

  if not row then return nil end
  return row.character_id, row
end

--- How a character is labelled when no contact alias applies.
---
--- This is the FALLBACK, not the label the panel shows. A contact the owner has
--- renamed is shown under that alias; this is only used for a number that has no
--- contact row, and for the call screen where showing the character's own name is
--- exactly right — you know who is ringing you before you look it up.
--- @return string
function Phone.displayName(characterId)
  local row = Db.one(
    'SELECT first_name, last_name FROM characters WHERE id = ?',
    { characterId }, 'phone:displayName')

  if not row then return 'Unbekannt' end
  return ('%s %s'):format(row.first_name or '?', row.last_name or '?')
end

--- Normalise what a player typed on the keypad into a stored number.
---
--- The stored form is `555-1234` (ADR-0021: four digits, `555` prefix). A player
--- typing `5551234`, `(555) 1234` or `555 1234` all mean the same person, and the
--- database stores one spelling because `uq_phone_accounts_number` is a UNIQUE
--- string comparison — `5551234` and `555-1234` would be two different accounts.
---
--- This has to be server-side. A client-side normaliser is a client that can be
--- told not to, and the unique constraint would then be enforcing nothing.
--- @return string|nil number, string|nil err
function Phone.normalise(input)
  if type(input) ~= 'string' then return nil, 'keine Nummer' end

  local digits = input:gsub('%D', '')
  if digits == '' then return nil, 'keine Ziffern' end

  -- A full international form is 0049 555 1234 and must not be read as a local
  -- number with a country code glued in front.
  digits = digits:gsub('^0049', ''):gsub('^0', '')

  local body = digits:match('^555(%d+)$')
  if not body then
    return nil, 'Unbekannte Nummer. Nifty hat Vorwahl 555.'
  end
  if #body ~= 4 then
    return nil, ('Die Nummer hat %d Ziffern nach der Vorwahl, erwartet werden 4.'):format(#body)
  end

  return ('555-%s'):format(body)
end

print(('[%s] phone account layer ready'):format(RESOURCE))