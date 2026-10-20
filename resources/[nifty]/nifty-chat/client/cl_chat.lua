--[[
  Chat — the client half.

  This file owns ONE thing that nothing else in the resource may touch while it is
  true: the game's keyboard and cursor.

  `SetNuiFocus` is a single global client native, and after the resource split there
  are ten surfaces in this project that want the keyboard — chat, creator, phone,
  panels. Whoever opens last wins, so a player can end up typing into a window they
  are not looking at. There used to be a broker in nifty-core to stop that. It is
  gone, and the reason is the next paragraph: it could never have worked.

  The CALL has to be made from HERE. SetNuiFocus acts on the calling resource's own
  CEF instance, so it only does anything from a resource that declares a ui_page.
  nifty-core deliberately declares none — every ui_page is its own full-screen
  composited browser, and one parked there once swallowed every click in the
  creator. A broker living there
  therefore could not hand over the keyboard however much it wanted to; it only
  ever logged `granted` and did nothing. This file makes the call itself.

  The rules that fall out of asking rather than taking:
    - Every exit path releases, through one function, including resource stop.
    - A refusal is reported to the player rather than swallowed: a chat box that
      does not appear looks exactly like a key binding that is not bound.

  The chat LOG is the exception: it is always visible and never holds focus. A
  chat you cannot read while walking is not a chat.
]]

local RESOURCE = GetCurrentResourceName()

local Input = { open = false }

-- ---------------------------------------------------------------- focus
-- NUI focus, owned entirely by this resource. Nothing about it is shared.
--
-- `SetNuiFocus` only does anything when the CALLING resource declares a
-- `ui_page`, because it acts on that resource's own CEF. This one declares one.
-- The focus broker in nifty-core could therefore never hand the keyboard over,
-- whatever it reported: it has no ui_page on purpose, so every native call it
-- issued was a silent no-op — it logged `granted`, returned true, and the player
-- got no cursor while every click punched their character through a wall.
--
-- WHAT IS GIVEN UP, STATED PLAINLY: with no shared broker nobody can ask "who
-- holds the keyboard right now?", so two surfaces that can be open at once are
-- arbitrated by whoever opened last. ox_inventory lives with the identical
-- constraint and papers over it with `Wait(100)` and a hopeful comment.
--
-- `SetNuiFocusKeepInput(false)` is not decoration: ox_target raises that flag
-- globally on every target interaction and never lowers it
-- (ox_target/client/state.lua), so without it a click on an open chat box also
-- reaches the game and moves the character.
local focusHeld = false

--- Take the keyboard and show the cursor.
local function acquireFocus()
  if focusHeld then return end

  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  focusHeld = true
end

--- Hand it back. Safe to call when we never had it, so the close paths do not
--- have to track state themselves.
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

AddEventHandler('playerDropped', function()
  focusHeld = false
end)

--- Close the input, releasing focus, whatever route we got here by.
---
--- Every path out of the open state goes through this one function. That is the
--- only way to be sure there is no route that hides the box and forgets the focus.
local function closeInput()
  if not Input.open then return end

  Input.open = false
  releaseFocus()
  SendNUIMessage({ action = 'chatInput', data = { open = false } })
end

--- Ask the NUI to show the input. Focus is granted BEFORE the NUI draws anything,
--- because a field that appears without focus is a field nobody can type into.
local function openInput()
  if Input.open then return end

  acquireFocus()
  Input.open = true
  SendNUIMessage({ action = 'chatInput', data = { open = true } })
end

-- ---------------------------------------------------------------------------
-- Key bindings
-- ---------------------------------------------------------------------------

RegisterCommand('niftychat', openInput, false)

--- `T` is the GTA default chat key. Rebinding to it means the vanilla chat box
--- never opens, which is the point — two chat boxes would be one too many.
RegisterKeyMapping('niftychat', 'Nifty Life — Chat', 'keyboard', 'T')

--- Escape from inside the NUI. FiveM only delivers it as a command while the page
--- has focus, which is exactly when it is needed.
RegisterCommand('niftychatclose', function()
  closeInput()
end, false)

--- Only the local flag is left to clear here. Dropping the actual cursor is done
--- by the focus block above, which registers its own `onResourceStop`. Here only
--- the local flag is left: the chat box must not come back from a restart
--- believing it is open.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  Input.open = false
end)

--- Coming BACK from a restart. Fresh Lua state means a fresh, empty input box.
AddEventHandler('onClientResourceStart', function(resource)
  if resource ~= RESOURCE then return end
  Input.open = false
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

--- Cancelled. Focus first, then the message: the NUI has already moved on and
--- leaving focus held for even one frame makes the box feel like it swallowed the
--- keypress.
RegisterNUICallback('chatCancel', function(_, cb)
  closeInput()
  cb({ ok = true })
end)

--- Sending. The text goes to the server and is not trusted there.
---
--- The input closes on the SAME event whether or not the server accepts the
--- message. Holding the box open until the server answers would tie the UI to a
--- round trip, and the local echo in ui/app.js covers the gap — so what the player
--- sees is instant while the broadcast remains the server's decision.
RegisterNUICallback('chatSend', function(data, cb)
  local body = type(data) == 'table' and data.text or ''

  closeInput()

  TriggerServerEvent('nifty:server:chatSay', { text = tostring(body) })
  cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- Server pushes
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:client:chat', function(payload)
  if type(payload) ~= 'table' then return end

  if payload.system then
    SendNUIMessage({ action = 'chatSystem', data = { text = tostring(payload.text or '') } })
    return
  end

  SendNUIMessage({
    action = 'chatLine',
    data = {
      author = tostring(payload.author or '?'),
      text = tostring(payload.text or ''),
    },
  })
end)

exports('isInputOpen', function() return Input.open end)

print(('[%s] chat client ready'):format(RESOURCE))