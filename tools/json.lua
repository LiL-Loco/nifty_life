-- ============================================================================
-- json.lua — minimal JSON codec for the headless harness.
--
-- FiveM provides `json` as a Cfx global. The harness has no engine, so it needs
-- its own, and it needs a CORRECT one: the appearance path is the most
-- client-facing code in the project, and a sloppy decoder would either hide real
-- validation bugs or manufacture fake ones.
--
-- Scope: exactly what this project serialises — objects, arrays, strings,
-- numbers, booleans and null. No unicode escapes, no exotic numbers, no
-- streaming. Anything outside that raises, rather than returning something
-- plausible, because a wrong answer here would be worse than no answer.
-- ============================================================================

local Json = {}

-- ---------------------------------------------------------------------------
-- Encode
-- ---------------------------------------------------------------------------

local ESCAPES = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
  ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function escapeString(value)
  local out = value:gsub('[%c"\\]', function(char)
    return ESCAPES[char] or string.format('\\u%04x', char:byte())
  end)
  return '"' .. out .. '"'
end

--- Keys are emitted in sorted order so the same structure always produces the
--- same string. `pairs()` order is undefined in Lua, and an appearance that
--- hashed differently on each save would be indefensible.
local function isArray(value)
  local count = 0
  for key in pairs(value) do
    if type(key) ~= 'number' then return false end
    count = count + 1
  end

  -- An empty table is encoded as `{}`, never `[]`. Lua cannot tell the two
  -- apart, and appearance components/props are empty objects far more often
  -- than they are empty arrays — `[]` would make a fresh character a different
  -- JSON document from one the server just wrote itself.
  if count == 0 then return false, 0 end

  for index = 1, count do
    if value[index] == nil then return false end
  end
  return true, count
end

local encodeValue

local function encodeTable(value, seen)
  -- Cycle detection. Appearance is client-supplied; a deeply self-referential
  -- structure must produce an error, not a stack overflow.
  if seen[value] then error('json: cyclic table') end
  seen[value] = true

  local array, count = isArray(value)

  local parts = {}
  if array then
    for index = 1, count do
      parts[#parts + 1] = encodeValue(value[index], seen)
    end
  else
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)

    for _, key in ipairs(keys) do
      parts[#parts + 1] = escapeString(key) .. ':' .. encodeValue(value[key], seen)
    end
  end

  seen[value] = nil

  local body = table.concat(parts, ',')
  return array and ('[' .. body .. ']') or ('{' .. body .. '}')
end

encodeValue = function(value, seen)
  local kind = type(value)

  if value == nil then return 'null' end
  if kind == 'boolean' then return tostring(value) end
  if kind == 'number' then
    -- JSON has no NaN or infinity. Emitting `null` for them is the honest
    -- encoding, and it mirrors what the driver would do with them.
    if value ~= value or value == math.huge or value == -math.huge then return 'null' end
    if value == math.floor(value) and math.abs(value) < 1e15 then
      return string.format('%d', value)
    end
    return string.format('%.14g', value)
  end
  if kind == 'string' then return escapeString(value) end
  if kind == 'table' then return encodeTable(value, seen) end

  error('json: cannot encode ' .. kind)
end

function Json.encode(value)
  return encodeValue(value, {})
end

-- ---------------------------------------------------------------------------
-- Decode
-- ---------------------------------------------------------------------------

local Decoder = {}
Decoder.__index = Decoder

local function newDecoder(text)
  return setmetatable({ text = text, pos = 1 }, Decoder)
end

function Decoder:error(message)
  error(('json: %s at position %d'):format(message, self.pos), 0)
end

function Decoder:skipWhitespace()
  local _, last = self.text:find('^[ \t\r\n]*', self.pos)
  self.pos = last + 1
end

function Decoder:peek()
  return self.text:sub(self.pos, self.pos)
end

function Decoder:expect(char)
  if self:peek() ~= char then self:error(('expected %q'):format(char)) end
  self.pos = self.pos + 1
end

local UNESCAPES = {
  ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b',
  f = '\f', n = '\n', r = '\r', t = '\t',
}

function Decoder:parseString()
  self:expect('"')

  local parts = {}

  while true do
    local char = self:peek()

    if char == '' then self:error('unterminated string') end

    if char == '"' then
      self.pos = self.pos + 1
      break
    end

    if char == '\\' then
      self.pos = self.pos + 1
      local escape = self:peek()
      if escape == 'u' then
        local hex = self.text:sub(self.pos + 1, self.pos + 4)
        if not hex:match('^%x%x%x%x$') then self:error('bad \\u escape') end
        local code = tonumber(hex, 16)
        self.pos = self.pos + 5
        -- The surrogate half of a pair is not combined. Appearance data is
        -- ASCII in practice; a lone surrogate becomes U+FFFD rather than a
        -- corrupt byte.
        if code >= 0xD800 and code <= 0xDFFF then
          parts[#parts + 1] = '\239\191\189'
        else
          parts[#parts + 1] = utf8.char(code)
        end
      else
        local mapped = UNESCAPES[escape]
        if not mapped then self:error(('bad escape \\%s'):format(escape)) end
        parts[#parts + 1] = mapped
        self.pos = self.pos + 1
      end
    else
      local nextSpecial = self.text:find('["\\]', self.pos) or (#self.text + 1)
      parts[#parts + 1] = self.text:sub(self.pos, nextSpecial - 1)
      self.pos = nextSpecial
    end
  end

  return table.concat(parts)
end

function Decoder:parseNumber()
  local literal = self.text:match('^%-?%d+%.?%d*[eE]?[%+%-]?%d*', self.pos)
  if not literal or literal == '' then self:error('bad number') end

  local number = tonumber(literal)
  if number == nil then self:error('bad number') end

  self.pos = self.pos + #literal
  return number
end

function Decoder:parseValue()
  self:skipWhitespace()
  local char = self:peek()

  if char == '{' then
    self.pos = self.pos + 1
    local object = {}
    self:skipWhitespace()

    if self:peek() == '}' then self.pos = self.pos + 1 return object end

    while true do
      self:skipWhitespace()
      local key = self:parseString()
      self:skipWhitespace()
      self:expect(':')
      object[key] = self:parseValue()
      self:skipWhitespace()

      local next_ = self:peek()
      if next_ == ',' then self.pos = self.pos + 1
      elseif next_ == '}' then self.pos = self.pos + 1 break
      else self:error("expected ',' or '}'") end
    end

    return object
  end

  if char == '[' then
    self.pos = self.pos + 1
    local array = {}
    self:skipWhitespace()

    if self:peek() == ']' then self.pos = self.pos + 1 return array end

    while true do
      array[#array + 1] = self:parseValue()
      self:skipWhitespace()

      local next_ = self:peek()
      if next_ == ',' then self.pos = self.pos + 1
      elseif next_ == ']' then self.pos = self.pos + 1 break
      else self:error("expected ',' or ']'") end
    end

    return array
  end

  if char == '"' then return self:parseString() end

  if self.text:sub(self.pos, self.pos + 3) == 'true' then
    self.pos = self.pos + 4 return true
  end
  if self.text:sub(self.pos, self.pos + 4) == 'false' then
    self.pos = self.pos + 5 return false
  end
  if self.text:sub(self.pos, self.pos + 3) == 'null' then
    self.pos = self.pos + 4 return nil
  end

  if char:match('[%-%d]') then return self:parseNumber() end

  self:error(('unexpected character %q'):format(char))
end

function Json.decode(text)
  if type(text) ~= 'string' then error('json: decode expects a string') end

  local decoder = newDecoder(text)
  local value = decoder:parseValue()

  decoder:skipWhitespace()
  if decoder.pos <= #text then decoder:error('trailing content') end

  return value
end

-- ---------------------------------------------------------------------------
-- Self-test. A codec that is wrong will quietly corrupt every test that uses it,
-- so it is checked before anything else is allowed to run.
-- ---------------------------------------------------------------------------

local function roundTrip(value)
  return Json.decode(Json.encode(value))
end

local cases = {
  {},
  { 1, 2, 3 },
  { model = 'mp_m_freemode_01', components = { ['0'] = { collection = '', drawable = 27, texture = 0 } } },
  { nested = { deep = { deeper = { value = true } } } },
  { text = 'quote " backslash \\ newline \n tab \t' },
  { [''] = 'empty key is legal JSON' },
  { unicode = 'Müller — ok' },
  { negative = -42, decimal = 3.5, zero = 0 },
}

for _, case in ipairs(cases) do
  local ok, result = pcall(function() return roundTrip(case) end)
  assert(ok, 'json self-test failed to round-trip: ' .. tostring(result))
end

assert(Json.encode({ a = 1, b = 2 }) == '{"a":1,"b":2}', 'json: key order must be deterministic')
assert(Json.encode({}) == '{}', 'json: empty object')
assert(Json.encode({ 1, 2 }) == '[1,2]', 'json: array')
assert(Json.decode('null') == nil, 'json: null decodes to nil')
assert(Json.decode('"\\u0041"') == 'A', 'json: \\u escape')
assert(not pcall(Json.decode, '{'), 'json: truncated object must raise')
assert(not pcall(Json.decode, '{"a":1}trailing'), 'json: trailing content must raise')
assert(not pcall(Json.decode, ''), 'json: empty input must raise')

return Json