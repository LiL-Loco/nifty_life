--[[
  The Lua <-> NUI contract for the phone, in one place.

  WHY THIS FILE IS THE SAME ON BOTH SIDES OF THE BUILD

  `SendNUIMessage` is a SHARED CHANNEL. Every resource that owns a `ui_page` has
  its own CEF browser, and every one of those browsers sees every message the
  server pushes. A message named `open` therefore unhides the creator, the shop
  and the inventory at once, and which frame is on top is decided by load order
  rather than by anybody's intent.

  That cost a day once already: a panel was visible, its buttons belonged to the
  frame underneath it, and every click landed on the frame above. The fix was not
  focus and not CSS — it was that action names collided. So every action and
  callback below carries the `phone:` prefix, and that is not decoration.

  The same list exists as packages/phone/src/contract.ts, typed. If the two drift
  apart the build fails, which is the point: a phone panel that answers nothing
  looks identical to one that is merely slow.
]]

Nifty = Nifty or {}
Nifty.Phone = Nifty.Phone or {}

--- Actions the Lua side pushes INTO the panel. All carry the `phone:` prefix.
Nifty.Phone.Actions = {
  OPEN     = 'phone:open',      -- full state, on open
  CLOSE    = 'phone:close',     -- panel closed, including on stop and drop
  CALL     = 'phone:call',      -- call state changed, or became nil
  THREADS  = 'phone:threads',   -- thread list or unread counts changed
  THREAD   = 'phone:thread',    -- one conversation's messages, opened
  CONTACTS = 'phone:contacts',  -- contact list changed
  ERROR    = 'phone:error',     -- something the player should be told
  TOAST    = 'phone:toast',     -- a confirmation that is not an error
}

--- Callbacks the panel calls INTO Lua. Also prefixed, for the same reason: a bare
--- `closePanel` is registered by nifty-clothing, nifty-inventory and nifty-world,
--- and whichever resource answers first wins. That collision is not hypothetical,
--- it is in the tree.
Nifty.Phone.Callbacks = {
  CLOSE        = 'phoneClose',
  GET_STATE    = 'phoneGetState',
  SEND_MESSAGE = 'phoneSendMessage',
  MARK_READ    = 'phoneMarkRead',
  OPEN_THREAD  = 'phoneOpenThread',
  CLEAR_THREAD = 'phoneClearThread',
  SAVE_CONTACT = 'phoneSaveContact',
  DELETE_CONTACT = 'phoneDeleteContact',
  CALL_START   = 'phoneCallStart',
  CALL_ANSWER  = 'phoneCallAnswer',
  CALL_DECLINE = 'phoneCallDecline',
  CALL_END     = 'phoneCallEnd',
}

--- Server -> client events. `open` is client-driven (the player used the item),
--- the other two are pushed and must work while the panel is CLOSED — a message
--- that arrives silently while the phone is in a pocket is the point of the
--- design (ADR-0018), not an edge case.
Nifty.Phone.Events = {
  OPEN         = 'nifty:client:phone:open',
  INCOMING_CALL = 'nifty:client:phone:incomingCall',
  INCOMING_MSG  = 'nifty:client:phone:incomingMessage',
}

--- The call lifecycle, as the PANEL draws it. This is a view model, not the
--- database state: `phone_calls` has five end reasons and the panel only needs
--- to know whether the phone is ringing, in a call, or idle.
---
--- The three states are mutually exclusive and there is no fourth. A panel that
--- has to decide between two booleans is a panel that will draw both.
Nifty.Phone.CallState = {
  IDLE    = 'idle',
  OUTGOING = 'outgoing',   -- we placed it, they have not answered
  INCOMING = 'incoming',   -- they placed it, we have not answered
  ACTIVE   = 'active',     -- answered
}

--- Reasons a call ended, as the call log shows them. `declined` and `missed` are
--- different social facts and the panel renders them differently, which is why
--- they are different values in the ENUM and not one `ended`.
Nifty.Phone.CallEnd = {
  ANSWERED     = 'answered',
  DECLINED     = 'declined',
  MISSED       = 'missed',
  BUSY         = 'busy',
  CANCELLED    = 'cancelled',
  UNAVAILABLE  = 'unavailable',
}

--- Bounds. Every one of these is enforced on the SERVER, and each exists because
--- the client is the untrusted side of this channel.
Nifty.Phone.Limits = {
  MESSAGE_BODY = 1000,   -- varchar(1000) in phone_messages. Exact, not round.
  ALIAS        = 64,     -- varchar(64) on phone_contacts.alias
  THREAD_PAGE  = 50,     -- messages per fetch; the client pages, it does not
                         -- ask for a character's whole history in one message.
}