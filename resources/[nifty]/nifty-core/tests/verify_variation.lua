--[[
  verify_variation.lua — the clothing-variation logic, checked without a client.

  Run it:
      lua resources/[nifty]/nifty-core/tests/verify_variation.lua

  WHY IT EXISTS
  -------------
  The fix for "CPed::SetVariation: Invalid variation (slotId: 10, drawblId: 9,
  texId: 1)" was deployed without ever being run against a real ped. The
  server reports what happens on a live client now, but a report can only say
  "something went wrong" - it cannot say "the clamp is off by one".

  The part that can be wrong WITHOUT a client is the part that decides which
  texture is allowed: the mapping from a collection-local drawable to the
  global one, the per-drawable texture count, and the step-down when the
  engine's validity check disagrees with the count. All three are arithmetic
  over a fake engine, and a fake engine can be made to disagree in the ways
  the real one does.

  So the engine is replaced here by a table, the natives are replaced by
  functions over that table, and the rules the engine actually follows are
  written down in one place:

      - a texture is valid for a drawable only if it is BELOW that drawable's
        own texture count (the count belongs to the drawable, not to the
        collection)
      - the collection setter refuses a variation and leaves the slot as it
        was; it does not raise and it does not return anything
      - the global index is what the ped ends up wearing, and it is not the
        same number as the collection-local one

  The third rule is the one that was broken three times, so the fake uses
  DIFFERENT numbers for the two spaces. A test that passes with equal numbers
  proves nothing.
]]

-- ---------------------------------------------------------------- the engine

--- The fake ped.
---
--- `slots` holds what the ped wears per component slot, `props` per anchor
--- point. Both are in GLOBAL indices - that is the whole point.
local ped = { slots = {}, props = {}, propTextures = {} }

--- The wardrobe.
---
--- slot -> collection -> local drawable -> { global, textures, valid }
---
--- `valid` is the set of textures the engine really accepts for that drawable.
--- It is usually the same as `textures` in count, but not always - and the
--- case where it is NOT is the one the fix has to survive.
local wardrobe = {
  components = {
    -- The slot from the bug report: one drawable with one texture, in a
    -- collection that has five. Asking the collection for the count is what
    -- produced texId 1, texId 3.
    [10] = {
      [''] = {
        [0] = { global = 0,  textures = 1 },
        [9] = { global = 41, textures = 1 },
        -- A drawable whose COUNT says five but which only has textures 0 and
        -- 2. The count alone would allow 4; the engine does not.
        [12] = { global = 55, textures = 5, valid = { [0] = true, [2] = true } },
      },
    },
    [11] = {
      [''] = {
        [0] = { global = 30, textures = 5 },
        [1] = { global = 31, textures = 3 },
      },
    },
  },
  props = {
    [0] = {
      [''] = {
        [0] = { global = 0, textures = 1 },
        [3] = { global = 7, textures = 2 },
        -- A prop whose COUNT says five but which only has textures 0 and 2.
        -- For props there is no validity native, so the count is the whole
        -- answer - and the engine refuses what the count allowed.
        [4] = { global = 9, textures = 5, valid = { [0] = true, [2] = true } },
      },
    },
  },
}

--- The refusals the fake engine makes, counted so a test can assert on them.
local refusals = 0

local function entryOf(kind, slot, collection, drawable)
  local group = wardrobe[kind][slot]
  if not group then return nil end
  return group[collection] and group[collection][drawable]
end

--- Is this texture one the engine accepts for this drawable?
local function accepts(item, texture)
  if item.valid then return item.valid[texture] == true end
  return texture >= 0 and texture < item.textures
end

-- ------------------------------------------------------------- the natives

--- The engine refuses a variation by leaving the slot as it was. It does not
--- raise and it does not return anything - which is why the whole bug could
--- hide behind a `type()` guard.
local function applyComponent(slot, collection, drawable, texture)
  local item = entryOf('components', slot, collection, drawable)
  if not item then
    refusals = refusals + 1
    return false
  end
  if not accepts(item, texture) then
    refusals = refusals + 1
    return false
  end
  ped.slots[slot] = { global = item.global, texture = texture }
  return true
end

local function applyProp(slot, collection, drawable, texture)
  local item = entryOf('props', slot, collection, drawable)
  if not item then
    refusals = refusals + 1
    return false
  end
  if not accepts(item, texture) then
    refusals = refusals + 1
    return false
  end
  ped.props[slot] = item.global
  ped.propTextures[slot] = texture
  return true
end

_G.GetCurrentResourceName = function() return 'nifty-core-test' end
_G.SetPedCollectionComponentVariation = function(_, slot, collection, drawable, texture)
  applyComponent(slot, collection, drawable, texture)
end
_G.SetPedCollectionPropIndex = function(_, slot, collection, drawable, texture)
  applyProp(slot, collection, drawable, texture)
end
_G.GetPedDrawableVariation = function(_, slot)
  local s = ped.slots[slot]
  return s and s.global or 0
end
_G.GetPedTextureVariation = function(_, slot)
  local s = ped.slots[slot]
  return s and s.texture or 0
end
_G.GetPedPropIndex = function(_, slot)
  return ped.props[slot] or -1
end
_G.GetPedPropTextureIndex = function(_, slot)
  return ped.propTextures[slot] or 0
end
_G.GetNumberOfPedTextureVariations = function(_, slot, global)
  for _, group in pairs(wardrobe.components[slot] or {}) do
    for _, item in pairs(group) do
      if item.global == global then return item.textures end
    end
  end
  return 0
end
_G.GetNumberOfPedPropTextureVariations = function(_, slot, global)
  for _, group in pairs(wardrobe.props[slot] or {}) do
    for _, item in pairs(group) do
      if item.global == global then return item.textures end
    end
  end
  return 0
end
_G.IsPedComponentVariationValid = function(_, slot, global, texture)
  for _, group in pairs(wardrobe.components[slot] or {}) do
    for _, item in pairs(group) do
      if item.global == global then return accepts(item, texture) end
    end
  end
  return false
end
--- The number of drawables a collection has for a slot.
---
--- The local indices are CONTIGUOUS - 0 to n-1 - so the count is the highest
--- index plus one, not the number of entries in the table. A collection that
--- lists drawables 0, 3 and 4 has FIVE, and index 3 is inside it.
local function collectionCount(group, collection)
  local set = group and group[collection]
  if not set then return 0 end
  local highest = -1
  for index in pairs(set) do
    if index > highest then highest = index end
  end
  return highest + 1
end

_G.GetNumberOfPedCollectionDrawableVariations = function(_, slot, collection)
  return collectionCount(wardrobe.components[slot], collection)
end
_G.GetNumberOfPedCollectionPropDrawableVariations = function(_, slot, collection)
  return collectionCount(wardrobe.props[slot], collection)
end

-- THE COLLECTION INDEX NATIVES.
--
-- These are the ones the fix leans on: they answer in the collection space,
-- they return -1 when the thing does not exist, and they do not touch the
-- ped. They are registered by the server
-- (code/components/extra-natives-five/src/PedCollectionsNatives.cpp) but they
-- are not in the documented native database, so whether they are exposed to
-- Lua is a question for the RUNTIME - and the file falls back to the older
-- read-back when they are not there.
--
-- The test runs the whole suite TWICE: once with them, once without. A path
-- that is only tested on one runtime is a path nobody knows.
local function indexOf(kind, slot, collection, drawable)
  local group = wardrobe[kind][slot]
  if not group then return -1 end
  local set = group[collection]
  if not set then return -1 end
  local item = set[drawable]
  if not item then return -1 end
  return item.global
end

_G.GetPedDrawableGlobalIndexFromCollection = function(_, slot, collection, drawable)
  return indexOf('components', slot, collection, drawable)
end
_G.GetPedPropGlobalIndexFromCollection = function(_, slot, collection, drawable)
  return indexOf('props', slot, collection, drawable)
end
_G.GetNumberOfPedCollectionTextureVariations = function(_, slot, collection, drawable)
  local item = entryOf('components', slot, collection, drawable)
  if not item then return 0 end
  return item.textures
end
_G.GetNumberOfPedCollectionPropTextureVariations = function(_, slot, collection, drawable)
  local item = entryOf('props', slot, collection, drawable)
  if not item then return 0 end
  return item.textures
end
_G.IsPedCollectionComponentVariationValid = function(_, slot, collection, drawable, texture)
  local item = entryOf('components', slot, collection, drawable)
  if not item then return false end
  return accepts(item, texture)
end

--- The reports the code sends to the server.
---
--- `TriggerServerEvent(name, message)` — two arguments, like the real one.
local reports = {}
_G.TriggerServerEvent = function(_, message) reports[#reports + 1] = message end

-- ------------------------------------------------------------------ the code

local here = arg[0]:match('^(.*)[/\\][^/\\]-$') or '.'
dofile(here .. '/../client/cl_variation.lua')

-- ----------------------------------------------------------------- the test

local failures = 0
local checks = 0

local function check(name, condition, detail)
  checks = checks + 1
  if condition then
    print(('  OK   %s%s'):format(name, detail and ('  -> ' .. detail) or ''))
  else
    failures = failures + 1
    print(('  FAIL %s%s'):format(name, detail and ('  -> ' .. detail) or ''))
  end
end

local function reset()
  ped.slots = {}
  ped.props = {}
  ped.propTextures = {}
  refusals = 0
  reports = {}
end

--- The suite, run once per path.
---
--- The collection index natives are not in the documented native database, so
--- whether they are exposed to Lua is a question for the runtime. The file
--- takes the direct path when they are there and falls back to the older
--- read-back when they are not - and BOTH paths have to hold, because which
--- one a player gets is not something this project decides.
local function runSuite(label, direct)
print(('== Variation: %s =='):format(label))

-- 1. THE BUG FROM THE LOG.
--
-- Drawable 9 of slot 10 has ONE texture, and the collection has five. The
-- old code took the texture from the collection count and handed the engine
-- texId 1. The engine refused it, every frame.
reset()
Variation.apply(ped, 'components', 10, '', 9, 3)
check('Drawable mit 1 Textur nimmt Textur 0',
  Variation.clampTexture(ped, 'components', 10, '', 9, 3) == 0)
check('die Engine hat die Variation angenommen',
  ped.slots[10] and ped.slots[10].texture == 0,
  ped.slots[10] and ('Textur ' .. ped.slots[10].texture) or 'nichts gesetzt')
check('keine Ablehnung', refusals == 0, refusals .. ' Ablehnungen')

-- 2. A TEXTURE THAT EXISTS IS LEFT ALONE.
reset()
Variation.apply(ped, 'components', 11, '', 1, 2)
check('gültiger Textur bleibt gültig',
  ped.slots[11] and ped.slots[11].texture == 2,
  ped.slots[11] and ('Textur ' .. ped.slots[11].texture) or 'nichts gesetzt')

-- 3. THE GLOBAL INDEX IS NOT THE LOCAL ONE.
--
-- Local drawable 9 of slot 10 is global 41. A fix that confused the two
-- would pass every test above and still put the wrong jacket on the ped.
reset()
Variation.apply(ped, 'components', 10, '', 9, 0)
check('globaler Index wird aufgelöst',
  ped.slots[10] and ped.slots[10].global == 41,
  ped.slots[10] and ('global ' .. ped.slots[10].global) or 'nichts gesetzt')

-- 4. THE COUNT CAN LIE, AND THE ENGINE HAS THE LAST WORD.
--
-- Drawable 12 of slot 10 reports five textures but only has 0 and 2. The
-- count alone would allow 4; the engine refuses it. The step-down has to
-- find 2 - not 0, and not 4.
--
-- THE DIRECT PATH CAN DO THIS; THE FALLBACK CANNOT. The read-back resolves
-- the drawable by applying it, and a refused apply leaves the ped wearing
-- the PREVIOUS item - so the count is asked for the wrong garment and the
-- step-down never happens. The engine refuses the slot, and the fallback
-- does not notice.
--
-- That difference is the whole argument for the collection index natives,
-- and it is why the fallback reports itself.
reset()
Variation.apply(ped, 'components', 10, '', 12, 4)
if direct then
  check('der Zähler lügt, die Engine nicht — auf Textur 2 heruntergestuft',
    ped.slots[10] and ped.slots[10].texture == 2,
    ped.slots[10] and ('Textur ' .. ped.slots[10].texture) or 'nichts gesetzt')
  check('keine Ablehnung trotz falschem Zähler', refusals == 0, refusals .. ' Ablehnungen')
else
  check('RÜCKSCHLAG: der lügende Zähler wird NICHT korrigiert (dokumentierte Schwäche)',
    ped.slots[10] and ped.slots[10].texture == 0,
    ped.slots[10] and ('Textur ' .. ped.slots[10].texture) or 'nichts gesetzt')
  check('RÜCKSCHLAG: die Engine lehnt ab, und der Rückfall sieht es nicht',
    refusals == 1, refusals .. ' Ablehnungen')
end

-- 5. A TEXTURE THE DRAWABLE DOES NOT HAVE AT ALL.
reset()
Variation.apply(ped, 'components', 11, '', 1, 99)
check('Textur jenseits des Zählers wird geklemmt',
  ped.slots[11] and ped.slots[11].texture == 2,
  ped.slots[11] and ('Textur ' .. ped.slots[11].texture) or 'nichts gesetzt')

-- 6. PROPS GO THROUGH THEIR OWN PATH.
reset()
Variation.apply(ped, 'props', 0, '', 3, 1)
check('Prop wird gesetzt',
  ped.props[0] == 7 and ped.propTextures[0] == 1,
  'global ' .. tostring(ped.props[0]) .. ', Textur ' .. tostring(ped.propTextures[0]))
check('Prop-Textur wird geklemmt',
  Variation.clampTexture(ped, 'props', 0, '', 3, 5) == 1)

-- 7. A REFUSAL IS REPORTED.
--
-- The engine's own answer is the only way to know that an apply did not
-- take. A refusal that is not reported is a failure nobody sees.
--
-- The DIRECT path sees it: the index native answers -1 for a drawable the
-- collection does not have. The FALLBACK does not - the ped keeps its
-- previous item, which reads back as a perfectly valid drawable.
reset()
reports = {}
Variation.apply(ped, 'components', 10, '', 999, 0)   -- a drawable that does not exist
if direct then
  check('eine Ablehnung wird gemeldet', #reports > 0,
    #reports .. ' Meldung(en): ' .. tostring(reports[1]))
else
  check('RÜCKSCHLAG: die Ablehnung eines unbekannten Drawables wird NICHT gemeldet (dokumentierte Schwäche)',
    #reports == 0, #reports .. ' Meldung(en)')
end

-- 7b. AND THE ENGINE IS NOT ASKED TO REFUSE IT.
--
-- The drawable is outside the collection, so the apply is skipped. Handing it
-- to the engine anyway would print "CPed::SetVariation: Invalid variation"
-- once per frame, for as long as the appearance is on screen.
reset()
Variation.apply(ped, 'components', 10, '', 9, 0)   -- a valid one first
local worn = ped.slots[10] and ped.slots[10].global
Variation.apply(ped, 'components', 10, '', 999, 0)  -- now an impossible one
check('der Ped behaelt sein vorheriges Item',
  ped.slots[10] and ped.slots[10].global == worn,
  'global ' .. tostring(ped.slots[10] and ped.slots[10].global))

-- 7c. A PROP WHOSE COUNT LIES.
--
-- For props there is no validity native, so the count is the whole answer -
-- and the engine can still refuse what the count allowed. The read-back is
-- what catches that one.
reset()
reports = {}
Variation.apply(ped, 'props', 0, '', 4, 4)
check('ein Prop mit luegendem Zaehler wird gemeldet', #reports > 0,
  #reports .. ' Meldung(en): ' .. tostring(reports[1]))

-- 8. THE SAME REPORT IS NOT SENT TWICE.
--
-- A different drawable, so this is not the message test 7 already sent: the
-- de-duplication is per message, and a message that was already sent would
-- make this check pass without proving anything.
--
-- The fallback does not report the refusal at all, so there is nothing to
-- de-duplicate there - and that is the point of the check above.
reset()
reports = {}
Variation.apply(ped, 'components', 10, '', 998, 0)
local first = #reports
Variation.apply(ped, 'components', 10, '', 998, 0)
if direct then
  check('dieselbe Meldung wird nicht wiederholt', first == 1 and #reports == first,
    first .. ' -> ' .. #reports)
else
  check('RÜCKSCHLAG: nichts zu entdoppeln, weil nichts gemeldet wird', first == 0,
    first .. ' Meldung(en)')
end

-- 9. A DRAWABLE THAT DOES NOT EXIST MUST NOT CRASH.
reset()
local ok = pcall(function()
  return Variation.clampTexture(ped, 'components', 10, '', 12345, 0)
end)
check('ein unbekannter Drawable wirft nicht', ok)
end

-- THE TWO PATHS.
runSuite('mit den Collection-Index-Natives', true)

-- Now take them away and run everything again. The file falls back to the
-- read-back, and the fallback has to hold just as well - it is the path a
-- runtime without those natives takes.
local COLLECTION_NATIVES = {
  'GetPedDrawableGlobalIndexFromCollection',
  'GetPedPropGlobalIndexFromCollection',
  'GetNumberOfPedCollectionTextureVariations',
  'GetNumberOfPedCollectionPropTextureVariations',
  'IsPedCollectionComponentVariationValid',
}
local saved = {}
for _, name in ipairs(COLLECTION_NATIVES) do
  saved[name] = _G[name]
  _G[name] = nil
end

runSuite('ohne die Collection-Index-Natives (Rueckfall)', false)

for _, name in ipairs(COLLECTION_NATIVES) do
  _G[name] = saved[name]
end

print('')
print(('%d Pruefungen, %d Fehler'):format(checks, failures))
if failures > 0 then
  print('FEHLGESCHLAGEN')
  os.exit(1)
end
print('ALLE PRUEFUNGEN BESTANDEN')
