--[[
  Static clothing data, read from this resource's `data/` folder.

  WHAT THIS IS
  Item names, restriction tags and "best torso" mappings for the freemode peds.
  They are keyed by GLOBAL drawable index - the number `GetNumDrawableVariations`
  would return for a component set with `SetPedComponentVariation`, which is not
  how this project stores anything (ADR-0017 stores collection + local drawable +
  texture, because global indices shift with every Title Update).

  So every lookup here goes through `globalFor()`, and that function is the whole
  point of this file. See the note on it before changing anything.

  WHY THE DATA LIVES IN THE REPOSITORY
  These tables are derived from the game's own clothes metadata and GXT text. They
  are vendored rather than generated at runtime because the source is inside RPF
  archives, which are not a documented format and which nobody on this project has
  tooling for. What they ARE is static game data, and static game data belongs with
  the code that reads it rather than in a runtime dependency on someone's server.

  The labels a player actually reads are NOT from here - those are ours, in
  cl_labels.lua. This is only item names, tags and torso mappings.
]]

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

--- Tattoo lists, keyed by gender and zone. Separate from `cache` because the zone
--- key already carries the gender, and because clearing one must not clear the
--- other: the clothing files are still valid when the tattoo lists are dropped.
local tattooCache = {}

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
--- Slots 12 is the only one without a file: the engine has no drawables
--- there for either freemode ped. Everything else gets a names file,
--- even the ones that are short on content (Head / Armor / Decal) - the
--- menu falls back to a number when a slot has no table.
local COMPONENT_FILE = {
  [0]  = 'heads',
  [1]  = 'masks',
  [2]  = 'hair',
  [3]  = 'torsos',
  [4]  = 'legs',
  [5]  = 'shoes',
  [7]  = 'accessories',
  [8]  = 'undershirts',
  [9]  = 'armor',
  [10] = 'decals',
  [11] = 'tops',
}

--- THE ONE FAMILY WHOSE FILES ARE NAMED THE OTHER WAY ROUND.
---
--- The game's own dumps carry the gender as a PREFIX almost everywhere
--- ('male_hair', 'female_tops') - but the masks carry it as a SUFFIX
--- ('masks_male', 'masks_female'). The loader builds the prefix form, so this
--- one family needs its own names.
---
--- It matters: the old code asked for 'male_masks', and that file does not
--- exist, so the mask slot had no names at all.
local FILE_BY_GENDER = {
  masks = { male = 'masks_male', female = 'masks_female' },
}

local PROP_FILE = {
  [0] = 'hats',
  [1] = 'glasses',
  [2] = 'ears',
  [6] = 'watches',
  [7] = 'bracelets',
}

--- The data file for one slot, with the gender in it.
---
--- It is a function and not an inline expression because the two tables above
--- have to be in scope first: a local declared LATER is not visible inside a
--- function body, and the function would look the name up as a global.
---
--- @return string|nil the file name without the extension, or nil for a slot
---                  that has no file (the engine has no drawables there).
local function fileForSlot(isProp, id)
  local file = (isProp and PROP_FILE[id]) or COMPONENT_FILE[id]
  if not file then return nil end

  local exception = FILE_BY_GENDER[file]
  if exception then
    return exception[GameData.gender] or exception.male
  end

  return (isProp and propPrefix() or genderPrefix()) .. file
end

--- Set by the creator before anything is looked up.
function GameData.setGender(gender)
  if GameData.gender == gender then return end

  GameData.gender = gender

  -- The global index mapping is per ped model. The same collection and the same
  -- local drawable mean different things on a male and a female ped, so the whole
  -- cache has to go - keeping it would name a leather jacket "Long Bob".
  cache = {}
  tattooCache = {}
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
--- There is no native for this. `GetPedPropGlobalIndexFromCollection` sounds
--- like one, but it was called with the prop index missing and it is not part
--- of the documented native set, so it cannot be trusted to answer at all.
---
--- So both kinds are resolved the same way: apply the local drawable with
--- texture 0 - which every item in the game has - and read back what the ped
--- is wearing now. `GetPedDrawableVariation` for a component, `GetPedPropIndex`
--- for a prop.
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

  -- What the ped is wearing in this slot, so it can be put back.
  --
  -- `GameData.savedSlot` returns the whole SLOT TABLE, not the collection
  -- name. The restore used to hand that table to a native that wants a
  -- string, which raised "invalid table argument" - and because the raise
  -- happened BEFORE the map was cached, every name lookup for this slot
  -- rebuilt the whole collection and threw again. So the collection name is
  -- taken out of the table here, and the drawable and the texture with it.
  local saved = GameData.savedSlot and GameData.savedSlot(kind, id)
  local savedCollection = type(saved) == 'table' and saved.collection or nil
  local savedDrawable = type(saved) == 'table' and tonumber(saved.drawable) or 0
  local savedTexture = type(saved) == 'table' and tonumber(saved.texture) or 0

  -- The local -> global mapping, asked of the engine WITHOUT touching the
  -- ped. The collection index native answers with -1 when the drawable does
  -- not exist, and it does not put a garment on the player to find out - the
  -- read-back this used to do could not tell a refusal from a success, and
  -- the player was left wearing the last drawable of the walk.
  for drawable = 0, count - 1 do
    local global = Variation.global(ped, kind, id, collection, drawable)
    if global then map[drawable] = global end
  end

  -- Put the ped back. With the index native the walk never touched it, but
  -- the fallback does, and the player is looking at their own character.
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
  local fileName = fileForSlot(isProp, id)
  if not fileName then return nil end

  local table_ = load(fileName)
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
  -- The tag files carry the gender as a PREFIX, like everything else:
  -- 'male_component_tags', 'male_prop_tags'. The old code asked for
  -- 'component_tags_male', and that file does not exist - so no piece ever had
  -- a restriction tag, and the restrictions the tags describe (a hat that
  -- clashes with a mask, a jacket that cannot be worn with a bag) were never
  -- checked on the client.
  local file = load(genderPrefix() .. (isProp and 'prop_tags' or 'component_tags'))
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

-- ---------------------------------------------------------- hair tattoo

--- The hair tattoo of one hairstyle: the two hashes the engine needs to draw the
--- hair's own overlay (its fading, its colour gradient).
---
--- THE DATA WAS HERE THE WHOLE TIME. Every row of `data/<gender>_hair.json`
--- carries `HairTattooCollection` and `HairTattooOverlay`, keyed exactly like
--- the names are keyed: by the GLOBAL drawable and the texture.
---
--- The creator used to build this map at runtime, out of the tattoo shop:
--- `GET_TATTOO_SHOP_DLC_ITEM_DATA` (whose third argument is a POINTER to a
--- struct that Lua cannot build) and the C# helper `GetTattooCollectionData`
--- (which does not exist in the runtime at all - the native list has
--- `GET_TATTOO_SHOP_DLC_ITEM_DATA` and nothing else of that shape). So the
--- probe always failed, and the hair never got its overlay.
---
--- A row without a tattoo says so with -1 in both fields. That is a real
--- answer, not a missing row: most hairstyles have no overlay at all.
---
--- @return number|nil collection, number|nil overlay
function GameData.hairTattoo(global, texture)
  local table_ = load(genderPrefix() .. 'hair')
  if not table_ then return nil end

  local row = table_[tostring(global)]
  if not row then return nil end

  local entry = row[tostring(texture or 0)]
  if not entry then return nil end

  local collection = tonumber(entry.HairTattooCollection)
  local overlay = tonumber(entry.HairTattooOverlay)
  if not collection or not overlay then return nil end

  -- -1 means "this hairstyle has no tattoo". Both fields are -1 together.
  if collection == -1 or overlay == -1 then return nil end

  return collection, overlay
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

-- ---------------------------------------------------------------- tattoos

--- The collection files, in a stable order.
---
--- `LoadResourceFile` has no directory listing, so the names come from the
--- allowlist the server also uses. That is deliberate: one list, two consumers,
--- and a collection the server would reject can never reach the menu either.
local tattooCollections = (function()
  local names = {}
  for name in pairs(AppearanceConfig.ALLOWED_TATTOO_COLLECTIONS) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end)()

--- Tattoos for one body zone, as a list of
--- `{ collection, preset, name, zone, zoneId }`.
---
--- `preset` is the joaat of the per-gender hash name; `collection` is the file
--- name, which is also the joaat the native wants. Both are computed HERE rather
--- than stored, because a hash is a hash and storing one would only add a way for
--- it to disagree with its own input.
---
--- `name` is the game's own English label. It is NOT translated - a tattoo called
--- "Hibiscus Flower Duo" has no honest German form, and inventing one would be
--- worse than leaving it readable. The menu around it is German; the proper nouns
--- are not.
function GameData.tattoosByZone(zoneId)
  local key = ('zone:%s:%s'):format(GameData.gender, tostring(zoneId))
  local cached = tattooCache[key]
  if cached then return cached end

  local wanted = (GameData.gender == 'female') and 'HashNameFemale' or 'HashNameMale'
  local out = {}

  for _, collection in ipairs(tattooCollections) do
    local file = load('tattoos/' .. collection)
    if type(file) == 'table' then
      for _, entry in ipairs(file) do
        if entry.ZoneID == zoneId and entry[wanted] and entry[wanted] ~= '' then
          out[#out + 1] = {
            collection = collection,
            hashName   = entry[wanted],
            preset     = joaat(entry[wanted]),
            name       = entry.LocalizedName or entry.Name or 'Tattoo',
            zone       = entry.Zone,
          }
        end
      end
    end
  end

  -- Sorted so the menu rows do not move between sessions. `pairs` over the JSON
  -- object keys would reorder everything on the next start, and "the tattoo one
  -- below Tribal Star" is not a thing a player can rely on.
  table.sort(out, function(a, b)
    if a.collection ~= b.collection then return a.collection < b.collection end
    return a.hashName < b.hashName
  end)

  tattooCache[key] = out
  return out
end

--- Every zone that has at least one tattoo for this ped.
function GameData.tattooZones()
  local out = {}
  for id = 0, 5 do
    if #GameData.tattoosByZone(id) > 0 then out[#out + 1] = id end
  end
  return out
end