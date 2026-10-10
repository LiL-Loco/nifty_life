--- Input validation (ADR-0007, ADR-0017).
---
--- Every value that crosses the client boundary passes through here before it
--- reaches a query or the database. Nothing in this project concatenates a
--- client value into SQL, and nothing stores a client value without a check
--- first. Those two rules together are what "the client is untrusted" means in
--- practice.

Validate = {}

--- Characters. Names are stored for display and filtering, so they are kept to
--- a conservative charset: no angle brackets, no quotes, no control characters.
--- That keeps them safe in NUI without needing to escape at every render site.
local NAME_PATTERN = "^[%w'%- ]{2,32}$"
local DATE_PATTERN = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

function Validate.characterName(value)
  if type(value) ~= 'string' then return nil, 'name must be a string' end

  value = value:gsub('^%s+', ''):gsub('%s+$', '')
  if #value < 2 or #value > 32 then
    return nil, 'name must be 2-32 characters'
  end
  if not value:match(NAME_PATTERN) then
    return nil, 'name contains unsupported characters'
  end

  return value
end

function Validate.dateOfBirth(value)
  if value == nil or value == '' then return nil end
  if type(value) ~= 'string' then return nil, 'date of birth must be a string' end

  local y, m, d = value:match(DATE_PATTERN)
  if not y then return nil, 'date of birth must be YYYY-MM-DD' end

  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 or d < 1 or d > 31 then return nil, 'date of birth is not a real date' end

  -- 18 is the floor: a character must be able to do the things the game has
  -- them do. This is a content rule, not a legal one.
  local year, _, _ = os.date('*t').year, nil, nil
  local currentYear = tonumber(os.date('%Y'))
  if y > currentYear or (currentYear - y) < 18 then
    return nil, 'character must be at least 18'
  end

  return string.format('%04d-%02d-%02d', y, m, d)
end

function Validate.gender(value)
  if value ~= 'male' and value ~= 'female' and value ~= 'nonbinary' then
    return nil, 'unknown gender'
  end
  return value
end

function Validate.pedModel(value)
  if type(value) ~= 'string' then return nil, 'model must be a string' end
  if not AppearanceConfig.PED_MODELS[value] then
    return nil, 'unsupported ped model'
  end
  return value
end

function Validate.spawnPoint(value)
  if value == nil then return 'default' end
  if type(value) ~= 'string' then return nil, 'spawn point must be a string' end
  if not SpawnPoints[value] then return nil, 'unknown spawn point' end
  return value
end

--- Validate one appearance slot: { collection = string, drawable = int, texture = int }
local function validateSlot(slot, cfg)
  if type(slot) ~= 'table' then return nil, 'slot must be an object' end

  local collection = slot.collection
  local drawable   = tonumber(slot.drawable)
  local texture    = tonumber(slot.texture)

  if type(collection) ~= 'string' then return nil, 'collection must be a string' end
  if not AppearanceConfig.ALLOWED_COLLECTIONS[collection] then
    return nil, ('collection "%s" is not permitted'):format(collection)
  end
  if drawable == nil or drawable ~= math.floor(drawable) then
    return nil, 'drawable must be an integer'
  end
  if drawable < 0 or drawable > AppearanceConfig.MAX_DRAWABLE then
    return nil, 'drawable out of range'
  end
  if texture == nil or texture ~= math.floor(texture) then
    return nil, 'texture must be an integer'
  end
  if texture < 0 or texture > AppearanceConfig.MAX_TEXTURE then
    return nil, 'texture out of range'
  end

  return { collection = collection, drawable = drawable, texture = texture }
end

--- Validate a whole appearance object (ADR-0017).
---
--- Returns a *rebuilt* structure rather than the input: only known keys survive,
--- with values coerced and bounded. Anything unrecognised is dropped, so extra
--- fields a client sends have no way to persist.
function Validate.appearance(value)
  if value == nil then
    return { model = 'mp_m_freemode_01', components = {}, props = {} }
  end
  if type(value) ~= 'table' then return nil, 'appearance must be an object' end

  local model = Validate.pedModel(value.model)
  if not model then return nil, 'unsupported ped model' end

  local result = { model = model, components = {}, props = {} }

  if type(value.components) == 'table' then
    for id, slot in pairs(value.components) do
      local compId = tonumber(id)
      if compId and compId == math.floor(compId)
        and compId >= AppearanceConfig.MIN_COMPONENT_ID
        and compId <= AppearanceConfig.MAX_COMPONENT_ID then
        local ok, clean = validateSlot(slot, AppearanceConfig)
        if not ok then return nil, ('component %d: %s'):format(compId, clean) end
        result.components[tostring(compId)] = clean
      end
    end
  end

  if type(value.props) == 'table' then
    for id, slot in pairs(value.props) do
      local anchor = tonumber(id)
      if anchor and anchor == math.floor(anchor)
        and anchor >= AppearanceConfig.MIN_COMPONENT_ID
        and anchor <= AppearanceConfig.MAX_COMPONENT_ID then
        local ok, clean = validateSlot(slot, AppearanceConfig)
        if not ok then return nil, ('prop %d: %s'):format(anchor, clean) end
        result.props[tostring(anchor)] = clean
      end
    end
  end

  return result
end