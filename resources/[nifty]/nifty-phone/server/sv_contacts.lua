--[[
  Contacts.

  WHY CONTACTS ARE NOT DERIVED FROM MESSAGE HISTORY

  "Who is in my phone book" and "who have I written to" look like the same
  question until you use them. The second one is answered by phone_messages; the
  first is not, because a contact is a NAME THE OWNER CHOSE, and that choice
  does not exist anywhere else in the schema. Deriving contacts from history
  means every person you ever texted is suddenly in your contacts, under their
  own name, forever — and deleting a contact becomes impossible, because the
  next message puts them back.

  So `phone_contacts` is an explicit table, and saving the same person twice
  edits the alias instead of adding a row (UNIQUE on owner_id, contact_id).
]]

local Db = Nifty.Db
local Limits = Nifty.Phone.Limits

Phone = Phone or {}

--- The owner's contacts, joined with the name each contact's number belongs to.
---
--- One query rather than two: the panel draws a list, and a list rendered in N
--- round trips is a list that arrives in pieces.
--- @return table[]
function Phone.contactsFor(characterId)
  return Db.all([[
    SELECT ct.contact_id, ct.alias,
           pa.number, pa.is_active,
           c.first_name, c.last_name
      FROM phone_contacts ct
      JOIN phone_accounts pa ON pa.character_id = ct.contact_id
      JOIN characters c      ON c.id        = ct.contact_id
     WHERE ct.owner_id = ?
     ORDER BY COALESCE(ct.alias, c.last_name, c.first_name) ASC
  ]], { characterId }, 'phone:contactsFor') or {}
end

--- Save or rename a contact.
---
--- `ON DUPLICATE KEY UPDATE` is what makes "save this person" idempotent: the
--- panel's save button is the same call whether the contact is new or existing,
--- and the client never has to know which it was.
--- @return boolean ok, string|nil err
function Phone.saveContact(characterId, number, alias)
  local normalised, err = Phone.normalise(number)
  if not normalised then return false, err end

  local targetId = Phone.characterByNumber(normalised)
  if not targetId then return false, 'Diese Nummer ist nicht vergeben.' end
  if targetId == characterId then return false, 'Das bist du.' end

  -- A suspended account can still be a contact — knowing someone was put on a
  -- watch list is not the same as being able to reach them, and hiding the row
  -- would make the list lie about who is on it.
  local clean = nil
  if alias ~= nil and type(alias) == 'string' then
    clean = alias:gsub('^%s+', ''):gsub('%s+$', '')
    if #clean == 0 then clean = nil end
    if #clean > Limits.ALIAS then
      return false, ('Der Name ist zu lang (maximal %d Zeichen).'):format(Limits.ALIAS)
    end
  end

  Db.insert([[
    INSERT INTO phone_contacts (owner_id, contact_id, alias)
    VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE alias = VALUES(alias)
  ]], { characterId, targetId, clean }, 'phone:saveContact')

  return true
end

--- @return boolean ok, string|nil err
function Phone.deleteContact(characterId, number)
  local normalised, err = Phone.normalise(number)
  if not normalised then return false, err end

  local targetId = Phone.characterByNumber(normalised)
  if not targetId then return false, 'Diese Nummer ist nicht vergeben.' end

  -- Scoped by owner on purpose. A contact is a row in the OWNER's list; deleting
  -- "the contact" globally would delete the other person's copy of you too, which
  -- is not a thing one player should be able to do to another.
  Db.update('DELETE FROM phone_contacts WHERE owner_id = ? AND contact_id = ?',
    { characterId, targetId }, 'phone:deleteContact')

  return true
end

--- One row, in the shape the panel's contact view wants.
--- @return table|nil
function Phone.resolveNumber(ownerId, number)
  local normalised = Phone.normalise(number)
  if not normalised then return nil end

  local contactId, account = Phone.characterByNumber(normalised)
  if not contactId then return nil end

  local contact = Db.one(
    'SELECT alias FROM phone_contacts WHERE owner_id = ? AND contact_id = ?',
    { ownerId, contactId }, 'phone:resolveNumber')

  return {
    number     = normalised,
    characterId = contactId,
    -- The alias the OWNER gave them, not the name they gave themselves. When
    -- there is no alias the panel falls back to the character's own name, and the
    -- panel decides that — the server sends both and does not editorialize.
    alias      = contact and contact.alias or nil,
    name       = Phone.displayName(contactId),
    active     = account and account.is_active == 1 or false,
    saved      = contact ~= nil,
  }
end