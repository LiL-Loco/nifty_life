--[[
  Spawn-location picker, powered by the nifty-ui Lemon menu.

  Logik/Idee angelehnt an qb-spawn (qbcore-fivem/qb-spawn, GPL-3.0). Kein
  Code uebernommen - das Picker-Konzept ist allgemein, und das nifty-ui-
  Menuframework liefert das Backbone. Kamerafuehrung und Auswahlablauf
  sind eigenstaendig geschrieben.

  VERANTWORTLICHKEIT

  nifty-spawn macht NUR den Picker: Menu aufbauen, Kamerafluge, Auswahl
  zurueckgeben. Das eigentliche Spawnen (Modell, Aussehen, Teleport,
  Cfx-spawnmanager) macht nifty-world im Callback. So bleibt nifty-spawn
  klein und frei von Charakterdaten.

  VERTRAG
  exports.openSpawnPicker(locations, onConfirm)
    locations: array of { key, label, x, y, z, heading }
    onConfirm(x, y, z, heading): wird mit den Koordinaten der gewaehlten
      Location aufgerufen, NACHDEM das Menu geschlossen und die Kameras
      abgebaut sind. nil heisst "abgebrochen".
      nifty-world macht dann den Rest.
]]

local RESOURCE = GetCurrentResourceName()
--- Menu DSL lives in the same resource now (was nifty-ui, absorbed into nifty-core).
local Menu = exports['nifty-ui']

--- Module state. Set when openSpawnPicker is called, cleared on close.
local locations   = nil
local onConfirmCb = nil
local currentPick = nil
local confirmed   = false
local cam, cam2

--- Cinematic flight to a location. Two scripted cameras with interpolation:
--- high overview first, then a closer angled view pointing at the point.
--- Concept similar to qb-spawn, values and code are ours.
local function flyTo(loc)
  if cam then DestroyCam(cam, true) end
  if cam2 then DestroyCam(cam2, true) end

  cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
    loc.x, loc.y, loc.z + Spawn.CAM_HIGH_Z,
    -85.0, 0.0, 0.0,
    Spawn.CAM_FAR_FOV, false, 0)
  SetCamActive(cam, true)
  RenderScriptCams(true, false, 1, true, true)

  SetTimeout(Spawn.CAM_SETTLE_MS, function()
    cam2 = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
      loc.x, loc.y, loc.z + Spawn.CAM_NEAR_Z,
      -20.0, 0.0, loc.heading,
      Spawn.CAM_NEAR_FOV, false, 0)
    PointCamAtCoord(cam2, loc.x, loc.y, loc.z)
    SetCamActiveWithInterp(cam2, cam, Spawn.CAM_INTERP_MS, true, true)
  end)
end

local function destroyCams()
  RenderScriptCams(false, true, 0, true, true)
  if cam then SetCamActive(cam, false); DestroyCam(cam, true); cam = nil end
  if cam2 then SetCamActive(cam2, false); DestroyCam(cam2, true); cam2 = nil end
end

--- ---------------------------------------------------------------------------
--- The menu
--- ---------------------------------------------------------------------------

--- Build a nifty-ui menu for the given locations and open it.
local function buildAndOpen()
  local m = Menu:menu({
    title    = 'Wo willst du aufwachen?',
    subtitle = 'Waehle einen Ort. Die Kamera fliegt hin. Bestaetige unten.',
    onClose  = function(_)
      destroyCams()
      local cb = onConfirmCb
      onConfirmCb = nil
      locations = nil
      currentPick = nil
      if cb then
        if confirmed then
          cb(currentPick and currentPick.x or 0,
             currentPick and currentPick.y or 0,
             currentPick and currentPick.z or 0,
             currentPick and currentPick.heading or 0.0)
        else
          cb(nil)
        end
      end
      confirmed = false
    end,
  })

  --- One button per location. Selecting it flies the camera and updates
  --- the current pick; the menu stays open. The camera preview IS the
  --- selection feedback - no need to rebuild the menu to relabel rows.
  for _, loc in ipairs(locations) do
    Menu:button(m, loc.label, {
      onSelect = function()
        currentPick = loc
        flyTo(loc)
      end,
    })
  end

  Menu:button(m, 'Bestaetigen', {
    description = 'Hier aufwachen.',
    onSelect = function()
      confirmed = true
      Menu:closeMenu(RESOURCE, 'confirmed')
    end,
  })

  Menu:button(m, 'Abbrechen', {
    onSelect = function()
      confirmed = false
      Menu:closeMenu(RESOURCE, 'cancelled')
    end,
  })

  Menu:openMenu(RESOURCE, m)
end

--- ---------------------------------------------------------------------------
--- Export
--- ---------------------------------------------------------------------------

exports('openSpawnPicker', function(passedLocations, cb)
  if type(passedLocations) ~= 'table' or #passedLocations == 0 then
    print(('[%s] openSpawnPicker: no locations provided'):format(RESOURCE))
    return false
  end
  if type(cb) ~= 'function' then
    print(('[%s] openSpawnPicker: callback is not a function'):format(RESOURCE))
    return false
  end
  if Menu:isOpen() then
    print(('[%s] openSpawnPicker: another menu is open'):format(RESOURCE))
    return false
  end

  locations   = passedLocations
  onConfirmCb = cb
  currentPick = passedLocations[1]
  confirmed   = false

  buildAndOpen()
  flyTo(currentPick)
  return true
end)
