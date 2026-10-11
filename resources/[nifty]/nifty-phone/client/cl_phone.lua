--- The phone handset (ADR-0018, ADR-0021).
---
--- This file is the **only** reason the phone is reachable. `server/phone.lua`
--- was already complete and fully tested while nothing on this side existed —
--- a module with no client handler is not implemented, it is just unreachable
--- code that happens to be green (see LEARNINGS.md).
---
--- What this file decides: whether the phone is open, and what the NUI is told.
--- What it never decides: whether a message may be sent, whether it is
--- addressed to a real character, or whether a report is legitimate. Those are
--- answered by `Phone.*` on the server, and every net event it sends carries no
--- authority at all.
---
--- The number on screen is the SERVER's number. There is no path by which this
--- file can change it, and the UI cannot supply one — `phoneSend` takes a number
--- the player typed and the server resolves it to a character itself.

local RESOURCE = GetCurrentResourceName()

--- Mirror of server truth, rebuilt on every push.
local State = {
  open = false,
  account = nil,
  inbox = {},
  unread = 0,
}

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------

local function push()
  SendNUIMessage({
    action = 'phone',
    data = {
      open = State.open,
      account = State.account,
      inbox = State.inbox,
      unread = State.unread,
    },
  })
end

--- The shared focus broker, and the only reason this file is allowed to touch the
--- keyboard at all. See resources/[nifty]/nifty-ui/client/cl_focus.lua.
---
--- `SetNuiFocus` is a single global client native shared by every NUI surface in
--- this project. Calling it directly here would work right up until a second
--- surface did the same, and then the player would be looking at the phone while
--- typing into the chat.
local Focus = exports['nifty-ui']

--- Focus and cursor move together and are released in the same order. Leaving the
--- cursor locked with the phone closed is the classic FiveM bug: the player can
--- still see it after closing the UI, and the only fix is a reconnect.
---
--- Opening ASKS rather than takes. The chat input holds the keyboard while somebody
--- is typing and must not silently lose it to a phone keypress, so `acquire` fails
--- and the phone simply does not open. That refusal is visible to the player
--- through the message the chat logs, not silent.
local function setOpen(open)
  if open then
    if not Focus:acquire(RESOURCE) then return end
  else
    Focus:release(RESOURCE)
  end

  State.open = open

  if open then
    -- Re-read on every open rather than trusting the last state. A message can
    -- have arrived while the phone was shut, and a phone that shows a stale inbox
    -- is worse than one that takes a frame to load.
    TriggerServerEvent('nifty:server:phoneInbox')
  else
    -- Messages are not marked read by closing the phone. Reading is an explicit
    -- act — opening the app — because a badge that clears itself on every key
    -- press is a badge that cannot be trusted.
    push()
  end
end

RegisterCommand('niftyphone', function()
  setOpen(not State.open)
end, false)

RegisterKeyMapping('niftyphone', 'Nifty Life — Telefon', 'keyboard', 'F4')

--- Escape must close the phone from inside NUI. FiveM delivers Escape as a key
--- event only when the page has focus, which is exactly when it matters.
RegisterCommand('niftyphoneclose', function()
  if State.open then setOpen(false) end
end, false)

--- The resource stopping must not leave a captured cursor behind. Release through
--- the broker, exactly as every other exit path does — never by calling the natives
--- here, because this file no longer has the right to.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  State.open = false
  Focus:release(RESOURCE)
end)

-- ---------------------------------------------------------------------------
-- Server pushes
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:client:phone', function(payload)
  if type(payload) ~= 'table' then return end

  State.account = payload.account
  State.inbox = payload.inbox or {}
  State.unread = tonumber(payload.unread) or 0

  push()
end)

--- The badge alone, so a message arriving is visible without opening anything.
--- The count is converted with `tonumber` because everything numeric off the
--- wire arrives as a string, and `"0"` is truthy in the same way `0` is (see
--- LEARNINGS.md — the Lua zero-is-truthy trap).
RegisterNetEvent('nifty:client:phoneUnread', function(count)
  State.unread = tonumber(count) or 0

  SendNUIMessage({ action = 'phoneBadge', data = { unread = State.unread } })
  push()
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

RegisterNUICallback('phoneClose', function(_, cb)
  setOpen(false)
  cb({ ok = true })
end)

--- Nothing is validated here beyond shape. An empty body is sent to the server
--- and refused there, because a client-side check that a cheater can skip is
--- decoration, not a rule.
RegisterNUICallback('phoneSend', function(data, cb)
  TriggerServerEvent('nifty:server:phoneSend', tostring(data.number or ''), tostring(data.body or ''))
  cb({ ok = true })
end)

RegisterNUICallback('phoneRead', function(_, cb)
  TriggerServerEvent('nifty:server:phoneRead')
  cb({ ok = true })
end)

RegisterNUICallback('phoneClear', function(data, cb)
  TriggerServerEvent('nifty:server:phoneClear', tostring(data.id or ''))
  cb({ ok = true })
end)

RegisterNUICallback('phoneReport', function(data, cb)
  TriggerServerEvent('nifty:server:phoneReport', tostring(data.id or ''), tostring(data.reason or ''))
  cb({ ok = true })
end)

--- Marks a message read without opening it. There is no server event for this
--- yet — `phoneRead` marks ALL of them — so it currently does the same thing.
--- Kept as a separate callback so the server can grow a per-message event
--- without the UI having to change.
RegisterNUICallback('phoneOpenMessage', function(_, cb)
  TriggerServerEvent('nifty:server:phoneRead')
  cb({ ok = true })
end)

exports('isOpen', function() return State.open end)