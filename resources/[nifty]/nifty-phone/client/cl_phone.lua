--[[
  The phone on the client: opening it, closing it, and moving every panel
  message to the server.

  THE DEVICE RULE (ADR-0018)

  A phone is an item in the inventory, not a property of the character. The
  character owns an ACCOUNT — a number and its history, permanently — and may use
  the menu while carrying ANY handset. Handing a phone to another player moves
  hardware, not identity: the giver loses the menu because they are no longer
  carrying a device, and the receiver gains a device that does nothing, because
  they are not the account holder.

  That is why the check below is `Inventory.has(characterId, 'phone')` and not
  "is this the phone they were issued". The second version would make losing a
  phone a permanent loss of a character's entire social life, which is exactly
  what ADR-0018 rejected.
]]

local RESOURCE = GetCurrentResourceName()
local A = Nifty.Phone.Actions
local CB = Nifty.Phone.Callbacks
local Events = Nifty.Phone.Events
local CallState = Nifty.Phone.CallState

-- Whether the panel is open. Declared before the handlers below rather than
-- with the rest of the state, because the `playerDropped` handler clears it and
-- a local declared after its first use silently becomes a global that nothing
-- else reads.
local phoneOpen = false

-- ---------------------------------------------------------------- focus
-- NUI focus, owned entirely by this resource. Nothing about it is shared.
--
-- `SetNuiFocus` only does anything when the CALLING resource declares a
-- `ui_page`, because it acts on that resource's own CEF. This one declares one.
-- The focus broker that used to live in nifty-core could therefore never hand
-- the keyboard over, whatever it reported: it has no ui_page on purpose, so
-- every native call it issued was a silent no-op — it logged `granted`, returned
-- true, and the player got no cursor while every click punched their character
-- through a wall.
--
-- WHAT IS GIVEN UP, STATED PLAINLY: with no shared broker nobody can ask "who
-- holds the keyboard right now?", so two surfaces that can be open at once are
-- arbitrated by whoever opened last. ox_inventory lives with the identical
-- constraint and papers over it with `Wait(100)` and a hopeful comment.
--
-- `SetNuiFocusKeepInput(false)` is not decoration: ox_target raises that flag
-- globally on every target interaction and never lowers it
-- (ox_target/client/state.lua), so without it a click on an open panel also
-- reaches the game and moves the character.
local focusHeld = false

--- Take the keyboard and show the cursor.
local function acquireFocus()
  if focusHeld then return end

  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  focusHeld = true
end

--- Hand it back. Safe to call when we never had it.
local function releaseFocus()
  if not focusHeld then return false end

  focusHeld = false
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  return true
end

-- Stopping with the keyboard held strands a captured cursor with no way out but a
-- reconnect, so the stop path has to release it. This handler cannot be inherited
-- from anywhere: every resource that can hold focus needs its own.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end

  releaseFocus()
end)

-- Not just the focus flag. A SOFT disconnect — the server restarting, a network
-- blip — fires playerDropped while this Lua VM survives, so every "is open"
-- flag set before it is still set afterwards. The CEF survives a soft drop too,
-- so without the message the phone is still drawn on the other side of it.
AddEventHandler('playerDropped', function()
  focusHeld = false
  phoneOpen = false
  SendNUIMessage({ action = A.CLOSE })
end)

-- ---------------------------------------------------------------- state

--- Ask the server for the whole state and push it. One message, not a chain:
--- a panel that fetches account, contacts and threads separately renders three
--- times and can render a contact list that does not match the threads beside it.
local function pushState()
  TriggerServerEvent('nifty:server:phone:state')
end

local function closePhone()
  if not phoneOpen then return end

  phoneOpen = false
  releaseFocus()
  SendNUIMessage({ action = A.CLOSE })
  -- The camera-free panel needs no cleanup beyond this, but the server must stop
  -- treating the character as sitting in front of an open phone — it uses that
  -- for the caller's own timer and for suppressing a second incoming call.
  TriggerServerEvent('nifty:server:phone:closed')
end

local function openPhone()
  if phoneOpen then return end

  phoneOpen = true
  acquireFocus()
  -- The cursor lands over the panel rather than wherever the mouse last was,
  -- which coming out of the game world is usually the middle of the screen — and
  -- the player then clicks what they believe is a button and hits the world
  -- behind the panel. Normalised coordinates, 0..1.
  SetCursorLocation(0.78, 0.30)
  pushState()
end

-- ---------------------------------------------------------------- open paths

-- ADR-0018: the phone opens by USING the item. nifty-inventory routes a used
-- item to its registered handler, which is how a handset becomes an entry point
-- rather than a hotkey that works whether or not the character owns one.
RegisterNetEvent('nifty:client:phone:open')
AddEventHandler('nifty:client:phone:open', function()
  openPhone()
end)

RegisterCommand('niftyphone', function()
  TriggerEvent('nifty:client:phone:open')
end, false)
RegisterKeyMapping('niftyphone', 'Nifty Life — Handy', 'keyboard', 'F4')

-- ---------------------------------------------------------------- incoming
--
-- Both of these arrive whether or not the panel is open. That is the whole point
-- of ADR-0018's "messages keep arriving while the owner has no device": the
-- pressure is what makes a lost phone worth replacing. Dropping them silently
-- would make the phone a feature you only benefit from if you never misplace it.

RegisterNetEvent(Events.INCOMING_CALL)
AddEventHandler(Events.INCOMING_CALL, function(payload)
  if not payload then return end

  if payload.state == CallState.IDLE then
    -- The other end hung up or declined. If our panel is showing a call screen,
    -- it has to come down; if not, there is nothing to do.
    if phoneOpen then SendNUIMessage({ action = A.CALL, data = { call = nil } }) end
    return
  end

  -- A call arrived while the phone is closed. The panel stays closed and the
  -- player hears nothing until they take the phone out — the ringing is a
  -- server-side state, not something the CEF can be trusted to hold.
  if not phoneOpen then
    TriggerServerEvent('nifty:server:phone:missedPrompt', payload.id)
    return
  end

  SendNUIMessage({ action = A.CALL, data = { call = payload } })
end)

RegisterNetEvent(Events.INCOMING_MSG)
AddEventHandler(Events.INCOMING_MSG, function(payload)
  -- Nothing to render while the phone is closed, but the UNREAD COUNT has to
  -- move, or the HUD badge lies. The count is server-side and re-pushed with the
  -- rest of the state, so this is where the badge is kept honest.
  if phoneOpen then
    SendNUIMessage({ action = A.THREADS, data = { bump = payload } })
  end
end)

-- ---------------------------------------------------------------- callbacks
--
-- Every callback is PREFIXED. `closePanel` is registered by nifty-clothing,
-- nifty-inventory and nifty-world as well, and whichever answers first wins —
-- that collision is in the tree, not hypothetical.

RegisterNUICallback(CB.CLOSE, function(_, cb)
  closePhone()
  cb({ ok = true })
end)

RegisterNUICallback(CB.GET_STATE, function(_, cb)
  pushState()
  cb({ ok = true })
end)

-- The rest are thin: they forward to the server and let the answer come back as
-- a push. Answering a callback from the SERVER would need the round trip to be
-- synchronous across a resource boundary, and a database call in the middle of
-- it would be a database call inside a NUI frame.
for name, event in pairs({
  [CB.SEND_MESSAGE]   = 'nifty:server:phone:sendMessage',
  [CB.OPEN_THREAD]    = 'nifty:server:phone:openThread',
  [CB.MARK_READ]      = 'nifty:server:phone:markRead',
  [CB.CLEAR_THREAD]   = 'nifty:server:phone:clearThread',
  [CB.SAVE_CONTACT]   = 'nifty:server:phone:saveContact',
  [CB.DELETE_CONTACT] = 'nifty:server:phone:deleteContact',
  [CB.CALL_START]     = 'nifty:server:phone:callStart',
  [CB.CALL_ANSWER]    = 'nifty:server:phone:callAnswer',
  [CB.CALL_DECLINE]   = 'nifty:server:phone:callDecline',
  [CB.CALL_END]       = 'nifty:server:phone:callEnd',
}) do
  RegisterNUICallback(name, function(data, cb)
    TriggerServerEvent(event, data or {})
    cb({ ok = true })
  end)
end

print(('[%s] phone client ready'):format(RESOURCE))