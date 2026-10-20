--[[
  Client world state and the HUD bridge.

  This file holds **nothing that decides anything**. Money, inventory and jobs
  are whatever the server last said they are; this client stores them only to
  draw them. That is the whole reason the server pushes instead of answering
  questions: a cheating client can lie about what it displays, and cannot
  change what it owns.

  The one thing the client does decide is presentation state — which panel is
  open, what the player last typed. Nothing in `State` is ever sent back to the
  server as an authority.
]]

local RESOURCE = GetCurrentResourceName()

--- Mirror of server truth. Rebuilt wholesale on every push, never patched, so a
--- missed update cannot leave a stale field behind showing the wrong balance.
local State = {
  money = { cash = 0, bank = 0 },
  inventory = { items = {}, usedSlots = 0, totalSlots = 0, usedWeight = 0, maxWeight = 0 },
  -- The character's full appearance (model + every component / prop slot).
  -- Lives here so the inventory panel can render the OUTFIT section
  -- ("what you are currently wearing") without the server having to
  -- repeat the data on a separate channel. Refreshed when the wardrobe
  -- applies an outfit; today that path is implicit (Identity.saveCharacter
  -- updates characters.appearance, the next state push carries it).
  character = nil,
  jobs = {},
  jobCatalogue = {},
  shop = {},
  properties = {},
  vehicles = {},
  panel = nil,
}

local panelOpen = false

-- ---------------------------------------------------------------------------
-- NUI bridge
-- ---------------------------------------------------------------------------

local function sendToNui(name, payload)
  SendNUIMessage({ action = name, data = payload })
end

--- Push the entire visible state. One message per change rather than a message
--- per subsystem, so the UI never renders half an update.
local function render()
  sendToNui('render', {
    money = State.money,
    inventory = State.inventory,
    character = State.character,
    jobs = State.jobs,
    jobCatalogue = State.jobCatalogue,
    shop = State.shop,
    properties = State.properties,
    vehicles = State.vehicles,
    panel = panelOpen and State.panel or nil,
  })
end

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
-- flag set before it is still set afterwards. Chat is the sharp case: Input.open
-- stayed true, so openInput() returned early and T did nothing for the rest of
-- the session, with no error anywhere and nothing on screen to explain it.
--
-- The NUI message matters for the same reason: the CEF survives a soft drop
-- too, so without it the panel is still drawn on the other side of it.
AddEventHandler('playerDropped', function()
  focusHeld = false
  panelOpen = false
  State.panel = nil
  render()
end)

local function setPanel(name)
  -- Opening takes the keyboard; closing gives it back. This resource used to do
  -- neither: it rendered a modal panel — shop, jobs — on top of whatever was
  -- already there and assumed it had the keyboard. It did not. Pressing F2 with
  -- the character creator open drew the shop OVER the creator with no cursor and
  -- no way to click it, and the F2 that was supposed to dismiss it did nothing.
  --
  -- Acquiring is refused rather than stolen, so a panel can never appear on top
  -- of a surface that legitimately owns the keyboard. A refusal is normal — the
  -- chat input hits it too — and it is reported rather than swallowed, because a
  -- key that opens nothing is indistinguishable from a key that is not bound.
  if name ~= nil then
    acquireFocus()
  else
    releaseFocus()
  end

  panelOpen = name ~= nil
  State.panel = name
  render()
end

-- ---------------------------------------------------------------------------
-- Server pushes
-- ---------------------------------------------------------------------------

RegisterNetEvent('nifty:client:economy', function(balances)
  if type(balances) ~= 'table' then return end
  State.money = {
    cash = tonumber(balances.cash) or 0,
    bank = tonumber(balances.bank) or 0,
  }
  render()
end)

RegisterNetEvent('nifty:client:inventory', function(view)
  if type(view) ~= 'table' then return end
  State.inventory = view
  render()
end)

RegisterNetEvent('nifty:client:jobs', function(list)
  if type(list) ~= 'table' then return end
  State.jobs = list
  render()
end)

--- The full job roster. Separate from `nifty:client:jobs`, which is only what
--- this character has signed up for — the difference matters, because a client
--- that merged them could never offer a first job.
RegisterNetEvent('nifty:client:jobCatalogue', function(list)
  if type(list) ~= 'table' then return end
  State.jobCatalogue = list
  render()
end)

RegisterNetEvent('nifty:client:shop', function(list)
  if type(list) ~= 'table' then return end
  State.shop = list
  render()
end)

RegisterNetEvent('nifty:client:properties', function(list)
  if type(list) ~= 'table' then return end
  State.properties = list
  render()
end)

RegisterNetEvent('nifty:client:vehicles', function(list)
  if type(list) ~= 'table' then return end
  State.vehicles = list
  render()
end)

-- Track the character's appearance so the inventory panel can show what
-- the player is currently wearing in the OUTFIT section. The server
-- ships this in nifty:client:enterWorld and on every save.
RegisterNetEvent('nifty:client:enterWorld', function(data)
  if type(data) ~= 'table' then return end
  -- The shape carries character with an appearance sub-object.
  if type(data.character) == 'table' then
    State.character = data.character
    render()
  end
end)

RegisterNetEvent('nifty:client:character', function(character)
  if type(character) ~= 'table' then return end
  State.character = character
  render()
end)

--- Result of the last action. A short-lived toast — it is a confirmation, not a
--- channel, so it must not sit on screen pretending to be current state.
RegisterNetEvent('nifty:client:result', function(result)
  if type(result) ~= 'table' then return end

  sendToNui('result', {
    ok = result.ok == true,
    message = tostring(result.message or ''),
  })
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

RegisterNUICallback('closePanel', function(_, cb)
  setPanel(nil)
  cb({ ok = true })
end)

RegisterNUICallback('buy', function(data, cb)
  TriggerServerEvent('nifty:server:buy', data.code, tonumber(data.quantity) or 1)
  cb({ ok = true })
end)

RegisterNUICallback('sell', function(data, cb)
  TriggerServerEvent('nifty:server:sell', data.code, tonumber(data.quantity) or 1)
  cb({ ok = true })
end)

RegisterNUICallback('deposit', function(data, cb)
  TriggerServerEvent('nifty:server:deposit', tonumber(data.amount))
  cb({ ok = true })
end)

RegisterNUICallback('withdraw', function(data, cb)
  TriggerServerEvent('nifty:server:withdraw', tonumber(data.amount))
  cb({ ok = true })
end)

RegisterNUICallback('jobJoin', function(data, cb)
  TriggerServerEvent('nifty:server:jobJoin', data.code)
  cb({ ok = true })
end)

RegisterNUICallback('jobLeave', function(data, cb)
  TriggerServerEvent('nifty:server:jobLeave', data.code)
  cb({ ok = true })
end)

RegisterNUICallback('dutyStart', function(data, cb)
  TriggerServerEvent('nifty:server:dutyStart', data.code)
  cb({ ok = true })
end)

RegisterNUICallback('dutyEnd', function(data, cb)
  TriggerServerEvent('nifty:server:dutyEnd', data.code)
  cb({ ok = true })
end)

RegisterNUICallback('useItem', function(data, cb)
  TriggerServerEvent('nifty:server:useItem', data.code, tonumber(data.quantity) or 1)
  cb({ ok = true })
end)

RegisterNUICallback('moveItem', function(data, cb)
  TriggerServerEvent('nifty:server:moveItem', tonumber(data.from), tonumber(data.to))
  cb({ ok = true })
end)

RegisterNUICallback('acquireProperty', function(data, cb)
  TriggerServerEvent('nifty:server:acquireProperty', data.id)
  cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- Commands and keys
-- ---------------------------------------------------------------------------

--- F1 inventory · F2 shop · F3 jobs — bound via RegisterKeyMapping below rather
--- than a raw key table, so a player can rebind them in the FiveM settings menu.

RegisterCommand('niftypanel', function(_, argument)
  -- FiveM sometimes passes the argument as a table (when the command
  -- framework can't parse the typed input as a string), so the type
  -- check is not paranoia - it was the source of a real crash.
  if type(argument) ~= 'string' then argument = '' end
  local name = argument:lower()
  if name == '' or not State[name] then return setPanel(nil) end
  if panelOpen and State.panel == name then return setPanel(nil) end
  setPanel(name)
end, false)

-- NOTE: 'inventory' is no longer a panel here. nifty-inventory has its own
-- ui_page now and binds F1 directly via RegisterKeyMapping in its own
-- client script (client/cl_inventory.lua).
RegisterKeyMapping('niftypanel shop', 'Nifty Life — Shop', 'keyboard', 'F2')
RegisterKeyMapping('niftypanel jobs', 'Nifty Life — Jobs', 'keyboard', 'F3')
RegisterKeyMapping('niftyclose', 'Nifty Life — Panel schließen', 'keyboard', 'F5')

RegisterCommand('niftyclose', function()
  setPanel(nil)
end, false)

--- Pull the current state on entry and on respawn. The server pushes on entry,
--- but a resource restart or a reconnect race can leave the HUD blank, and a
--- blank HUD is indistinguishable from a broken server to the person looking
--- at it.
RegisterNetEvent('nifty:client:worldReady', function()
  TriggerServerEvent('nifty:server:requestState')
end)

AddEventHandler('onClientResourceStart', function(resource)
  if resource ~= RESOURCE then return end
  TriggerServerEvent('nifty:server:requestState')
end)

--- Nothing in this file is a decision, so a diagnostic print of the mirrored
--- state is safe — and it is the fastest way to tell "the server is wrong" from
--- "the client is not drawing it".
RegisterCommand('niftystate', function()
  print(('[%s] money: %s cash / %s bank · %d item(s) · %d job(s)'):format(
    RESOURCE,
    tostring(State.money.cash), tostring(State.money.bank),
    #State.inventory.items, #State.jobs))
end, true)

exports('state', function() return State end)