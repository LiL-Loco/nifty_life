--- Settings cache (ADR-0009).
---
--- Every tunable number is a row in `settings`, loaded once at start. Nothing
--- else in the codebase is allowed to hardcode a price, a wage or an interval —
--- which is what makes the first economy tuning pass a data change rather than
--- a code change.

local RESOURCE = GetCurrentResourceName()

local function coerce(row)
  local value = row.value
  local t = row.value_type

  if t == 'int' or t == 'decimal' then
    return tonumber(value) or 0
  elseif t == 'bool' then
    return value == '1' or value == 'true'
  end

  return value
end

function LoadSettings()
  local rows = Db.all('SELECT `key`, value, value_type FROM settings', {}, 'settings:load')
  local count = 0

  for _, row in ipairs(rows) do
    Nifty.Settings[row.key] = coerce(row)
    count = count + 1
  end

  print(('[%s] loaded %d settings'):format(RESOURCE, count))
end

--- Read a setting. Falls back to a caller-supplied default rather than nil,
--- because a missing key must not become a nil comparison three layers up.
function GetSetting(key, fallback)
  local value = Nifty.Settings[key]
  if value == nil then
    print(('[%s] WARNING: unknown setting "%s", using fallback'):format(RESOURCE, key))
    return fallback
  end
  return value
end

AddEventHandler('onResourceStart', function(resource)
  if resource ~= RESOURCE then return end

  -- oxmysql may still be starting; wait for it rather than racing it.
  if GetResourceState('oxmysql') ~= 'started' then
    SetTimeout(2000, function() LoadSettings() end)
  else
    LoadSettings()
  end
end)