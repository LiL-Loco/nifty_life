--[[
  Clothing variations: the line between what this project STORES and what
  the engine ACCEPTS.

  THE SPACE THIS PROJECT STORES IN
  -------------------------------
  `collection + local drawable + texture` (ADR-0017), because the global
  indices shift with every Title Update and the collection-local ones do not.

  THE SPACE THE ENGINE VALIDATES IN
  ---------------------------------
  The engine's `CPed::SetVariation` takes GLOBAL indices. The collection
  natives are the layer in between, and they are the ones that speak this
  project's space. From the server's own source
  (code/components/extra-natives-five/src/PedCollectionsNatives.cpp):

      GET_PED_DRAWABLE_GLOBAL_INDEX_FROM_COLLECTION(ped, componentId, collection, drawableId)
      GET_PED_PROP_GLOBAL_INDEX_FROM_COLLECTION(ped, anchorPoint, collection, propIndex)
      GET_PED_COLLECTION_LOCAL_INDEX_FROM_DRAWABLE(ped, globalDrawableIdx, componentId)
      GET_PED_COLLECTION_LOCAL_INDEX_FROM_PROP(ped, globalPropIdx, anchorPoint)
      GET_NUMBER_OF_PED_COLLECTION_TEXTURE_VARIATIONS(ped, componentId, collection, drawableId)
      GET_NUMBER_OF_PED_COLLECTION_PROP_TEXTURE_VARIATIONS(ped, anchorPoint, collection, propIndex)
      IS_PED_COLLECTION_COMPONENT_VARIATION_VALID(ped, componentId, collection, drawableId, textureId)

  Every one of them answers in the COLLECTION space and returns -1 when the
  thing does not exist. None of them touches the ped.

  WHY THAT MATTERS MORE THAN IT LOOKS
  -----------------------------------
  `SET_PED_COLLECTION_COMPONENT_VARIATION` is a redirect: it resolves the
  local index to the global one and, if that fails, RETURNS WITHOUT CALLING
  THE ENGINE. So a local index that does not exist is a SILENT NO-OP - the
  ped keeps the garment it was wearing, and the engine never prints
  "CPed::SetVariation: Invalid variation" because the engine was never
  called.

  Which means: reading the ped back is not a way to find out whether an
  apply worked. The ped still wears the PREVIOUS item, and that item looks
  exactly like a successful apply. The only thing that knows the truth is
  the index native, and it answers -1.

  The previous version of this file resolved the local index by applying it
  with texture 0 and reading the ped back. That could not tell a refused
  apply from a successful one, so the texture count was asked for the WRONG
  item and the clamp was computed against the wrong garment.

  THE NATIVES ARE NOT DOCUMENTED
  -------------------------------
  None of them is in the CFX native database, and the database is what the
  documentation is generated from. They are REGISTERED all the same, and the
  ones this project has used for years - the collection setters - demonstrably
  work. Whether the index ones are exposed to Lua is therefore measured, not
  assumed: `reportNatives()` says which path the file took, and the fallback
  is the older read-back.
]]

--- The clothing index helpers.
---
--- A global, like `AppearanceConfig` and `Nifty` in the rest of the project.
--- FiveM Lua's `require` exists but is not the convention here.
Variation = {}

local RESOURCE = GetCurrentResourceName()

--- Whether a native is there.
---
--- The question is asked of the RUNTIME, never of the documentation: the
--- documentation does not know these natives, and the runtime does. The
--- answer decides which path the file takes, and it is reported so that the
--- path is never a guess.
local function has(name)
  return type(_G[name]) == 'function'
end

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

--- Say once, loudly, which natives this file depends on and which path it
--- took.
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
    if not has(name) then missing[#missing + 1] = name end
  end

  local text
  if #missing == 0 then
    text = 'alle Natives vorhanden'
  else
    text = 'FEHLENDE NATIVES: ' .. table.concat(missing, ', ')
  end

  -- WHICH PATH THE FILE TOOK.
  --
  -- The index natives are the whole point of this file: they answer without
  -- touching the ped and they say -1 when the thing does not exist. Without
  -- them the file falls back to applying the drawable and reading the ped
  -- back, which cannot tell a refusal from a success.
  local path = 'direkt (Collection-Index-Natives)'
  if not (has('GetPedDrawableGlobalIndexFromCollection')
      and has('GetNumberOfPedCollectionTextureVariations')
      and has('IsPedCollectionComponentVariationValid')) then
    path = 'RÜCKSCHLAG (Read-back, ohne Index-Natives)'
  end

  print(('[%s] variation: %s | Weg: %s'):format(RESOURCE, text, path))

  -- To the server once, not once per resource that includes this file: the
  -- natives are the same on every client, and nifty-core is the resource that
  -- owns the server side of this diagnostic.
  if RESOURCE == 'nifty-core' then
    TriggerServerEvent('nifty:server:variationDiag', ('%s | Weg: %s'):format(text, path))
  end
end

-- ---------------------------------------------------------------- the indexes

--- The GLOBAL index of a collection-local drawable, or nil.
---
--- nil means: this collection does not exist for this ped, or this local
--- index is outside it. The native says so with -1, and the answer is
--- meaningful because the native does not touch the ped.
function Variation.global(ped, kind, slot, collection, drawable)
  local anchor = tonumber(slot)
  local index = tonumber(drawable)
  if not anchor or not index then return nil end

  if kind == 'props' then
    if has('GetPedPropGlobalIndexFromCollection') then
      local global = GetPedPropGlobalIndexFromCollection(ped, anchor, collection, index)
      if global == -1 then return nil end
      return global
    end
  elseif has('GetPedDrawableGlobalIndexFromCollection') then
    local global = GetPedDrawableGlobalIndexFromCollection(ped, anchor, collection, index)
    if global == -1 then return nil end
    return global
  end

  -- THE FALLBACK: apply the drawable with texture 0 - which every item has -
  -- and read back what the ped wears.
  --
  -- It cannot tell a refusal from a success, and the caller is told so by
  -- getting the PREVIOUS item's index. That is why the index natives above
  -- are worth having, and why their absence is reported.
  if kind == 'props' then
    SetPedCollectionPropIndex(ped, anchor, collection, index, 0, false)
    local global = GetPedPropIndex(ped, anchor)
    if global == -1 then return nil end
    return global
  end

  SetPedCollectionComponentVariation(ped, anchor, collection, index, 0, 0)
  return GetPedDrawableVariation(ped, anchor)
end

--- The collection-local drawable of a GLOBAL one, or nil.
---
--- The shop's variant system speaks global indices; this project stores
--- collection-local ones. The native answers the question directly and does
--- not touch the ped - so the player is left wearing what they were wearing,
--- which is the only acceptable answer for a lookup.
---
--- The collection name is not needed by the native: it searches the ped's own
--- collection for the drawable. It IS needed by the fallback, which walks
--- the collection.
function Variation.localForGlobal(ped, kind, slot, collection, global, count)
  local anchor = tonumber(slot)
  local wanted = tonumber(global)
  if not anchor or not wanted then return nil end

  if kind == 'props' then
    if has('GetPedCollectionLocalIndexFromProp') then
      local local_index = GetPedCollectionLocalIndexFromProp(ped, wanted, anchor)
      if local_index == -1 then return nil end
      return local_index
    end
  elseif has('GetPedCollectionLocalIndexFromDrawable') then
    local local_index = GetPedCollectionLocalIndexFromDrawable(ped, wanted, anchor)
    if local_index == -1 then return nil end
    return local_index
  end

  -- THE FALLBACK: walk the collection.
  --
  -- This one DOES touch the ped - there is no other way to learn the mapping
  -- by asking - so the caller has to put the ped back. The walk leaves it
  -- wearing the last drawable of the collection, and the failure path leaves
  -- it there too.
  local total = tonumber(count) or 0
  for drawable = 0, total - 1 do
    local resolved = Variation.global(ped, kind, anchor, collection, drawable)
    if resolved == wanted then return drawable end
  end

  return nil
end

-- -------------------------------------------------------------- the textures

--- The texture count of ONE drawable of a collection.
---
--- FOUR arguments. The fourth is the local drawable index, and the native
--- uses it: it resolves the local index to the global one and asks the engine
--- for THAT item's texture count. Called with three arguments, the missing
--- one arrives as 0 and the answer is about drawable 0 - a plausible number
--- for the wrong jacket.
function Variation.textureCount(ped, kind, slot, collection, drawable)
  local anchor = tonumber(slot)
  local index = tonumber(drawable)
  if not anchor or not index then return nil end

  if kind == 'props' then
    if has('GetNumberOfPedCollectionPropTextureVariations') then
      return GetNumberOfPedCollectionPropTextureVariations(ped, anchor, collection, index)
    end
  elseif has('GetNumberOfPedCollectionTextureVariations') then
    return GetNumberOfPedCollectionTextureVariations(ped, anchor, collection, index)
  end

  -- THE FALLBACK: the same count, asked in the global space.
  local global = Variation.global(ped, kind, anchor, collection, index)
  if not global then return nil end

  if kind == 'props' then
    return GetNumberOfPedPropTextureVariations(ped, anchor, global)
  end
  return GetNumberOfPedTextureVariations(ped, anchor, global)
end

--- Is this (drawable, texture) real?
---
--- The engine's own predicate, asked in the collection space - which is the
--- space the appearance is stored in, so nothing has to be translated.
---
--- There is no `IsPedCollectionPropVariationValid`, so for props this is nil
--- and the count is the whole answer.
function Variation.isValid(ped, kind, slot, collection, drawable, texture)
  if kind == 'props' then return nil end
  if not has('IsPedCollectionComponentVariationValid') then return nil end

  return IsPedCollectionComponentVariationValid(ped, tonumber(slot), collection,
    tonumber(drawable), tonumber(texture)) == true
end

--- The texture index the engine will accept for this drawable.
---
--- The count bounds the search and the engine has the last word: a drawable
--- can have fewer textures than the count reports, and the validity check
--- asks about the exact pair.
---
--- @return number texture -- the index to use
function Variation.clampTexture(ped, kind, slot, collection, drawable, texture)
  local count = Variation.textureCount(ped, kind, slot, collection, drawable)
  if type(count) ~= 'number' or count < 1 then count = 1 end

  local tex = tonumber(texture) or 0
  if tex < 0 then tex = 0 end
  if tex > count - 1 then tex = count - 1 end

  if Variation.isValid(ped, kind, slot, collection, drawable, tex) == false then
    while tex > 0 do
      tex = tex - 1
      if Variation.isValid(ped, kind, slot, collection, drawable, tex) ~= false then
        break
      end
    end
  end

  return tex
end

--- Apply one slot, with a texture the engine accepts.
---
--- This is the only place in the project that sets a clothing variation, so it
--- is the only place that has to know about the texture count at all.
---
--- @return number texture -- the texture that was used
function Variation.apply(ped, kind, slot, collection, drawable, texture)
  local anchor = tonumber(slot)
  local index = tonumber(drawable)
  if not anchor or not index then return 0 end

  local tex = Variation.clampTexture(ped, kind, slot, collection, index, texture)

  -- The drawable this apply is ABOUT. The native says -1 when it does not
  -- exist, and that is the only trustworthy answer - the engine's own
  -- reaction to an unknown local index is to do nothing at all.
  local wantedGlobal = Variation.global(ped, kind, anchor, collection, index)

  if kind == 'props' then
    SetPedCollectionPropIndex(ped, anchor, collection, index, tex, false)
  else
    SetPedCollectionComponentVariation(ped, anchor, collection, index, tex, 0)
  end

  -- THE ENGINE'S OWN ANSWER.
  --
  -- The engine does not return an error when it refuses a variation. It
  -- prints one - to the CLIENT's console, once per frame, for as long as the
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

  local tookIt = (wantedGlobal ~= nil
    and appliedGlobal == wantedGlobal
    and appliedTexture == tex)

  if not tookIt then
    Variation.report(('engine nahm Drawable %s/Textur %s statt %s/%s (slot %s, collection %q, drawable %s)'):format(
      tostring(appliedGlobal), tostring(appliedTexture), tostring(wantedGlobal), tostring(tex),
      tostring(anchor), tostring(collection), tostring(index)))
  end

  return tex
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
