--[[
  verify_appearance_config.lua — the two directions of the model table.

  Run it:
      lua resources/[nifty]/nifty-core/tests/verify_appearance_config.lua

  WHY IT EXISTS
  -------------
  `AppearanceConfig.PED_MODELS` is keyed by MODEL and valued by GENDER:

      PED_MODELS = { mp_m_freemode_01 = 'male', mp_f_freemode_01 = 'female' }

  and the server read it the other way round - `PED_MODELS[character.gender]` -
  which answers nil for every gender in the game. The fallback then took the
  GENDER where it expected a model, and every character save was refused:

      [nifty-core] refused to save appearance for a92f02e4-...: unsupported ped model

  No character had ever been able to keep an appearance, and the message that
  said so was in the server log only.

  The two directions are not interchangeable, and the only thing that keeps
  them apart is a test that says which is which. The file itself is plain Lua
  with no natives in it, so it loads in a bare interpreter.
]]

local here = arg[0]:match('^(.*)[/\\][^/\\]-$') or '.'
dofile(here .. '/../shared/appearance_config.lua')

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

print('== AppearanceConfig: die zwei Richtungen ==')

-- 1. THE DIRECTION THAT WAS READ WRONG.
--
-- A gender lookup on PED_MODELS answers nil. That is not a bug in the table -
-- it is what the table is - and it is the exact thing the server did.
check('PED_MODELS ist nach MODELL sortiert',
  AppearanceConfig.PED_MODELS['mp_m_freemode_01'] == 'male',
  tostring(AppearanceConfig.PED_MODELS['mp_m_freemode_01']))
check('ein Geschlecht ist KEIN Schluessel von PED_MODELS',
  AppearanceConfig.PED_MODELS['male'] == nil,
  tostring(AppearanceConfig.PED_MODELS['male']))

-- 2. THE DIRECTION THAT WAS MEANT.
check('PED_MODEL_BY_GENDER kennt male',
  AppearanceConfig.PED_MODEL_BY_GENDER['male'] == 'mp_m_freemode_01',
  tostring(AppearanceConfig.PED_MODEL_BY_GENDER['male']))
check('PED_MODEL_BY_GENDER kennt female',
  AppearanceConfig.PED_MODEL_BY_GENDER['female'] == 'mp_f_freemode_01',
  tostring(AppearanceConfig.PED_MODEL_BY_GENDER['female']))

-- 3. "nonbinary" has no model attached: the gender is a fact about the
--    player, the model is a fact about the body, and the database records
--    only the first one. So the player CHOOSES - and the choice is checked
--    against the same allowlist.
check('nonbinary hat kein Modell',
  AppearanceConfig.PED_MODEL_BY_GENDER['nonbinary'] == nil,
  tostring(AppearanceConfig.PED_MODEL_BY_GENDER['nonbinary']))

-- 4. THE ROUND TRIP.
--
-- Every model a gender maps to must be a model the table knows, or the
-- server would hand out a ped that the validation refuses.
local roundTrip = true
local detail = ''
for gender, model in pairs(AppearanceConfig.PED_MODEL_BY_GENDER) do
  if not AppearanceConfig.PED_MODELS[model] then
    roundTrip = false
    detail = ('%s -> %s ist kein bekanntes Model'):format(gender, model)
  end
end
check('jedes Model aus der Gender-Map ist ein bekanntes Model', roundTrip, detail)

-- 5. THE MAP IS DERIVED, NOT A SECOND LIST.
--
-- A model added to PED_MODELS has to follow on its own. If somebody writes
-- the gender map out by hand, the two can drift - and then a character can be
-- given a model the validation refuses.
local derived = true
for model, gender in pairs(AppearanceConfig.PED_MODELS) do
  if AppearanceConfig.PED_MODEL_BY_GENDER[gender] ~= model then
    derived = false
  end
end
check('die Gender-Map folgt PED_MODELS', derived)

print('')
print(('%d Pruefungen, %d Fehler'):format(checks, failures))
if failures > 0 then
  print('FEHLGESCHLAGEN')
  os.exit(1)
end
print('ALLE PRUEFUNGEN BESTANDEN')
