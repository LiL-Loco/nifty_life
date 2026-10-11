--- Static clothing data, read from this resource's `data/` folder.
---
--- WHAT THIS IS
--- Item names, restriction tags and "best torso" mappings for the freemode peds.
--- They are keyed by GLOBAL drawable index - the number `GetNumDrawableVariations`
--- would return for a component set with `SetPedComponentVariation`, which is not
--- how this project stores anything (ADR-0017 stores collection + local drawable +
--- texture, because global indices shift with every Title Update).
---
--- So every lookup here goes through `globalFor()`, and that function is the whole
--- point of this file. See the note on it before changing anything.
---
--- WHY THE DATA LIVES IN THE REPOSITORY
--- These tables are derived from the game's own clothes metadata and GXT text. They
--- are vendored rather than generated at runtime because the source is inside RPF
--- archives, which are not a documented format and which nobody on this project has
--- tooling for. What they ARE is static game data, and static game data belongs with
--- the code that reads it rather than in a runtime dependency on someone's server.
---
--- The labels a player actually reads are NOT from here - those are ours, in
--- cl_labels.lua. This is only item names, tags and torso mappings.

local RESOURCE = GetCurrentResourceName()

--- A GLOBAL, like `AppearanceConfig` and `Nifty` in the rest of the project.
--- FiveM Lua's `require` exists but is not the convention here, and a resource
--- that reads its data through one loader and its labels through another is two
--- ways to be wrong.
GameData = {}

--- Loaded tables, by file name. `false` means "we tried and it was not there",
--- which is different from `nil` (not asked yet) and lets a missing file cost one
--- failed read instead of one per menu open.
local cache = {}

local function load(name)
  if cache[name] ~= nil then return cache[name] end

  local raw = LoadResourceFile(RESOURCE, ('data/%s.json'):format(name))
  if not raw or raw == '' then
    print(('[nifty-creator] data file missing: data/%s.json'):format(name))
    cache[name] = false
    return false
  end

  local ok, decoded = pcall(json.decode, raw)
  if not ok then
    print(('[nifty-creator] could not parse data/%s.json: %s'):format(name, tostring(decoded)))
    cache[name] = false
    return false
  end

  cache[name] = decoded
  return decoded
end

local function genderPrefix()
  return GameData.gender == 'female' and 'female_' or 'male_'
end

local function propPrefix()
  return GameData.gender == 'female' and 'props_female_' or 'props_male_'
end

--- Which file holds the names for a component.
---
--- Only ten of the thirteen freemode components have names, because those are the
--- ones the game ever sold. Slots 0, 9, 10 and 12 - masks are component 1, hats
--- are a PROP - simply have no table, and the menu falls back to a number.
local COMPONENT_FILE = {
  [1]  = 'masks',
  [2]  = 'hair',
  [3]  = 'torsos',
  [4]  = 'legs',
  [5]  = 'shoes',
  [7]  = 'accessories',
  [8]  = 'undershirts',
  [11] = 'tops',
}

local PROP_FILE = {
  [0] = 'hats',
  [1] = 'glasses',
  [2] = 'ears',
  [6] = 'watches',
  [7] = 'bracelets',
}

--- Set by the creator before anything is looked up.
function GameData.setGender(gender)
  if GameData.gender == gender then return end

  GameData.gender = gender

  -- The global index mapping is per ped model. The same collection and the same
  -- local drawable mean different things on a male and a female ped, so the whole
  -- cache has to go - keeping it would name a leather jacket "Long Bob".
  cache = {}
  GameData.globalMaps = {}
end

-- -------------------------------------------------------- global index map

--- local drawable -> global drawable, per slot and collection.
GameData.globalMaps = {}

local function mapKey(kind, id, collection)
  return table.concat({ kind, id, collection or '' }, ':')
end

--- The global index for a (slot, collection, local drawable) triple.
---
--- PROPS FIRST, because it is cheap and exact:
--- `GetPedPropGlobalIndexFromCollection` answers the question directly, for one
--- prop at a time, without touching the ped.
---
--- COMPONENTS HAVE NO SUCH NATIVE. There is `GetPedPropGlobalIndexFromCollection`
--- for props and nothing equivalent for components, so the only way to learn what
--- global index the engine assigned to a component drawable is to apply it and
--- read the result back with `GetPedDrawableVariation`.
---
--- That is why `mapCollection` exists and why it builds a whole collection at a
--- time: applying one drawable to read one index is two native calls, and doing it
--- for every drawable in a collection is exactly the same work plus the loop.
--- Doing it lazily per slider tick would instead mean re-applying on every nudge,
--- which streams drawables in and drops frames.
---
--- The ped is put back exactly as it was, whatever happens in between - the player
--- is looking at their own character while this runs.
local function mapCollection(ped, kind, id, collection, count)
  local key = mapKey(kind, id, collection)
  local cached = GameData.globalMaps[key]
  if cached then return cached end

  local map = {}

  -- The slot is restored from OUR state, not read back from the ped: there is no
  -- portable `GetPedComponentVariation` across builds, and the caller knows
  -- exactly what it set. Without a restore the ped would be left wearing the last
  -- item of the last collection we walked, and the player is looking at it.
  local savedCollection, savedDrawable, savedTexture =
    GameData.savedSlot and GameData.savedSlot(kind, id)

  for drawable = 0, count - 1 do
    if kind == 'components' then
      SetPedCollectionComponentVariation(ped, id, collection, drawable, 0, 0)
      map[drawable] = GetPedDrawableVariation(ped, id)
    else
      map[drawable] = GetPedPropGlobalIndexFromCollection(ped, id, collection)
    end
  end

  if savedCollection then
    if kind == 'components' then
      SetPedCollectionComponentVariation(ped, id, savedCollection, savedDrawable, savedTexture, 0)
    else
      SetPedCollectionPropIndex(ped, id, savedCollection, savedDrawable, savedTexture, false)
    end
  end

  GameData.globalMaps[key] = map
  return map
end

--- The global index for one item, or nil.
function GameData.globalFor(ped, kind, id, collection, drawable, count)
  local map = mapCollection(ped, kind, id, collection, count or (drawable + 1))
  return map[drawable]
end

-- ------------------------------------------------------------------ names

--- The name of one item, or nil when there is none.
---
--- `count` is the collection's drawable count. It is needed because the map is
--- built a whole collection at a time, and passing a count of 1 would cache a map
--- that only knows index 0 - which then looks like "no data" for every other item.
function GameData.itemName(isProp, id, collection, drawable, texture, count)
  local prefix = isProp and propPrefix() or genderPrefix()
  local file = (isProp and PROP_FILE[id]) or COMPONENT_FILE[id]
  if not file then return nil end

  local table_ = load(prefix .. file)
  if not table_ then return nil end

  local global = GameData.globalFor(PlayerPedId(), isProp and 'props' or 'components',
    id, collection, drawable, count)

  local row = table_[global]
  if not row then return nil end

  local entry = row[tostring(texture or 0)]
  return entry and entry.Localized or nil
end

-- ------------------------------------------------------------------- tags

--- Restriction tags for one item, or an empty list.
---
--- Empty is a real answer here, not a failure: the README of the source data says
--- explicitly that a missing row means either "these are the original freemode
--- clothes" or "Rockstar gave it no tags". Both are normal.
function GameData.itemTags(isProp, id, collection, drawable, texture, count)
  local file = load((isProp and 'prop' or 'component') .. '_tags_' .. GameData.gender)
  if not file then return {} end

  local global = GameData.globalFor(PlayerPedId(), isProp and 'props' or 'components',
    id, collection, drawable, count)

  local slot = file[tostring(id)]
  if not slot then return {} end

  local row = slot[tostring(global)]
  if not row then return {} end

  local tags = row[tostring(texture or 0)]
  return tags or {}
end

--- True when the item carries a tag.
function GameData.hasTag(isProp, id, collection, drawable, texture, count, tag)
  for _, value in ipairs(GameData.itemTags(isProp, id, collection, drawable, texture, count)) do
    if value == tag then return true end
  end
  return false
end

-- ------------------------------------------------------------- best torso

--- The torso that fits under a top, as (globalDrawable, texture), or nil.
---
--- Only component 11 (tops) has entries; the source README says explicitly that
--- this does not cover gloves or undershirts. `BestTorsoDrawable` of -1 means the
--- top has no torso data at all, and the caller must leave slot 3 alone - forcing
--- a default there would take the player's own choice away from them.
function GameData.bestTorso(collection, drawable, texture, count)
  local file = load('besttorso_' .. GameData.gender)
  if not file then return nil end

  local global = GameData.globalFor(PlayerPedId(), 'components', 11, collection, drawable, count)
  local row = file[tostring(global)]
  if not row then return nil end

  local entry = row[tostring(texture or 0)]
  if not entry then return nil end
  if entry.BestTorsoDrawable == nil or entry.BestTorsoDrawable < 0 then return nil end

  return entry.BestTorsoDrawable, entry.BestTorsoTexture
end

--- The collection-local coordinates of a global drawable on a component slot.
---
--- Needed because the torso table speaks global indices and this project stores
--- collection-local ones (ADR-0017). Looking the global back up in the slot's map
--- is what keeps one storage format in the database instead of two.
function GameData.localForGlobal(kind, id, global, collection, count)
  local map = mapCollection(PlayerPedId(), kind, id, collection, count)
  for drawable, value in pairs(map) do
    if value == global then return drawable end
  end
  return nil
end