-- nifty-creator NUI driver.
--
-- Owns: the NUI page lifecycle (acquire/release focus, push open/refresh/close),
-- the RegisterNUICallback handlers for every user gesture in the NUI, and the
-- long-running helper threads (face-bone projection, parent-portrait render,
-- camera-orbit Q/E).
--
-- Does NOT own: state. cl_creator.lua is the data engine; this file is a thin
-- adapter. Every callback here either calls a public helper from cl_creator.lua
-- (openCreator / closeCreator / setFeature / setSlot / ...), or it does the
-- native call itself (e.g. SetPedHairColor for hair colour channel change) and
-- then calls refresh() to push the new state back.

local RESOURCE = GetCurrentResourceName()

-- Forward declarations for helpers defined in cl_creator.lua. These are the
-- single source of truth for state mutations; cl_nui.lua never writes
-- `face.*` / `selection.*` directly.
local api = {
  openCreator      = function(...) return exports[RESOURCE]:openCreator(...) end,
  closeCreator     = function(...) return exports[RESOURCE]:closeCreator(...) end,
  isCreatorOpen    = function(...) return exports[RESOURCE]:isCreatorOpen(...) end,
  setFeature       = function(...) return exports[RESOURCE]:setFeature(...) end,
  setSlot          = function(...) return exports[RESOURCE]:setSlot(...) end,
  setOverlay       = function(...) return exports[RESOURCE]:setOverlay(...) end,
  setHairColour    = function(...) return exports[RESOURCE]:setHairColour(...) end,
  setHairOverlayOpacity = function(...) return exports[RESOURCE]:setHairOverlayOpacity(...) end,
  setEyeColour     = function(...) return exports[RESOURCE]:setEyeColour(...) end,
  setHeadBlend     = function(...) return exports[RESOURCE]:setHeadBlend(...) end,
  randomise        = function(...) return exports[RESOURCE]:randomise(...) end,
  randomiseAll     = function(...) return exports[RESOURCE]:randomiseAll(...) end,
  reset            = function(...) return exports[RESOURCE]:reset(...) end,
  submit           = function(...) return exports[RESOURCE]:submit(...) end,
  cancel           = function(...) return exports[RESOURCE]:cancel(...) end,
  zoomCamera       = function(...) return exports[RESOURCE]:zoomCamera(...) end,
  camYaw           = function(...) return exports[RESOURCE]:camYaw(...) end,
  pickModel        = function(...) return exports[RESOURCE]:pickModel(...) end,
  pickTattoo       = function(...) return exports[RESOURCE]:pickTattoo(...) end,
  removeTattoo     = function(...) return exports[RESOURCE]:removeTattoo(...) end,
  swapOverlayPalette = function(...) return exports[RESOURCE]:swapOverlayPalette(...) end,
  showSkinCam      = function(...) return exports[RESOURCE]:showSkinCam(...) end,
  getState         = function(...) return exports[RESOURCE]:getState(...) end,
  captureParentPortrait = function(...) return exports[RESOURCE]:captureParentPortrait(...) end,
  getTattooZones   = function(...) return exports[RESOURCE]:getTattooZones(...) end,
  getTattoosByZone = function(...) return exports[RESOURCE]:getTattoosByZone(...) end,
  projectFaceBones = function(...) return exports[RESOURCE]:projectFaceBones(...) end,
}

-- Resolve any nil forward declarations (export not yet wired by the engine)
-- at script load. If a function is missing, log and continue; the corresponding
-- NUI callback will refuse gracefully.
for k, v in pairs(api) do
  if type(v) ~= 'function' then
    print(('[cl_nui] export "%s" is not available yet (deferred). NUI will retry on first use.'):format(k))
  end
end

-- WHY EVERY WRAPPER ABOVE USES A COLON (`exports[RESOURCE]:name(...)`)
--
-- FiveM consumes an implicit first argument on an export call, so the spelling
-- decides whether your arguments arrive or vanish:
--
--     exports[RESOURCE].zoomCamera(...)   -- export receives (nil, ...)
--     exports[RESOURCE]:zoomCamera(...)   -- export receives (...)
--
-- With the dot form `zoomCamera` got `direction = nil` and threw "attempt to
-- perform arithmetic on a nil value"; `camYaw` lost its delta; `setFeature` lost
-- its id. The wrappers below all used it, so every parameterised button in the
-- panel was broken while every no-argument one happened to work — which is
-- exactly the "some buttons are dead" shape this had.
--
-- Same trap as the focus broker in nifty-core/cl_focus.lua, and the reason
-- nifty-chat used `Focus:acquire(...)` (colon) while three other callers used
-- `Focus.acquire(...)` (dot) and silently got nil.

local function tryCall(name, ...)
  local fn = api[name]
  if type(fn) ~= 'function' then
    print(('[cl_nui] tried to call missing export "%s"'):format(name))
    return nil
  end
  return fn(...)
end

-- Face-bone projection runs only while that panel is up; the flag lives here,
-- next to the focus state, because the playerDropped handler below has to clear
-- it and a local declared after its first use would silently become a global.
local faceBonesActive = false

-- ---------------------------------------------------------------- focus
-- NUI focus, owned entirely by this resource. Nothing about it is shared.
--
-- `SetNuiFocus` only does anything when the CALLING resource declares a
-- `ui_page`, because it acts on that resource's own CEF. This one declares one.
-- The focus broker in nifty-core could therefore never hand the keyboard over,
-- whatever it reported: it has no ui_page on purpose, so every native call it
-- issued was a silent no-op — it logged `granted`, returned true, and the player
-- got no cursor while every click punched their character through a wall. Thirty
-- consecutive `SetNuiFocus(true, true)` from that context read `focused=false`;
-- the same line here reads `focused=1` within 100 ms.
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
--
-- WHY THE OLD `callExport` HELPER IS GONE: it existed to absorb the implicit
-- argument shift on export calls — `Focus.acquire(R)` hands the export `(nil, R)`
-- and the resource name arrives nil, while `Focus:acquire(R)` hands it `(R)`.
-- Both compile and both return a boolean, so nothing at the call site said
-- "wrong". There are no export calls left to make.
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
  faceBonesActive = false
  SendNUIMessage({ action = 'creator:close' })
end)

-- ---------------------------------------------------------------- push helpers
local function buildPayload()
  local s = tryCall('getState')
  if type(s) ~= 'table' then return nil end
  return {
    currentModel      = s.currentModel,
    characterGender   = s.characterGender,
    scene             = s.scene,
    selection         = s.selection,
    face              = s.face,
    slots             = s.slots,
    labels            = s.labels,
    palettes          = s.palettes,
    hairOverlayState  = s.hairOverlayState,
    modelIsUndecided  = s.modelIsUndecided,
    skinCam           = s.skinCam,
  }
end

-- ---------------------------------------------------------------- action names
-- WHY EVERY `action` BELOW CARRIES THE `creator:` PREFIX.
--
-- Each ui_page is its own CEF browser, so two resources do not share a frame —
-- but they DO share the `SendNUIMessage` channel, and every frame on the client
-- sees every message. A bare `action = 'open'` was therefore heard by
-- nifty-world as well, which unhides ITS `#creator` — a full character-creation
-- form, left over from before the creator became its own resource. That frame
-- composites ON TOP of this one, so the player saw a menu whose buttons did
-- nothing: the buttons belonged to the panel underneath, and the clicks went to
-- the one above.
--
-- The symptom points in three directions at once and none of them is where the
-- fault is: focus reports held (`IsNuiFocused` = 1), the page is provably alive
-- (a NUI callback round-trips), and the CSS has no overlay. `open`, `refresh`,
-- `close` and `error` all collided with nifty-world or nifty-inventory; all
-- creator actions are namespaced now so a frame only ever hears its own name.

local function sendOpen()
  acquireFocus()
  local payload = buildPayload()
  if not payload then return end
  SendNUIMessage({ action = 'creator:open', data = payload })

  -- Put the cursor over the panel. The panel is the right-hand 460px of the
  -- screen (style.css .cr-root: right: 0; width: 460px), and after
  -- SetNuiFocus(true, true) the cursor keeps wherever the mouse last was —
  -- which, having just come from the game world, is usually the middle of the
  -- screen. The player then clicks on what they believe is a button and hits
  -- the world behind the panel instead.
  --
  -- qb-clothing does the same thing (SetCursorLocation(0.9, 0.25) right after
  -- SetNuiFocus) and the position is the screen centre in NORMALISED
  -- coordinates: 0..1, 0 = top/left, 1 = bottom/right. 0.9/0.25 therefore lands
  -- in the upper area of that right-hand strip.
  SetCursorLocation(0.9, 0.25)
end

local function sendRefresh()
  if not focusHeld then return end
  local s = tryCall('getState')
  if type(s) ~= 'table' then return end
  SendNUIMessage({ action = 'creator:refresh', data = {
    selection = s.selection,
    face      = s.face,
    skinCam   = s.skinCam,
    slots     = s.slots,
  }})
end

-- Send a partial refresh with explicit keys (used by handlers that don't
-- need a full state dump).
local function sendPartialRefresh(t)
  if not focusHeld then return end
  SendNUIMessage({ action = 'creator:refresh', data = t })
end

local function sendClose()
  SendNUIMessage({ action = 'creator:close' })
  releaseFocus()
end

-- ---------------------------------------------------------------- face-bone projection thread
-- While the player is in the Gesichtszuege panel, a thread ticks the
-- 24 facial bones through GetWorldPositionOfEntityBone and
-- GetScreenCoordFromWorldCoord, then sends their screen positions to
-- the NUI every frame. The NUI positions 24 gold dots over the camera
-- viewport; the player can drag a dot to nudge the matching face
-- feature, which the NUI's onMove dispatches back as a setFeature
-- call.
--
-- 24 bones / frame * 8 bytes / bone = a few hundred bytes per push.
-- FiveM's CEF can sustain that easily at 60 fps.
local FACE_BONE_PUSH_MS = 1000 / 30  -- cap at 30 Hz to keep CPU in check

Citizen.CreateThread(function()
  while true do
    if faceBonesActive and focusHeld then
      local bones = tryCall('projectFaceBones')
      if type(bones) == 'table' and #bones > 0 then
        SendNUIMessage({ action = 'creator:faceBones', data = { bones = bones } })
      end
    end
    Citizen.Wait(FACE_BONE_PUSH_MS)
  end
end)

-- ---------------------------------------------------------------- callbacks
-- `fetchNui(name, body)` from the NUI hits `https://${GetParentResourceName()}/<name>`.
-- The handler receives the same body as a Lua table.

RegisterNUICallback('closePanel', function(data, cb)
  faceBonesActive = false
  tryCall('cancel')
  cb({ ok = true })
  -- closeCreator triggers 'nifty:client:enterWorld' or sends cancelCreator;
  -- both end with closeCreator which calls sendClose via a hook below.
end)

RegisterNUICallback('setFaceBonesActive', function(data, cb)
  faceBonesActive = (data and data.active == true)
  cb({ ok = true })
end)

RegisterNUICallback('getItemNames', function(data, cb)
  if not (data and data.kind and data.id) then cb({ ok = true }) return end
  local result = tryCall('getItemNames', data.kind, tonumber(data.id) or 0)
  if type(result) == 'table' then
    SendNUIMessage({
      action = 'creator:itemNames',
      data = { kind = data.kind, id = data.id, names = result },
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('setSlot', function(data, cb)
  if type(data) == 'table' and data.kind and data.id then
    tryCall('setSlot', data.kind, tonumber(data.id), data.slot or {})
  end
  cb({ ok = true })
end)

RegisterNUICallback('setFeature', function(data, cb)
  if type(data) == 'table' and data.id then
    tryCall('setFeature', tonumber(data.id), tonumber(data.value) or 0.0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setOverlay', function(data, cb)
  if type(data) == 'table' and data.id and type(data.overlay) == 'table' then
    tryCall('setOverlay', tonumber(data.id), data.overlay)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setHairColour', function(data, cb)
  if type(data) == 'table' and data.channel and data.index then
    tryCall('setHairColour', data.channel, tonumber(data.index) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setHairOverlayOpacity', function(data, cb)
  if type(data) == 'table' and data.opacity then
    tryCall('setHairOverlayOpacity', tonumber(data.opacity) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setEyeColour', function(data, cb)
  if type(data) == 'table' and data.index then
    tryCall('setEyeColour', tonumber(data.index) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('setHeadBlend', function(data, cb)
  if type(data) == 'table' then
    tryCall('setHeadBlend', data)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('randomise', function(_, cb)
  tryCall('randomise')
  sendRefresh()
  cb({ ok = true })
end)

RegisterNUICallback('randomiseAll', function(_, cb)
  tryCall('randomiseAll')
  sendRefresh()
  cb({ ok = true })
end)

RegisterNUICallback('reset', function(_, cb)
  tryCall('reset')
  sendRefresh()
  cb({ ok = true })
end)

RegisterNUICallback('submit', function(_, cb)
  tryCall('submit')
  cb({ ok = true })
end)

RegisterNUICallback('cancel', function(_, cb)
  tryCall('cancel')
  cb({ ok = true })
end)

RegisterNUICallback('zoomIn', function(_, cb)
  tryCall('zoomCamera', 1)
  cb({ ok = true })
end)

RegisterNUICallback('zoomOut', function(_, cb)
  tryCall('zoomCamera', -1)
  cb({ ok = true })
end)

RegisterNUICallback('camYaw', function(data, cb)
  if type(data) == 'table' and data.delta then
    tryCall('camYaw', tonumber(data.delta) or 0)
  end
  cb({ ok = true })
end)

-- Which close-up the skin cam should frame: 'face' for the panels that adjust
-- features, 'body' for everything else. The NUI re-sends this on every panel
-- change (app.js updateSkinCamState).
--
-- This callback was MISSING while the export below it existed since the NUI
-- migration. The consequence was not a dead button but a dead PAGE: the NUI
-- fired POST /showSkinCam on every panel switch, got a 404, and CEF treated the
-- failed request as a navigation — so the whole panel reloaded itself. It looks
-- exactly like "the menu is broken" from the outside and produces no Lua error,
-- because the 404 is answered by the NUI server, not by the resource.
RegisterNUICallback('showSkinCam', function(data, cb)
  if type(data) == 'table' and data.kind then
    tryCall('showSkinCam', tostring(data.kind))
  end
  cb({ ok = true })
end)

RegisterNUICallback('pickModel', function(data, cb)
  if type(data) == 'table' and data.model then
    tryCall('pickModel', data.model)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('pickTattoo', function(data, cb)
  if type(data) == 'table' and data.zoneId then
    tryCall('pickTattoo', tonumber(data.zoneId), data.collection, tonumber(data.preset) or 0)
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('removeTattoo', function(data, cb)
  if type(data) == 'table' and data.zoneId then
    tryCall('removeTattoo', tonumber(data.zoneId))
    sendRefresh()
  end
  cb({ ok = true })
end)

RegisterNUICallback('swapOverlayPalette', function(data, cb)
  if type(data) == 'table' and data.id then
    tryCall('swapOverlayPalette', tonumber(data.id), tonumber(data.paletteIndex) or 1)
    sendRefresh()
  end
  cb({ ok = true })
end)

-- ---------------------------------------------------------------- lazy fetches
RegisterNUICallback('getTattooZones', function(_, cb)
  local zones = tryCall('getTattooZones') or {}
  SendNUIMessage({ action = 'creator:tattooZones', data = { zones = zones } })
  cb({ ok = true })
end)

RegisterNUICallback('getTattoosByZone', function(data, cb)
  if type(data) == 'table' and data.zoneId then
    local t = tryCall('getTattoosByZone', tonumber(data.zoneId)) or {}
    SendNUIMessage({ action = 'creator:tattoosByZone', data = { zoneId = data.zoneId, tattoos = t } })
  end
  cb({ ok = true })
end)

RegisterNUICallback('requestParentPortraits', function(_, cb)
  -- Capture both parents in a hidden clone; reply with both base64 PNGs.
  local mother = tryCall('captureParentPortrait', 'mother')
  local father = tryCall('captureParentPortrait', 'father')
  SendNUIMessage({ action = 'creator:parentPortraits', data = {
    mother = type(mother) == 'string' and mother or '',
    father = type(father) == 'string' and father or '',
  }})
  cb({ ok = true })
end)

RegisterNUICallback('tickFaceBones', function(_, cb)
  local bones = tryCall('projectFaceBones') or {}
  SendNUIMessage({ action = 'creator:faceBones', data = { bones = bones } })
  cb({ ok = true })
end)

-- ---------------------------------------------------------------- server hooks
-- `nifty:client:enterWorld` is the canonical "creator finished" signal.
-- The server sends it after `nifty:server:finishAppearance` succeeds, or
-- immediately on a returning player who already has a character. Either
-- way, the creator must close.
AddEventHandler('nifty:client:enterWorld', function()
  if focusHeld then sendClose() end
end)

-- `nifty:client:openCreator` is the entry point. The server fires it once
-- the player has been authorised (no character yet, or force re-create).
-- The handler opens the camera, parks the player, then sends the NUI.
--
-- The RegisterNetEvent is load-bearing and it lives HERE, in the resource that
-- OWNS the event, not in nifty-world (which only reacts to it). FiveM keeps one
-- shared handler table per event name, and the server's TriggerClientEvent
-- arrives with eventSource 'net'; a table without `safeForNet` is DROPPED and
-- the client only prints "was not safe for net". That is a black creator with
-- no error anywhere else - the message looks like a server problem and is
-- entirely a client-side registration problem. Declaring it in the owner means
-- it does not matter whether nifty-world is started, restarted, or fails.
RegisterNetEvent('nifty:client:openCreator')
AddEventHandler('nifty:client:openCreator', function(data)
  tryCall('openCreator', data or {})
  sendOpen()
end)

-- closeCreator fires this after the data engine has torn down the
-- camera and state; the NUI driver is responsible for the NUI side
-- (close the panel, release focus).
AddEventHandler('nifty:client:closeCreator', function()
  sendClose()
end)

-- `nifty:client:creatorError` keeps the creator open so the player can
-- retry. The error message is forwarded to the NUI as a toast.
AddEventHandler('nifty:client:creatorError', function(message)
  SendNUIMessage({ action = 'creator:error', data = { message = message or '' } })
end)

-- Dropping focus on disconnect and on stop is handled by the focus block at the top
-- of this file, which registers those handlers itself. Repeating them here would be
-- a second source of truth for one flag.
