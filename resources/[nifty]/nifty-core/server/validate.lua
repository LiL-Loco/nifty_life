-- Input validation (ADR-0007, ADR-0017).
--
-- Every value that crosses the client boundary passes through here before it
-- reaches a query or the database. Nothing in this project concatenates a
-- client value into SQL, and nothing stores a client value without a check
-- first. Those two rules together are what "the client is untrusted" means in
-- practice.

Validate = {}

-- Characters. Names are stored for display and filtering, so they are kept to
-- a conservative charset: no angle brackets, no quotes, no control characters.
-- That keeps them safe in NUI without needing to escape at every render site.
--
-- The pattern asserts the CHARACTER SET only. The length is enforced by the
-- explicit `#value` check below, and deliberately not by a `{2,32}` repetition
-- in the pattern: pattern repetition quantifiers behaved inconsistently across
-- the Lua builds this project has been checked against (stock Lua 5.4.6 refused
-- `a{2}` in the container used by the headless harness). Splitting the two
-- concerns is clearer anyway, and it removes a dependency on a feature whose
-- behaviour was never in doubt on the real target but could not be verified.
local NAME_PATTERN = "^[%w'%- ]+$"
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

-- Validate a world position { x = number, y = number, z = number }.
--
-- GTA V bounds are wide; the limits below are a sanity net against a
-- malicious client claiming to be at 1e6, 1e6, 1e6 and pinning a future
-- resume there. The hard cap on map size is ~ +/- 10 000, so these bounds
-- leave the entire legal world inside.
function Validate.position(value)
  if value == nil then return nil end
  if type(value) ~= 'table' then return nil, 'position must be an object' end
  local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
  if x == nil or y == nil or z == nil then
    return nil, 'position coordinates must be numbers'
  end
  if x < -12000 or x > 12000 or y < -12000 or y > 12000 or z < -500 or z > 4000 then
    return nil, 'position out of GTA V bounds'
  end
  return { x = x, y = y, z = z }
end

-- Validate one appearance slot: { collection = string, drawable = int, texture = int }
--
-- Returns `true, cleanedSlot` or `nil, errorMessage`. The two-value shape is
-- load-bearing: an earlier version returned the cleaned table ALONE, and the
-- callers read it as `local ok, clean = validateSlot(...)`. `ok` became the
-- table (truthy, so no error was raised) and `clean` was nil — so every
-- component and every prop was validated and then stored as nil. Characters
-- were created with a model and nothing else, and the appearance editor looked
-- like it was doing nothing. Always return the success flag first.
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

  return true, { collection = collection, drawable = drawable, texture = texture }
end

-- A finite number, or nil.
--
-- `tonumber('abc')` is nil and `tonumber('nan')` is a number that is not equal to
-- itself. Both would sail through a range check as false-positive "valid" values
-- if written as `if n < min or n > max`, because every comparison with NaN is
-- false - so the check has to be positive, not negative.
local function finiteNumber(value)
  local n = tonumber(value)
  if n == nil then return nil end
  if n ~= n then return nil end          -- NaN
  if n == math.huge or n == -math.huge then return nil end
  return n
end

-- A whole number inside an inclusive range, or nil.
local function boundedInt(value, min, max)
  local n = finiteNumber(value)
  if n == nil or n ~= math.floor(n) then return nil end
  if n < min or n > max then return nil end
  return n
end

-- A float inside an inclusive range, or nil.
local function boundedFloat(value, min, max)
  local n = finiteNumber(value)
  if n == nil or n < min or n > max then return nil end
  return n
end

-- Face sliders: a sparse map `{ ['0'] = -0.35, ['7'] = 0.8, ... }`.
--
-- SPARSE on purpose. Twenty sliders at full precision for every character is a
-- stored blob nobody reads, and the ones nobody touched must not be able to
-- disagree with the ped. Only the keys the player actually moved survive.
function Validate.faceFeatures(value)
  local out = {}
  if type(value) ~= 'table' then return out end

  for id, raw in pairs(value) do
    local index = boundedInt(id, 0, AppearanceConfig.MAX_FACE_FEATURE)
    local slider = boundedFloat(raw, -1.0, 1.0)
    if index and slider then
      out[tostring(index)] = slider
    end
  end

  return out
end

-- Head overlays: `{ ['1'] = { style=, opacity=, colourType=, colour=, secondColour= } }`.
--
-- A malformed overlay is DROPPED rather than rejected. The difference matters:
-- an overlay the player never touched is simply absent, and refusing to save the
-- whole appearance because one unrecognised slot came in would mean a client on
-- an older build can never change its hair. What is stored is always rebuilt
-- from these fields, so an entry that cannot be understood contributes nothing.
function Validate.headOverlays(value)
  local out = {}
  if type(value) ~= 'table' then return out end

  for id, raw in pairs(value) do
    local index = boundedInt(id, AppearanceConfig.MIN_OVERLAY_ID, AppearanceConfig.MAX_OVERLAY_ID)

    if index and type(raw) == 'table' then
      local style = boundedInt(raw.style, 0, AppearanceConfig.MAX_OVERLAY_STYLE)
      if style then
        -- Opacity defaults to 1.0 rather than 0.0: a style with no stated opacity
        -- is a style the player wants at full strength, and defaulting to
        -- invisible would silently erase a beard.
        local opacity = boundedFloat(raw.opacity, 0.0, 1.0) or 1.0
        local colourType = boundedInt(raw.colourType, 0, AppearanceConfig.MAX_OVERLAY_COLOUR_TYPE) or 1
        local colour = boundedInt(raw.colour, 0, AppearanceConfig.MAX_OVERLAY_COLOUR) or 0
        local second = boundedInt(raw.secondColour, 0, AppearanceConfig.MAX_OVERLAY_COLOUR) or colour

        out[tostring(index)] = {
          style        = style,
          opacity      = opacity,
          colourType   = colourType,
          colour       = colour,
          secondColour = second,
        }
      end
    end
  end

  return out
end

-- Hair colour: primary and highlight, both from the hair palette.
function Validate.hairColour(value)
  if type(value) ~= 'table' then return nil end

  return {
    primary   = boundedInt(value.primary, 0, AppearanceConfig.MAX_OVERLAY_COLOUR) or 0,
    highlight = boundedInt(value.highlight, 0, AppearanceConfig.MAX_OVERLAY_COLOUR) or 0,
  }
end

-- A hair overlay: a facial decoration riding on top of a hairstyle.
--
-- `{ collection = <joaat>, preset = <joaat> }`. Both are 32-bit hashes, so the only
-- meaningful bound is "is this a number that fits in 32 unsigned bits". The server
-- cannot know whether the combination exists - see the note on `MAX_OVERLAY_STYLE`
-- in appearance_config. The creator resolves them through the tattoo-shop map and
-- a client that invents them gets a ped with no visible overlay, which is harmless.
function Validate.hairOverlay(value)
  if type(value) ~= 'table' then return nil end

  local collection = boundedInt(value.collection, 0, 0xFFFFFFFF)
  local preset = boundedInt(value.preset, 0, 0xFFFFFFFF)

  if collection and preset then
    return { collection = collection, preset = preset }
  end

  return nil
end

-- Tattoos, as a LIST rather than a map by slot.
--
-- A ped can wear several at once - they are facial decorations, and each call to
-- the native adds one without clearing the others. A map keyed by body zone would
-- be tidier and wrong: the game allows more than one per zone, and a map would
-- silently drop one of them.
--
-- The collection is checked against the allowlist, which makes this stronger than
-- the head overlays above: a client cannot name a collection the server has never
-- heard of. The preset is still only range-checked - it is a joaat hash and the
-- server has no table to look it up in.
function Validate.tattoos(value)
  if type(value) ~= 'table' then return {} end

  local out = {}
  for _, entry in ipairs(value) do
    if #out >= AppearanceConfig.MAX_TATTOOS then break end

    if type(entry) == 'table'
      and type(entry.collection) == 'string'
      and AppearanceConfig.ALLOWED_TATTOO_COLLECTIONS[entry.collection]
    then
      local preset = boundedInt(entry.preset, 0, 0xFFFFFFFF)
      if preset then
        out[#out + 1] = { collection = entry.collection, preset = preset }
      end
    end
  end

  return out
end

-- Eye colour index.
function Validate.eyeColour(value)
  local colour = boundedInt(value, 0, AppearanceConfig.MAX_EYE_COLOUR)
  return colour or 0
end

-- Head blend: three presets and how much of each.
--
-- `SetPedHeadBlendData` takes THREE form presets, not two - mother, father and a
-- third, which is how a face can show all three at once. What it does not have
-- is three independent weights: the engine derives them from two numbers plus a
-- third blend, so the weights a player asks for have to be converted on the way
-- in. See `shapeMix` in nifty-world/client/cl_identity.lua, which is the one
-- place that conversion happens.
--
-- The weights are stored as the player set them, 0..1 and unnormalised. Storing
-- the engine's derived numbers instead would make the database disagree with
-- every slider on the menu.
--
-- `skinTone` is the mix between the two SKIN presets. It is separate from the
-- three shape weights because the engine gives it its own parameter - with the
-- third blend, which it shares, as the one unavoidable exception.
function Validate.headBlend(value)
  if type(value) ~= 'table' then return nil end

  return {
    mother = boundedInt(value.mother, 0, AppearanceConfig.MAX_HEADBLEND_PRESET) or 0,
    father = boundedInt(value.father, 0, AppearanceConfig.MAX_HEADBLEND_PRESET) or 0,
    third  = boundedInt(value.third, 0, AppearanceConfig.MAX_HEADBLEND_PRESET) or 0,

    motherWeight = boundedFloat(value.motherWeight, 0.0, 1.0) or 0.5,
    fatherWeight = boundedFloat(value.fatherWeight, 0.0, 1.0) or 0.5,
    thirdWeight  = boundedFloat(value.thirdWeight, 0.0, 1.0) or 0.0,

    skinTone = boundedFloat(value.skinTone, 0.0, 1.0) or 0.5,
  }
end

-- Validate a whole appearance object (ADR-0017).
--
-- Returns a *rebuilt* structure rather than the input: only known keys survive,
-- with values coerced and bounded. Anything unrecognised is dropped, so extra
-- fields a client sends have no way to persist.
function Validate.appearance(value)
  if value == nil then
    return {
      model = 'mp_m_freemode_01',
      components = {},
      props = {},
      faceFeatures = {},
      overlays = {},
    }
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

  -- Face sliders, overlays and hair colour.
  --
  -- These three CANNOT reject the appearance the way components and props do, and
  -- the difference is worth being explicit about. A component carries a
  -- collection name, so the server can look the name up in its allowlist and know
  -- whether that garment exists. A head overlay carries a bare integer index whose
  -- meaning is decided by the client's game files - the server cannot ask. So these
  -- are range-checked, not verified: a bound, not a guarantee.
  result.faceFeatures = Validate.faceFeatures(value.faceFeatures)
  result.overlays = Validate.headOverlays(value.overlays)
  result.hairColour = Validate.hairColour(value.hairColour)
  result.hairOverlay = Validate.hairOverlay(value.hairOverlay)
  result.eyeColour = Validate.eyeColour(value.eyeColour)
  result.headBlend = Validate.headBlend(value.headBlend)
  result.tattoos = Validate.tattoos(value.tattoos)

  return result
end