--[[
  The server event bridge: every panel callback arrives here, and this is the
  only file that decides whether the caller is allowed to have what they asked
  for.

  WHY THE CHECK IS HERE AND NOT IN THE CALLBACKS

  ADR-0018 says the phone is a device. A character may use the menu while
  carrying ANY handset, and the number behind it belongs to them permanently. So
  every entry point asks the same two questions in the same order:

    1. is there an active character?
    2. are they carrying a phone?

  Both are checked per request rather than once at open. A player can drop their
  handset into a duffel bag while the panel is open, and a check at open time
  would let them keep sending messages from a phone they no longer have — which
  is the exact hole ADR-0018 was written to close.
]]

local A = Nifty.Phone.Actions
local Limits = Nifty.Phone.Limits
local RESOURCE = GetCurrentResourceName()

Phone = Phone or {}

--- Resolve the caller, or explain why not.
--- @return string|nil characterId, string|nil err
local function caller(src)
  local character = Nifty.Identity.getActiveCharacter(src)
  if not character then
    return nil, 'Du hast gerade keinen Charakter.'
  end
  return character.id
end

--- ADR-0018: the account is the character's, the device is not.
---
--- Returns the account only if a handset is actually in the inventory. Note what
--- this does NOT ask: whether it is the handset they were issued. A replacement
--- works identically, which is the point — losing a phone must not cost a
--- character its social life.
---
--- Three return values: the account, the reason it failed, and the character id.
--- The character id comes last because the failure cases return nil for it, and a
--- caller that wrote `account, err = ...` and then used `characterId` would get a
--- stale value from a previous request rather than nil.
--- @return table|nil account, string|nil err, string|nil characterId
local function accountWithDevice(src)
  local characterId, err = caller(src)
  if not characterId then return nil, err end

  local account, accErr = Phone.accountFor(characterId)
  if not account then return nil, accErr end

  local has = Nifty.Inventory.has(characterId, 'phone')
  if not has then
    return nil, 'Du hast kein Handy dabei.'
  end

  -- `is_active` is suspension, not hardware. A suspended account still has a
  -- number and still has history; it just cannot be used right now.
  if not account.active then
    return nil, 'Dein Handy-Konto ist gesperrt.'
  end

  return account, nil, characterId
end

--- Tell the caller something went wrong. The panel shows it; nothing is thrown,
--- because a thrown error in an event handler stops the resource.
local function tellError(src, message)
  TriggerClientEvent(A.ERROR, src, { message = message or 'Unbekannter Fehler.' })
end

-- ---------------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------------

--- The whole state, in one message.
---
--- Sent as ONE push rather than four. The panel renders once, and it cannot
--- render a contact list that disagrees with the threads beside it because the
--- two arrived in different frames.
RegisterNetEvent('nifty:server:phone:state')
AddEventHandler('nifty:server:phone:state', function(src)
  local account, err, characterId = accountWithDevice(src)
  if not account then return tellError(src, err) end

  TriggerClientEvent(A.OPEN, src, {
    account = account,
    contacts = Phone.contactsFor(characterId),
    threads = Phone.threadsFor(characterId),
    call = Phone.callView(characterId),
    callLog = Phone.callLog(characterId, 25),
    unread = Phone.unreadCount(characterId),
    -- Telling the panel what the number looks like rather than letting it
    -- format the string means the keypad preview and the contacts list can
    -- never disagree about how a number is written.
    limits = Limits,
  })
end)

RegisterNetEvent('nifty:server:phone:closed')
AddEventHandler('nifty:server:phone:closed', function() end)

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:phone:sendMessage')
AddEventHandler('nifty:server:phone:sendMessage', function(src, data)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  local row, sendErr = Phone.sendMessage(characterId, data and data.to, data and data.body)
  if not row then return tellError(src, sendErr) end

  -- The sender's own panel gets the row back rather than re-fetching the thread.
  -- A send that shows up a second later, or not at all because a race lost, is
  -- the difference between a phone and a guessing game.
  TriggerClientEvent(A.THREADS, src, { sent = row })
end)

--- One conversation's messages, for the thread view.
---
--- A separate fetch rather than part of `phone:state` on purpose: the open
--- payload carries every thread's LAST message, which is what the list draws.
--- Folding full histories into it would make opening the phone read the entire
--- message history of a character who has played for a month.
RegisterNetEvent('nifty:server:phone:openThread')
AddEventHandler('nifty:server:phone:openThread', function(src, data)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  local number = data and data.number
  local messages = Phone.threadMessages(characterId, number, (data and data.limit))

  TriggerClientEvent(A.THREAD, src, { number = number, messages = messages })

  -- Opening a conversation is also reading it. Doing it here rather than from the
  -- panel means the unread badge clears even if the panel is closed straight
  -- afterwards.
  Phone.markRead(characterId, number)
end)

RegisterNetEvent('nifty:server:phone:markRead')
AddEventHandler('nifty:server:phone:markRead', function(src, data)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  Phone.markRead(characterId, data and data.number)
  TriggerClientEvent(A.THREADS, src, { read = data.number })
end)

RegisterNetEvent('nifty:server:phone:clearThread')
AddEventHandler('nifty:server:phone:clearThread', function(src, data)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  Phone.clearThread(characterId, data and data.number)
  TriggerClientEvent(A.THREADS, src, { cleared = data.number })
end)

-- ---------------------------------------------------------------------------
-- Contacts
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:server:phone:saveContact')
AddEventHandler('nifty:server:phone:saveContact', function(src, data)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  local ok, saveErr = Phone.saveContact(characterId, data and data.number, data and data.alias)
  if not ok then return tellError(src, saveErr) end

  TriggerClientEvent(A.CONTACTS, src, { contacts = Phone.contactsFor(characterId) })
end)

RegisterNetEvent('nifty:server:phone:deleteContact')
AddEventHandler('nifty:server:phone:deleteContact', function(src, data)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  local ok, delErr = Phone.deleteContact(characterId, data and data.number)
  if not ok then return tellError(src, delErr) end

  TriggerClientEvent(A.CONTACTS, src, { contacts = Phone.contactsFor(characterId) })
end)

-- ---------------------------------------------------------------------------
-- Calls
--
-- The device check is the same for placing and answering, and that is not an
-- oversight: ADR-0018 says the account belongs to the character, so a character
-- carrying a handset is the account holder whoever placed the call.
-- ---------------------------------------------------------------------------

local function pushCall(src, characterId)
  TriggerClientEvent(A.CALL, src, { call = Phone.callView(characterId) })
end

RegisterNetEvent('nifty:server:phone:callStart')
AddEventHandler('nifty:server:phone:callStart', function(src, data)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  local _, callErr, reason = Phone.placeCall(characterId, data and data.number)
  if callErr or reason then
    -- `busy` is its own message. "Die Leitung ist besetzt" and "Unbekannte
    -- Nummer" are different facts and the player acts on them differently.
    if reason == Nifty.Phone.CallEnd.BUSY then
      return tellError(src, 'Die Leitung ist besetzt.')
    end
    return tellError(src, callErr)
  end

  pushCall(src, characterId)
end)

RegisterNetEvent('nifty:server:phone:callAnswer')
AddEventHandler('nifty:server:phone:callAnswer', function(src)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  local _, answerErr = Phone.answerCall(characterId)
  if answerErr then return tellError(src, answerErr) end

  pushCall(src, characterId)
end)

RegisterNetEvent('nifty:server:phone:callDecline')
AddEventHandler('nifty:server:phone:callDecline', function(src)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  local _, decErr = Phone.declineCall(characterId)
  if decErr then return tellError(src, decErr) end

  pushCall(src, characterId)
end)

RegisterNetEvent('nifty:server:phone:callEnd')
AddEventHandler('nifty:server:phone:callEnd', function(src)
  local _, err, characterId = accountWithDevice(src)
  if not characterId then return tellError(src, err) end

  Phone.endCall(characterId)
  pushCall(src, characterId)
end)

-- ---------------------------------------------------------------------------
-- The device itself
-- ---------------------------------------------------------------------------

--- Using the handset opens the menu. This is the whole of ADR-0018's device
--- half: the item is the entry point, so a character with no phone has no way in
--- even if they know the hotkey.
---
--- Registered against nifty-inventory rather than a target, because a phone is
--- in a bag, not on a wall. The server re-checks the device on every request
--- anyway; this registration is about whether the player CAN reach the menu, not
--- about whether they are allowed to use it.
RegisterNetEvent('nifty:server:phone:usedItem')
AddEventHandler('nifty:server:phone:usedItem', function(src)
  TriggerClientEvent(Nifty.Phone.Events.OPEN, src)
end)

CreateThread(function()
  if not Nifty.Inventory or type(Nifty.Inventory.registerUseHandler) ~= 'function' then
    print(('[%s] nifty-inventory did not expose registerUseHandler — the phone cannot be opened by using the item. F4 still works.')
      :format(RESOURCE))
    return
  end

  local ok, err = pcall(Nifty.Inventory.registerUseHandler, 'phone',
    function(src)
      TriggerClientEvent(Nifty.Phone.Events.OPEN, src)
    end)

  if not ok then
    print(('[%s] could not register the phone use handler: %s'):format(RESOURCE, tostring(err)))
  end
end)

-- The handler has to be removed on stop. A registered callback that outlives its
-- resource is a callback that fires into nothing, and nifty-inventory would keep
-- it until IT is restarted.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end

  if Nifty.Inventory and type(Nifty.Inventory.unregisterUseHandler) == 'function' then
    pcall(Nifty.Inventory.unregisterUseHandler, 'phone')
  end
end)

print(('[%s] phone server ready'):format(RESOURCE))