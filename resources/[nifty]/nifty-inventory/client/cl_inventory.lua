--[[
  nifty-inventory client.

  Owns the inventory NUI's lifecycle: focus, push, close. The server
  fires `nifty:client:inventory` whenever the authoritative inventory
  changes (nifty-inventory/server/inventory.lua Inventory.push), and this
  client caches the latest payload. When the player opens the inventory,
  the cached payload is what the NUI receives - no extra round-trip.

  RegisterKeyMapping binds F1. FiveM allows multiple resources to bind
  the same key, but to avoid the nifty-world HUD also opening its panel
  on F1, the registration here is the canonical one. nifty-world's HUD
  keeps an inventory-shaped placeholder for client compatibility (legacy
  saves reference the F1 inventory key), but the actual UI lives here.
]]

local RESOURCE = GetCurrentResourceName()

-- Server pushes inventory payloads here. Same event nifty-world listens
-- to - both resources catch the broadcast.
local invState = {
  inventory = { items = {}, usedSlots = 0, totalSlots = 0, usedWeight = 0, maxWeight = 0 },
  character = nil,
}

RegisterNetEvent('nifty:client:inventory', function(view)
  if type(view) ~= 'table' then return end
  invState.inventory = view
end)

RegisterNetEvent('nifty:client:character', function(character)
  if type(character) ~= 'table' then return end
  invState.character = character
end)

RegisterNetEvent('nifty:client:enterWorld', function(data)
  if type(data) ~= 'table' or type(data.character) ~= 'table' then return end
  invState.character = data.character
end)

-- ---------------------------------------------------------------------------
-- Panel lifecycle
-- ---------------------------------------------------------------------------

local panelOpen = false

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
  SendNUIMessage({ action = 'inventory:close' })
end)

local function openPanel()
  if panelOpen then return end

  -- WHY THE CHECK, AND WHY IT IS FIRST
  --
  -- This used to be `panelOpen = true` followed by an acquire whose RESULT WAS
  -- THROWN AWAY. So pressing F1 while the creator or the chat held the keyboard
  -- raised the inventory frame on top of it anyway — visible, undismissable, with
  -- no cursor, because the holder had the keyboard and this panel had never
  -- asked for it. That is the same shape as the bug that cost the creator an
  -- evening: a panel that renders over a surface that owns the keyboard.
  --
  -- A refusal is normal, not an error: the chat input says so out loud. F1 is
  -- also the inventory key, so the closest equivalent here is a short message
  -- rather than silence — a key that does nothing looks exactly like a broken
  -- key binding and the player has no way to tell which it is.
  acquireFocus()
  panelOpen = true
  -- Push the cached state once on open. The NUI receives {action: 'inventory:open'}
  -- and snapshots the inventory state at that moment.
  --
  -- The prefix matters: action names are a shared channel and every resource's
  -- frame sees every message, so a bare 'open' also unhides the creator's panel.
  SendNUIMessage({
    action = 'inventory:open',
    data  = {
      inventory = invState.inventory,
      character = invState.character,
    },
  })
end

local function closePanel()
  if not panelOpen then return end
  panelOpen = false
  releaseFocus()
  SendNUIMessage({ action = 'inventory:close' })
end

RegisterCommand('+niftyinventory', function()
  if panelOpen then closePanel() else openPanel() end
end, false)
RegisterCommand('-niftyinventory', function() end, false)
RegisterKeyMapping('+niftyinventory', 'Nifty Life — Inventar', 'keyboard', 'F1')

-- ESC zum Schliessen: RegisterKeyMapping akzeptiert "ESC" nicht als
-- gueltigen Key-Namen (FiveM-Liste: nur A-Z, 0-9, F1-F12, Tab, Space,
-- Arrow, Numpad, Modifier). Der NUI-Keydown-Handler in ui/index.html
-- faengt die Taste selbst ab und ruft ueber das bestehende
-- closePanel-Callback closePanel() auf.

-- Direct command form for /inventory.
RegisterCommand('inventory', function()
  if panelOpen then closePanel() else openPanel() end
end, false)

-- Auto-refresh the NUI whenever the server pushes a fresh inventory state
-- while the panel is open. The server pushes on every purchase, equip,
-- transfer, etc.
AddEventHandler('nifty:client:inventory', function()
  if not panelOpen then return end
  SendNUIMessage({
    action = 'inventory:refresh',
    data  = {
      inventory = invState.inventory,
      character = invState.character,
    },
  })
end)
AddEventHandler('nifty:client:character', function()
  if not panelOpen then return end
  SendNUIMessage({
    action = 'inventory:refresh',
    data  = {
      inventory = invState.inventory,
      character = invState.character,
    },
  })
end)
AddEventHandler('nifty:client:enterWorld', function(data)
  if type(data) ~= 'table' or type(data.character) ~= 'table' then return end
  if not panelOpen then return end
  SendNUIMessage({
    action = 'inventory:refresh',
    data  = {
      inventory = invState.inventory,
      character = invState.character,
    },
  })
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

RegisterNUICallback('closePanel', function(_, cb)
  closePanel()
  cb({ ok = true })
end)

-- Item actions. The NUI sends the inventory row id; we look it up
-- locally to identify the item, and forward to the server which runs
-- the actual side-effect.
RegisterNUICallback('useItem', function(data, cb)
  TriggerServerEvent('nifty:server:useItem', {
    code     = data and data.code,
    quantity = (data and tonumber(data.quantity)) or 1,
    itemId   = data and data.itemId,
  })
  cb({ ok = true })
end)

RegisterNUICallback('discardItem', function(data, cb)
  TriggerServerEvent('nifty:server:discardItem', {
    code     = data and data.code,
    quantity = (data and tonumber(data.quantity)) or 1,
    itemId   = data and data.itemId,
  })
  cb({ ok = true })
end)

-- Split a stack into two. The NUI's quantity picker passes the qty
-- for the original row; the rest stays together as a fresh row.
RegisterNUICallback('splitStack', function(data, cb)
  TriggerServerEvent('nifty:server:splitStack', {
    itemId   = data and data.itemId,
    quantity = (data and tonumber(data.quantity)) or 1,
  })
  cb({ ok = true })
end)

-- Discard on the ground: server removes the inventory row AND spawns
-- a placeholder world prop at the player's current position. The
-- client passes its own coords so a hostile client cannot make items
-- rain from the sky at coordinates of its choosing.
RegisterNUICallback('discardItemOnGround', function(data, cb)
  local ped = PlayerPedId()
  if not ped or ped == 0 then return cb({ ok = false, reason = 'no ped' }) end
  local c = GetEntityCoords(ped)
  if not c or not c.x then return cb({ ok = false, reason = 'no coords' }) end
  TriggerServerEvent('nifty:server:discardItemOnGround', {
    code     = data and data.code,
    quantity = (data and tonumber(data.quantity)) or 1,
    itemId   = data and data.itemId,
    x        = c.x, y = c.y, z = c.z,
  })
  cb({ ok = true })
end)

-- Give flow: arm an item for giving, list nearby players, dispatch.
-- giveMode carries the inventory row until a target is picked or the
-- player dismisses.
local giveMode = nil  -- { row = { code, itemId, quantity }, targets = { ... } }

RegisterNUICallback('enterGiveMode', function(data, cb)
  if type(data) ~= 'table' then return cb({ ok = false }) end
  giveMode = {
    code     = data.code,
    itemId   = data.itemId,
    quantity = (tonumber(data.quantity)) or 1,
  }
  -- Refresh the target picker with current nearby players.
  local list = nearbyPlayers()
  cb({ ok = true, targets = list })
end)

RegisterNUICallback('exitGiveMode', function(_, cb)
  giveMode = nil
  cb({ ok = true })
end)

RegisterNUICallback('refreshTargets', function(_, cb)
  cb({ ok = true, targets = nearbyPlayers() })
end)

-- The selected target fires inventoryGive on the server. The actual
-- transfer / metadata stamp is server-side.
RegisterNUICallback('confirmGive', function(data, cb)
  if not giveMode then return cb({ ok = false, reason = 'no give mode' }) end
  if type(data) ~= 'table' or type(data.targetSrc) ~= 'number' then
    return cb({ ok = false, reason = 'no target' })
  end
  TriggerServerEvent('nifty:server:inventoryGive', {
    targetSrc = data.targetSrc,
    code      = giveMode.code,
    itemId    = giveMode.itemId,
    quantity  = giveMode.quantity,
  })
  giveMode = nil
  cb({ ok = true })
end)

-- -----------------------------------------------------------------------
-- Nearby players
--
-- Returns a list of { src, name, distance, position } for players
-- within NEARBY_RADIUS of the local player. Used by the target picker
-- overlay so the player can click a recipient.
local NEARBY_RADIUS = 5.0
local function nearbyPlayers()
  local list = {}
  local me = PlayerPedId()
  if not me or me == 0 then return list end
  local myPos = GetEntityCoords(me)
  if not myPos then return list end

  for _, srcStr in ipairs(GetPlayers()) do
    local candidate = tonumber(srcStr)
    if candidate and candidate ~= 0 then
      local ped = GetPlayerPed(candidate)
      if ped and ped ~= 0 then
        local p = GetEntityCoords(ped)
        if p then
          local dx, dy, dz = p.x - myPos.x, p.y - myPos.y, p.z - myPos.z
          local d = math.sqrt(dx * dx + dy * dy + dz * dz)
          if d <= NEARBY_RADIUS then
            list[#list + 1] = {
              src      = candidate,
              name     = GetPlayerName(candidate) or ('Spieler ' .. candidate),
              distance = d,
            }
          end
        end
      end
    end
  end
  return list
end

print(('[%s] inventory panel ready'):format(RESOURCE))
