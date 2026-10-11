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
    jobs = State.jobs,
    jobCatalogue = State.jobCatalogue,
    shop = State.shop,
    properties = State.properties,
    vehicles = State.vehicles,
    panel = panelOpen and State.panel or nil,
  })
end

local function setPanel(name)
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
  local name = (argument or ''):lower()
  if name == '' or not State[name] then return setPanel(nil) end
  if panelOpen and State.panel == name then return setPanel(nil) end
  setPanel(name)
end, false)

RegisterKeyMapping('niftypanel inventory', 'Nifty Life — Inventar', 'keyboard', 'F1')
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