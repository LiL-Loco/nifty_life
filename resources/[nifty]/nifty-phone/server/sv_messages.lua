--[[
  Messages: threads, sending, reading and clearing.

  THE MODEL IS PER-CONVERSATION, NOT PER-FOLDER

  A thread is the pair of numbers, and there is no "sent box". The database has
  `cleared_by_sender` and `cleared_by_recipient` rather than a delete, and the
  difference is the whole reason the history is permanent (ADR-0004).

  One player clearing their thread removes it from THEIR view and nobody else's.
  A real delete would have one side destroy the other side's history, and since
  every message is stored with both directions, deleting one direction to "clean
  up" is indistinguishable from destroying a record somebody else has a right to.

  So: clear sets a flag. Nothing is ever removed. The unread count is derived
  from `read_at` over rows the reader has not cleared, which is a query and not a
  counter that can drift.
]]

local Db = Nifty.Db
local Limits = Nifty.Phone.Limits
local Events = Nifty.Phone.Events

Phone = Phone or {}

--- Every conversation the character is part of, newest activity first.
---
--- Built in SQL rather than in Lua because the unread count is a conditional
--- aggregate per conversation and doing it in Lua means fetching every message
--- of every thread to count them. The subquery is bounded by the join; the Lua
--- alternative is bounded by nothing.
--- @return table[]
function Phone.threadsFor(characterId)
  return Db.all([[
    SELECT
      pa.number,
      c.first_name, c.last_name,
      ct.alias,
      last_msg.body      AS last_body,
      last_msg.sent_at   AS last_at,
      last_msg.sender_id AS last_sender,
      unread.n           AS unread
    FROM phone_accounts me
    -- The other party: everyone this character has ever spoken to, in either
    -- direction. Built from the union of both sides rather than from contacts,
    -- because a thread with someone who is not a contact is still a thread.
    JOIN (
      SELECT recipient_id AS other_id, MAX(sent_at) AS last_at
        FROM phone_messages
       WHERE sender_id = ?
       GROUP BY recipient_id
      UNION
      SELECT sender_id AS other_id, MAX(sent_at) AS last_at
        FROM phone_messages
       WHERE recipient_id = ?
         AND cleared_by_recipient = 0
       GROUP BY sender_id
    ) conv ON conv.other_id <> me.character_id

    JOIN phone_accounts pa ON pa.character_id = conv.other_id
    JOIN characters c      ON c.id        = conv.other_id
    LEFT JOIN phone_contacts ct
           ON ct.owner_id = ? AND ct.contact_id = conv.other_id

    LEFT JOIN phone_messages last_msg
           ON last_msg.id = (
             SELECT m.id FROM phone_messages m
              WHERE (m.sender_id = conv.other_id AND m.recipient_id = me.character_id
                     AND m.cleared_by_recipient = 0)
                 OR (m.sender_id = me.character_id AND m.recipient_id = conv.other_id
                     AND m.cleared_by_sender = 0)
              ORDER BY m.sent_at DESC LIMIT 1)

    LEFT JOIN (
      SELECT recipient_id, COUNT(*) AS n
        FROM phone_messages
       WHERE recipient_id = ?
         AND read_at IS NULL
         AND cleared_by_recipient = 0
       GROUP BY recipient_id
    ) unread ON unread.recipient_id = conv.other_id

   WHERE me.character_id = ?
     AND (last_msg.id IS NOT NULL)
   ORDER BY last_msg.sent_at DESC
   LIMIT 200
  ]], { characterId, characterId, characterId, characterId, characterId },
    'phone:threadsFor') or {}
end

--- One conversation, oldest first — the order it was written in.
--- @return table[]
function Phone.threadMessages(characterId, number, limit)
  local normalised, err = Phone.normalise(number)
  if not normalised then return {} end

  local otherId = Phone.characterByNumber(normalised)
  if not otherId then return {} end

  local take = tonumber(limit) or Limits.THREAD_PAGE
  if take < 1 then take = 1 end
  if take > 200 then take = 200 end

  return Db.all([[
    SELECT m.id, m.sender_id, m.recipient_id, m.body, m.sent_at, m.read_at
      FROM phone_messages m
     WHERE ( (m.sender_id = ? AND m.recipient_id = ? AND m.cleared_by_sender = 0)
          OR (m.sender_id = ? AND m.recipient_id = ? AND m.cleared_by_recipient = 0) )
     ORDER BY m.sent_at DESC
     LIMIT ?
  ]], { characterId, otherId, otherId, characterId, take },
    'phone:threadMessages') or {}
end

--- Send. Returns the new row so the panel can render it without a refetch.
--- @return table|nil row, string|nil err
function Phone.sendMessage(characterId, number, body)
  local normalised, err = Phone.normalise(number)
  if not normalised then return nil, err end

  local text = (type(body) == 'string') and body or ''
  text = text:gsub('^%s+', ''):gsub('%s+$', '')

  if text == '' then return nil, 'Leere Nachricht.' end
  -- Exact, not rounded: the column is varchar(1000), and a message of 1001
  -- characters is a refusal from the database that the player cannot act on.
  if #text > Limits.MESSAGE_BODY then
    return nil, ('Die Nachricht ist zu lang (maximal %d Zeichen).'):format(Limits.MESSAGE_BODY)
  end

  local targetId = Phone.characterByNumber(normalised)
  if not targetId then return nil, 'Diese Nummer ist nicht vergeben.' end
  if targetId == characterId then return nil, 'Das bist du.' end

  local row = Db.one([[
    INSERT INTO phone_messages (id, sender_id, recipient_id, body)
    VALUES (?, ?, ?, ?)
    RETURNING id, sender_id, recipient_id, body, sent_at, read_at
  ]], { Nifty.newUuid(), characterId, targetId, text }, 'phone:sendMessage')

  -- The recipient is notified EVEN IF THEY HAVE NO PHONE IN THEIR POCKET. That is
  -- ADR-0018's deliberate pressure: messages keep arriving while the owner has no
  -- device, and it is what makes replacing a lost phone matter. The client drops
  -- it if the panel is closed and the character has nothing to read it with.
  TriggerClientEvent(Events.INCOMING_MSG, targetId, {
    from    = normalised,
    name    = Phone.displayName(characterId),
    preview = #text > 60 and (text:sub(1, 57) .. '…') or text,
  })

  return row
end

--- Mark everything from this person as read.
function Phone.markRead(characterId, number)
  local normalised = Phone.normalise(number)
  if not normalised then return false end

  local otherId = Phone.characterByNumber(normalised)
  if not otherId then return false end

  Db.update([[
    UPDATE phone_messages SET read_at = NOW()
     WHERE sender_id = ? AND recipient_id = ? AND read_at IS NULL
  ]], { otherId, characterId }, 'phone:markRead')

  return true
end

--- Clear THIS character's view. The other side keeps everything.
function Phone.clearThread(characterId, number)
  local normalised = Phone.normalise(number)
  if not normalised then return false end

  local otherId = Phone.characterByNumber(normalised)
  if not otherId then return false end

  Db.update([[
    UPDATE phone_messages SET cleared_by_recipient = 1
     WHERE sender_id = ? AND recipient_id = ?
  ]], { otherId, characterId }, 'phone:clearRecipient')

  Db.update([[
    UPDATE phone_messages SET cleared_by_sender = 1
     WHERE sender_id = ? AND recipient_id = ?
  ]], { characterId, otherId }, 'phone:clearSender')

  return true
end

--- Total unread across every thread. The HUD badge, and the reason a phone in a
--- pocket is still worth opening.
--- @return number
function Phone.unreadCount(characterId)
  local row = Db.one([[
    SELECT COUNT(*) AS n FROM phone_messages
     WHERE recipient_id = ? AND read_at IS NULL AND cleared_by_recipient = 0
  ]], { characterId }, 'phone:unreadCount')

  return row and row.n or 0
end