--- Phone (ADR-0018, ADR-0021).
---
--- Two objects that people constantly conflate:
---
---   * the DEVICE — an ordinary inventory item called `phone`. Any handset opens
---     the menu. It is not identity, it carries nothing, and stealing it steals
---     nothing. That is the point: it removes an entire class of permanent
---     impersonation bug.
---   * the ACCOUNT — the number, the messages, the eventual social profile. It
---     belongs to the character and was created with them.
---
--- Numbers are assigned by the server at character creation and never change
--- (ADR-0021). The player does not choose, so there is nothing to reserve,
--- nothing to trade and no collision to argue about — the UNIQUE constraint is a
--- backstop, not a mechanism.

local RESOURCE = GetCurrentResourceName()

Phone = {}

--- Characters per server are counted in dozens, so this is deliberately small.
--- The space is large enough that nobody will ever see a collision and small
--- enough that nobody will memorise a stranger's number by accident.
local MAX_NUMBER_ATTEMPTS = 25

--- Roll a number and check it is free.
---
--- Collision is handled by asking the database, not by a retry-on-error inside a
--- transaction: the INSERT below happens in the same transaction as the character
--- row, and a failed transaction cannot be partially retried from here. Asking
--- first means the rare collision never reaches the transaction at all.
function Phone.newNumber()
  local prefix = GetSetting('phone.number.prefix', '555-')
  local digits = math.max(4, math.min(tonumber(GetSetting('phone.number.digits', 4)) or 4, 8))

  for _ = 1, MAX_NUMBER_ATTEMPTS do
    local suffix = tostring(math.random(0, 10 ^ digits - 1))
    -- Pad to the requested width: 0042 and 42 must be the same length, or the
    -- "permanent" number of a new player would look different from an old one.
    while #suffix < digits do suffix = '0' .. suffix end

    local candidate = prefix .. suffix

    local taken = Db.one(
      'SELECT 1 AS taken FROM phone_accounts WHERE number = ?',
      { candidate }, 'phone:numberTaken')

    if taken == nil then
      return candidate
    end
  end

  -- Exhausting the attempts means the space is full, which is a server-scale
  -- problem and not something to paper over with a fallback number.
  print(('[%s] FAILED to allocate a free phone number after %d attempts'):format(
    RESOURCE, MAX_NUMBER_ATTEMPTS))
  return nil
end

--- Create the account. Called inside the character-creation transaction.
function Phone.createAccount(characterId)
  local number = Phone.newNumber()
  if not number then return nil, 'no free number' end

  Db.insert([[
    INSERT INTO phone_accounts (character_id, number, is_active) VALUES (?, ?, 1)
  ]], { characterId, number }, 'phone:createAccount')

  return number, nil
end

function Phone.getAccount(characterId)
  local row = Db.one([[
    SELECT character_id, number, is_active, created_at FROM phone_accounts WHERE character_id = ?
  ]], { characterId }, 'phone:getAccount')

  if not row then return nil end

  return {
    characterId = row.character_id,
    number = row.number,
    active = tonumber(row.is_active) == 1,
  }
end

--- Find a character by phone number. This is how you address someone you have
--- never met — there is no contacts model yet (undecided, launch gate).
function Phone.findByNumber(number)
  if type(number) ~= 'string' or number == '' then return nil end

  return Db.one([[
    SELECT c.id, c.first_name, c.last_name, p.number
      FROM phone_accounts p
      JOIN characters c ON c.id = p.character_id
     WHERE p.number = ?
  ]], { number }, 'phone:findByNumber')
end

--- Partial name lookup, so a number can be found by who owns it.
function Phone.search(term)
  if type(term) ~= 'string' or #term < 2 then return {} end

  term = term:gsub('^%s+', ''):gsub('%s+$', '')

  return Db.all([[
    SELECT c.id, c.first_name, c.last_name, p.number
      FROM characters c
      LEFT JOIN phone_accounts p ON p.character_id = c.id
     WHERE c.first_name LIKE ? OR c.last_name LIKE ?
     ORDER BY c.first_name
     LIMIT 25
  ]], { ('%' .. term .. '%'), ('%' .. term .. '%') }, 'phone:search')
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

--- Send. Returns the message id, or nil and a reason.
---
--- There is no "delivery state" and no undelivered queue. Both parties are on the
--- same server during the same window, so a message either has a recipient row
--- or the recipient does not exist — and a character without a phone account is
--- a character who has not been created properly, which is a bug to log rather
--- than a message to queue.
function Phone.send(senderId, recipientId, body)
  if senderId == recipientId then return nil, 'cannot message yourself' end

  if not Phone.getAccount(senderId) then return nil, 'you have no phone' end
  if not Phone.getAccount(recipientId) then return nil, 'recipient has no phone' end

  body = type(body) == 'string' and body or ''
  body = body:gsub('^%s+', ''):gsub('%s+$', '')

  if body == '' then return nil, 'empty message' end

  local maxLength = tonumber(GetSetting('phone.message.max_length', 1000)) or 1000
  -- Truncating rather than refusing: a message that is too long is still a
  -- message someone wanted to send, and the sender has no way to know the limit.
  if #body > maxLength then
    body = body:sub(1, maxLength)
  end

  local id = Nifty.newUuid()

  local inserted = Db.insert([[
    INSERT INTO phone_messages (id, sender_id, recipient_id, body)
    VALUES (?, ?, ?, ?)
  ]], { id, senderId, recipientId, body }, 'phone:send')

  if inserted == nil then return nil, 'could not send' end

  return id, nil
end

--- Inbox. Paged, because this table grows forever (ADR-0004) and an unpaged read
--- would eventually take the server down.
function Phone.inbox(characterId, limit, offset)
  limit = math.min(math.max(tonumber(limit) or 25, 1), 100)
  offset = math.max(tonumber(offset) or 0, 0)

  return Db.all([[
    SELECT m.id, m.sender_id, m.recipient_id, m.body, m.sent_at, m.read_at,
           c.first_name AS sender_first, c.last_name AS sender_last,
           p.number AS sender_number
      FROM phone_messages m
      JOIN characters c ON c.id = m.sender_id
      LEFT JOIN phone_accounts p ON p.character_id = m.sender_id
     WHERE m.recipient_id = ? AND m.cleared_by_recipient = 0
     ORDER BY m.sent_at DESC, m.id DESC
     LIMIT ? OFFSET ?
  ]], { characterId, limit, offset }, 'phone:inbox')
end

function Phone.outbox(characterId, limit, offset)
  limit = math.min(math.max(tonumber(limit) or 25, 1), 100)
  offset = math.max(tonumber(offset) or 0, 0)

  return Db.all([[
    SELECT m.id, m.recipient_id, m.body, m.sent_at,
           c.first_name AS recipient_first, c.last_name AS recipient_last,
           p.number AS recipient_number
      FROM phone_messages m
      JOIN characters c ON c.id = m.recipient_id
      LEFT JOIN phone_accounts p ON p.character_id = m.recipient_id
     WHERE m.sender_id = ? AND m.cleared_by_sender = 0
     ORDER BY m.sent_at DESC, m.id DESC
     LIMIT ? OFFSET ?
  ]], { characterId, limit, offset }, 'phone:outbox')
end

--- Mark everything currently unread as read. "Currently" matters: messages that
--- arrive during the update are not marked, so nothing is silently lost between
--- the read and the screen.
function Phone.markAllRead(characterId)
  return Db.update([[
    UPDATE phone_messages SET read_at = NOW()
     WHERE recipient_id = ? AND read_at IS NULL AND cleared_by_recipient = 0
  ]], { characterId }, 'phone:markRead')
end

--- Clear a message from YOUR inbox. This is private: the sender keeps their copy.
--- Only staff remove content from both sides (ADR-0019).
function Phone.clear(characterId, messageId)
  local affected = Db.update([[
    UPDATE phone_messages SET cleared_by_recipient = 1
     WHERE id = ? AND recipient_id = ?
  ]], { messageId, characterId }, 'phone:clear')

  return affected ~= nil and affected > 0
end

function Phone.unreadCount(characterId)
  local row = Db.one([[
    SELECT COUNT(*) AS c FROM phone_messages
     WHERE recipient_id = ? AND read_at IS NULL AND cleared_by_recipient = 0
  ]], { characterId }, 'phone:unread')

  return row and (tonumber(row.c) or 0) or 0
end

-- ---------------------------------------------------------------------------
-- Reporting (ADR-0019)
-- ---------------------------------------------------------------------------

function Phone.report(reporterId, reportedCharacterId, messageId, reason)
  if reporterId == reportedCharacterId then return nil, 'cannot report yourself' end

  local allowed = { spam = true, harassment = true, impersonation = true, other = true }
  if not allowed[reason] then return nil, 'unknown reason' end

  local id = Nifty.newUuid()

  local inserted = Db.insert([[
    INSERT INTO phone_reports (id, reporter_id, reported_char, message_id, reason)
    VALUES (?, ?, ?, ?, ?)
  ]], { id, reporterId, reportedCharacterId, messageId or '', reason }, 'phone:report')

  if inserted == nil then return nil, 'could not file report' end

  return id, nil
end

--- Open reports, oldest first — staff work a queue in order, and a newest-first
--- queue on a small server means the same three reports get handled repeatedly.
function Phone.openReports(limit)
  limit = math.min(math.max(tonumber(limit) or 25, 1), 100)

  return Db.all([[
    SELECT r.id, r.reported_char, r.reason, r.status, r.created_at,
           m.body AS reported_body,
           c.first_name AS reported_first, c.last_name AS reported_last
      FROM phone_reports r
      JOIN characters c ON c.id = r.reported_char
      LEFT JOIN phone_messages m ON m.id = r.message_id
     WHERE r.status = 'open'
     ORDER BY r.created_at
     LIMIT ?
  ]], { limit }, 'phone:openReports')
end

--- Staff resolution. `actioned` versus `dismissed` is recorded either way: a
--- queue where dismissals are invisible cannot be audited.
function Phone.resolveReport(reportId, status)
  if status ~= 'actioned' and status ~= 'dismissed' then return false, 'bad status' end

  local affected = Db.update([[
    UPDATE phone_reports SET status = ?, resolved_at = NOW() WHERE id = ?
  ]], { status, reportId }, 'phone:resolveReport')

  return affected ~= nil and affected > 0, nil
end

exports('getAccount', Phone.getAccount)
exports('inbox', Phone.inbox)
exports('unreadCount', Phone.unreadCount)