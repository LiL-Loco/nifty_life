--[[
  Clothing variations: the line between what this project STORES and what the
  engine ACCEPTS.

  THE TWO INDEX SPACES
  -------------------
  This project stores clothing as `collection + local drawable + texture`
  (ADR-0017), because the global indices shift with every Title Update and the
  collection-local ones do not.

  The engine does not work in that space. `CPed::SetVariation` takes GLOBAL
  indices: the number the wardrobe itself stores. The collection natives
  (`SetPedCollectionComponentVariation` and friends) are a thin layer that
  translates a collection-local pair into the global one - and then the engine
  validates the global pair.

  So there are two different numbers for the same jacket, and the texture count
  a drawable has is a property of the GLOBAL drawable, not of the collection.

  WHY THIS FILE EXISTS
  --------------------
  Because getting this wrong is silent, and the silence is expensive. The
  engine's answer to an invalid texture is not an error return - it is a refusal
  that it prints once per frame, for as long as the appearance is on screen:

      CPed::SetVariation: Invalid variation (slotId: 10, drawblId: 9, texId: 1)

  The previous fix for that asked the engine two questions that the engine
  cannot answer under those names:

      GetNumberOfPedComponentTextures   -> does not exist
      GetNumberOfPedPropTextures        -> does not exist

  The real ones are `GetNumberOfPedTextureVariations` and
  `GetNumberOfPedPropTextureVariations`. Both were called behind a
  `type(...) == 'function'` guard, so the wrong name did not raise - it made the
  guard fall through, the count came back nil, and the fix quietly did nothing
  while the engine kept refusing the slot.

  A silent fallback for a native that must be there is not robustness, it is a
  way of not finding out. `reportNatives()` below turns that class of mistake
  into a line in the log.

  THE MAPPING
  -----------
  For a PROP there is `GetPedPropGlobalIndexFromCollection`, but it is not part
  of the documented native set and it was being called with one argument
  missing, so it answered about a different prop. For a COMPONENT there is no
  such native at all.

  So both are resolved the same way, by reading it back:

      apply the local drawable with texture 0  ->  ask the ped what it wears

  Texture 0 exists for every item in the game, so this apply never produces an
  "Invalid variation" of its own. The ped is left wearing the resolved item,
  which is what the caller wanted anyway - `Variation.apply` sets the final
  texture straight afterwards.
]]

--- The clothing index helpers.
---
--- A global, like `AppearanceConfig` and `Nifty` in the rest of the project.
--- FiveM Lua's `require` exists but is not the convention here.
Variation = {}

local RESOURCE = GetCurrentResourceName()

-- ------------------------------------------------------- the natives report

local reported = false

--- Reports already sent, so the same one is not sent twice.
local seenReports = {}

--- Report something the client found.
---
--- It goes to the server as well as to the local console, because a client-side
--- `print()` reaches the CLIENT's console and nowhere else - it never appears
--- in the server log. That was measured: a client resource that printed its
--- name and its probe output left nothing in the server log but the
--- resource's own startup lines.
---
--- A report that nobody can read is the same as no report at all.
function Variation.report(message)
  if type(message) ~= 'string' or message == '' then return end
  if seenReports[message] then return end
  seenReports[message] = true

  -- The set is a de-duplication, not a history. It is allowed to forget.
  local count = 0
  for _ in pairs(seenReports) do count = count + 1 end
  if count > 64 then seenReports = {} end

  print(('[%s] variation: %s'):format(RESOURCE, message))
  TriggerServerEvent('nifty:server:variationDiag', ('%s: %s'):format(RESOURCE, message))
end

--- Say once, loudly, whether the natives this file depends on are there.
---
--- The point is not the report itself. The point is that a missing native used
--- to be indistinguishable from a native that answered "no", and the two look
--- identical at the call site: both end in a fallback.
local function reportNatives()
  if reported then return end
  reported = true

  local required = {
    'SetPedCollectionComponentVariation',
    'SetPedCollectionPropIndex',
    'GetPedDrawableVariation',
    'GetPedPropIndex',
    'GetNumberOfPedTextureVariations',
    'GetNumberOfPedPropTextureVariations',
  }

  local missing = {}
  for _, name in ipairs(required) do
    if type(_G[name]) ~= 'function' then missing[#missing + 1] = name end
  end

  local text
  if #missing == 0 then
    text = 'alle Natives vorhanden'
  else
    text = 'FEHLENDE NATIVES: ' .. table.concat(missing, ', ')
  end

  print(('[%s] variation: %s'):format(RESOURCE, text))

  -- To the server once, not once per resource that includes this file: the
  -- natives are the same on every client, and nifty-core is the resource that
  -- owns the server side of this diagnostic.
  if RESOURCE == 'nifty-core' then
    TriggerServerEvent('nifty:server:variationDiag', text)
  end
end

-- --------------------------------------------------------------- the mapping

--- The GLOBAL index the engine gave a collection-local drawable.
---
--- There is no native that maps a collection-local COMPONENT drawable to its
--- global index, so the mapping is read back: apply the local drawable with
--- texture 0 and ask the ped what it is wearing now.
---
--- @return number|nil global -- nil when the engine refused the drawable
function Variation.global(ped, kind, slot, collection, localDrawable)
  reportNatives()

  local drawable = tonumber(localDrawable)
  local anchor = tonumber(slot)
  if not drawable or not anchor then return nil end

  if kind == 'props' then
    SetPedCollectionPropIndex(ped, anchor, collection, drawable, 0, false)
    local global = GetPedPropIndex(ped, anchor)
    if global == -1 then return nil end
    return global
  end

  SetPedCollectionComponentVariation(ped, anchor, collection, drawable, 0, 0)
  return GetPedDrawableVariation(ped, anchor)
end

--- How many textures one drawable has.
---
--- The count belongs to the GLOBAL drawable. Asking for a collection-local one
--- asks about a different item and produces a plausible number for the wrong
--- jacket, which is how an invalid texture gets through.
---
--- @return number|nil count -- nil when the runtime cannot answer
function Variation.textureCount(ped, kind, slot, global)
  local anchor = tonumber(slot)
  if not global or not anchor then return nil end

  if kind == 'props' then
    return GetNumberOfPedPropTextureVariations(ped, anchor, global)
  end

  return GetNumberOfPedTextureVariations(ped, anchor, global)
end

--- Is this local drawable inside the collection at all?
---
--- The engine refuses a drawable the collection does not have, and that
--- refusal is INVISIBLE in the read-back: the ped keeps the item it was
--- wearing, and that item reads back as a perfectly valid drawable with a
--- perfectly valid texture. So this is asked of the COLLECTION, which knows
--- how many drawables it has, and not of the ped.
---
--- @return boolean known -- false when the collection reports no drawables
--- @return boolean exists
function Variation.hasDrawable(ped, kind, slot, collection, localDrawable)
  local available = Variation.collectionDrawables(ped, kind, slot, collection)
  if available <= 0 then return false, false end

  local drawable = tonumber(localDrawable)
  if not drawable then return true, false end

  return true, drawable < available
end

--- The texture index the engine will accept for this drawable.
---
--- The count bounds the search and the engine has the last word: a drawable can
--- have fewer textures than the count reports, and `IsPedComponentVariationValid`
--- asks about the exact pair the engine validates.
---
--- There is no `IsPedPropVariationValid`, so for props the count is the whole
--- answer.
---
--- @return number texture -- the index to use
--- @return number|nil global -- the drawable's global index
function Variation.clampTexture(ped, kind, slot, collection, localDrawable, texture)
  local global = Variation.global(ped, kind, slot, collection, localDrawable)
  if not global then return 0, nil end

  local count = Variation.textureCount(ped, kind, slot, global)
  if type(count) ~= 'number' or count < 1 then count = 1 end

  local tex = tonumber(texture) or 0
  if tex < 0 then tex = 0 end
  if tex > count - 1 then tex = count - 1 end

  if kind ~= 'props' and type(IsPedComponentVariationValid) == 'function' then
    while tex > 0 and not IsPedComponentVariationValid(ped, tonumber(slot), global, tex) do
      tex = tex - 1
    end
  end

  return tex, global
end

--- Apply one slot, with a texture the engine accepts.
---
--- This is the only place in the project that sets a clothing variation, so it
--- is the only place that has to know about the texture count at all.
---
--- @return number texture -- the texture that was actually used
function Variation.apply(ped, kind, slot, collection, localDrawable, texture)
  local anchor = tonumber(slot)
  local drawable = tonumber(localDrawable)
  if not anchor or not drawable then return 0 end

  -- THE STATE BEFORE THE APPLY.
  --
  -- Without it, a refusal is invisible. An empty slot reads as drawable 0 and
  -- texture 0 - which is exactly what a refused "drawable 0, texture 0" looks
  -- like - so a read-back that compares only against the REQUEST cannot tell
  -- "the engine refused it" from "the engine did exactly what I asked".
  --
  -- This is not a theoretical distinction: it is the difference between the
  -- engine printing "CPed::SetVariation: Invalid variation" every frame and
  -- the engine silently keeping the old jacket, and only one of them is
  -- visible in a report.
  local beforeGlobal, beforeTexture
  if kind == 'props' then
    beforeGlobal = GetPedPropIndex(ped, anchor)
    beforeTexture = GetPedPropTextureIndex(ped, anchor)
  else
    beforeGlobal = GetPedDrawableVariation(ped, anchor)
    beforeTexture = GetPedTextureVariation(ped, anchor)
  end

  -- DOES THE COLLECTION HAVE THIS DRAWABLE AT ALL?
  --
  -- This is checked BEFORE the apply, and it is the one refusal the read-back
  -- cannot see: the ped keeps the item it was wearing, which reads back as a
  -- perfectly valid drawable with a perfectly valid texture.
  --
  -- The apply is skipped when we know the engine would refuse it, because
  -- refusing it is not silent - it prints, once per frame, for as long as the
  -- appearance is on screen.
  local known, exists = Variation.hasDrawable(ped, kind, anchor, collection, drawable)
  if known and not exists then
    Variation.report(('die Collection %q hat kein Drawable %s in Slot %s'):format(
      tostring(collection), tostring(drawable), tostring(anchor)))
    return 0
  end
  if not known then
    Variation.report(('die Collection %q meldet keine Drawables fuer Slot %s'):format(
      tostring(collection), tostring(anchor)))
  end

  local tex, global = Variation.clampTexture(ped, kind, slot, collection, localDrawable, texture)

  if kind == 'props' then
    SetPedCollectionPropIndex(ped, anchor, collection, drawable, tex, false)
  else
    SetPedCollectionComponentVariation(ped, anchor, collection, drawable, tex, 0)
  end

  -- THE ENGINE'S OWN ANSWER.
  --
  -- The engine does not return an error when it refuses a variation. It prints
  -- one - to the CLIENT's console, once per frame, for as long as the
  -- appearance is on screen - and leaves the slot as it was. So the only way
  -- to know whether the apply worked is to read the ped back and compare.
  local appliedGlobal, appliedTexture
  if kind == 'props' then
    appliedGlobal = GetPedPropIndex(ped, anchor)
    appliedTexture = GetPedPropTextureIndex(ped, anchor)
  else
    appliedGlobal = GetPedDrawableVariation(ped, anchor)
    appliedTexture = GetPedTextureVariation(ped, anchor)
  end

  local tookIt = (appliedGlobal == global and appliedTexture == tex)

  if not tookIt then
    -- If the ped was already showing exactly this, there is nothing to
    -- report: the engine may have refused, or the item was already on, and
    -- the outcome for the player is the same either way.
    local alreadyThere = (beforeGlobal == global and beforeTexture == tex)
    if not alreadyThere then
      Variation.report(('engine nahm Drawable %s/Textur %s statt %s/%s (slot %s, collection %q, drawable %s)'):format(
        tostring(appliedGlobal), tostring(appliedTexture), tostring(global), tostring(tex),
        tostring(anchor), tostring(collection), tostring(drawable)))
    end
  end

  return tex
end

--- The collection-local drawable that means `global`, or nil.
---
--- The reverse of `Variation.global`, and it is needed whenever something hands
--- us a global index: the shop's variant system speaks global indices, while
--- this project stores local ones, and applying a global index as a local one
--- is exactly the mistake that produces "Invalid variation".
---
--- The walk applies every drawable of the collection once, so the ped is left
--- wearing the LAST one. The caller has to apply what it actually wants
--- afterwards - `Variation.apply` does exactly that.
---
--- @return number|nil local -- nil when the collection has no such item
function Variation.localForGlobal(ped, kind, slot, collection, global, count)
  reportNatives()

  local wanted = tonumber(global)
  local total = tonumber(count)
  if not wanted or not total then return nil end

  for drawable = 0, total - 1 do
    local resolved = Variation.global(ped, kind, slot, collection, drawable)
    if resolved == wanted then return drawable end
  end

  return nil
end

--- How many drawables a collection has for this slot.
function Variation.collectionDrawables(ped, kind, slot, collection)
  reportNatives()

  local anchor = tonumber(slot)
  if not anchor then return 0 end

  if kind == 'props' then
    return GetNumberOfPedCollectionPropDrawableVariations(ped, anchor, collection) or 0
  end

  return GetNumberOfPedCollectionDrawableVariations(ped, anchor, collection) or 0
end

-- Report at load, not at first use.
--
-- A report that only appears when something goes wrong is a report nobody
-- reads. The natives are registered before any client script runs, so this
-- says what is there at the moment the resource starts - and a missing one
-- shows up in the log of a session that has not broken yet.
reportNatives()
