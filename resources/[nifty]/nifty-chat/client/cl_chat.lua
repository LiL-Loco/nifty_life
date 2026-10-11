--- Chat — the client half.
---
--- This file owns ONE thing that nothing else in the resource may touch while it is
--- true: the game's keyboard and cursor.
---
--- It does NOT own focus outright. `SetNuiFocus` is a single global client native,
--- and after the resource split there are ten surfaces in this project that want the
--- keyboard — chat, creator, phone, panels. If each of them called the native
--- itself, last writer wins and the player types into a window they are not looking
--- at. So focus is ARBITRATED by nifty-ui (ADR-0018 made the phone the second
--- surface; the split made it the tenth) and this file only asks.
---
--- The rules that fall out of asking rather than taking:
---   - The chat input refuses to open while another surface holds focus.
---   - Another surface opening closes this one, via `focusAcquire`'s failure.
---   - Every exit path releases, through one function, including resource stop.
---
--- The chat LOG is the exception: it is always visible and never holds focus. A
--- chat you cannot read while walking is not a chat.

local RESOURCE = GetCurrentResourceName()

local Input = { open = false }

--- The shared focus broker. Fetched once: an export call per keystroke would be a
--- round trip for a decision that does not change between keypresses.
local Focus = exports['nifty-ui']

--- Ask the broker whether we may have the keyboard. Returns false if another
--- surface already holds it, which is a normal outcome and not an error.
local function acquire()
  local got = Focus:acquire(RESOURCE)
  return got == true
end

--- Hand it back. Safe to call when we never had it — the broker ignores a release
--- from a surface that does not hold focus, which is exactly what we want here so
--- the close paths do not have to track state themselves.
local function release()
  Focus:release(RESOURCE)
end

--- Close the input, releasing focus, whatever route we got here by.
---
--- Every path out of the open state goes through this one function. That is the
--- only way to be sure there is no route that hides the box and forgets the focus.
local function closeInput()
  if not Input.open then return end

  Input.open = false
  release()
  SendNUIMessage({ action = 'chatInput', data = { open = false } })
end

--- Ask the NUI to show the input. Focus is granted BEFORE the NUI draws anything,
--- because a field that appears without focus is a field nobody can type into.
local function openInput()
  if Input.open then return end

  if not acquire() then
    -- Another surface owns the keyboard. Say so instead of silently doing nothing:
    -- a chat box that refuses to appear looks exactly like a broken key binding,
    -- and the player has no way to tell which it is.
    SendNUIMessage({
      action = 'chatSystem',
      data = { text = 'Ein anderes Fenster ist offen.' },
    })
    return
  end

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

--- The resource stopping must not leave a captured cursor behind. This is the one
--- handler that cannot wait for a UI event, because there will not be one.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  Input.open = false
  release()
end)

--- The broker holds a NAME, and this resource can be restarted while holding it.
--- `onClientResourceStop` in nifty-ui covers the case where WE are the one going
--- away, but this covers us coming BACK: clear the local flag so a fresh start does
--- not believe it already has focus.
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