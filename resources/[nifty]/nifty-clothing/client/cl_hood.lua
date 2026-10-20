--[[
  Hood up / hood down.

  PORTED FROM root-cause/ragemp-hood-up (MIT licence). The original is two
  JavaScript files for RAGE MP and does not run here at all: RAGE MP's server
  can set clothes on a player directly, FiveM cannot, so its whole shape - the
  client asks the server, the server calls `player.setClothes` - has to be
  inverted. In FiveM the ped is only ever touched on the client, and the server
  is told afterwards so the change survives a relog.

  WHAT IT DOES
  Press the key. If your top is a hoodie that is not a "tucked" variant, it is
  swapped for the same hoodie in the other hood state. If a hat or a mask would
  clip through a raised hood, it refuses and says why.

  WHERE THIS DEPARTS FROM THE REFERENCE, AND WHY

  1. The variant drawable index comes from GET_VARIANT_COMPONENT, not from
     GET_SHOP_PED_COMPONENT. The reference reads drawable and texture out of a
     136-byte struct that native fills. Cfx Lua can only hand a native a
     four-byte pointer (Citizen.PointerValueInt), so that struct is simply not
     readable from Lua - the port has no way to do what the reference does, and
     GET_VARIANT_COMPONENT returns the same drawable index directly.

  2. The reference works in GLOBAL freemode indices. This project stores
     clothing per collection (ADR-0017), so the swap keeps the current top's
     collection and only replaces drawable and texture. The consequence is that
     a variant index is applied into whichever collection the player is already
     wearing, which is correct for the base collection and unproven for a DLC
     one. The first in-game run reports what actually happened - see the
     diagnostic net event at the bottom of this file - and the collection
     handling is the thing to check in it.
]]

local RESOURCE = GetCurrentResourceName()
local N = Clothing.NATIVES
local TAGS = Clothing.TAGS

--- How long to wait after a join before the key does anything.
---
--- Without it the key works during the creator, where the ped is a preview that
--- belongs to nifty-creator and any write would be saved as if the player had
--- chosen it themselves.
local SETTLE_MS = 3000

local settled = false

-- -----------------------------------------------------------------------------
-- Native wrappers
-- -----------------------------------------------------------------------------

--- joaat as the engine means it: unsigned 32-bit.
---
--- GetHashKey can hand back a negative number for a hash whose top bit is set,
--- and comparing that against a hash produced the same way still works - but
--- only as long as BOTH sides go through this. Mixing a raw GetHashKey result
--- with an unsigned literal is the kind of comparison that is false for one
--- hoodie and true for the next.
local function hash32(name)
  return GetHashKey(name) & 0xFFFFFFFF
end

local HASHED_TAGS = {}
for name, text in pairs(TAGS) do HASHED_TAGS[name] = hash32(text) end
for i, name in ipairs(Clothing.MASK_TAGS) do HASHED_TAGS[name] = hash32(name) end

--- joaat("0"). The reference filters this out of variant results; it is a
--- placeholder the clothing definitions use for "no component".
local HASH_ZERO = hash32('0')

--- Whether a component hash carries a restriction tag.
local function hasRestrictionTag(componentHash, tagHash)
  if componentHash == nil or componentHash == 0 then return false end

  -- The third parameter is an out-param, not an input: the engine writes the
  -- answer through it. Passing nothing would leave it whatever it was before.
  local out = Citizen.PointerValueInt()
  Citizen.InvokeNative(N.DOES_SHOP_PED_APPAREL_HAVE_RESTRICTION_TAG,
    componentHash, tagHash, out)

  return (out:GetValue(Citizen.PointerValueInt()) or 0) ~= 0
end

--- Hash of the component the ped is currently wearing at `componentId`.
local function wornComponentHash(ped, componentId)
  local drawable = GetPedDrawableVariation(ped, componentId)
  local texture  = GetPedTextureVariation(ped, componentId)
  return Citizen.InvokeNative(N.GET_HASH_NAME_FOR_COMPONENT,
    ped, componentId, drawable, texture) & 0xFFFFFFFF
end

--- Hash of the prop the ped is currently wearing at `propIndex`.
local function wornPropHash(ped, propIndex)
  local drawable = GetPedPropIndex(ped, propIndex)
  if drawable == -1 then return 0 end

  local texture = GetPedPropTextureIndex(ped, propIndex)
  return Citizen.InvokeNative(N.GET_HASH_NAME_FOR_PROP,
    ped, propIndex, drawable, texture) & 0xFFFFFFFF
end

--- Find the variant of `topHash` that carries `targetFlag`.
---
--- Returns drawable, or nil when the garment has no such variant - which is a
--- normal answer, not a failure: plenty of hoodies are modelled with only one
--- hood state.
local function findVariant(topHash, targetFlag)
  local count = Citizen.InvokeNative(N.GET_SHOP_PED_APPAREL_VARIANT_COMPONENT_COUNT, topHash)
  if type(count) ~= 'number' or count <= 0 then return nil, 'no variants (' .. tostring(count) .. ')' end

  for i = 0, count - 1 do
    local variantHash    = Citizen.PointerValueInt()
    local variantDrawable = Citizen.PointerValueInt()
    local variantType    = Citizen.PointerValueInt()

    Citizen.InvokeNative(N.GET_VARIANT_COMPONENT,
      topHash, i, variantHash, variantDrawable, variantType)

    local vHash = variantHash:GetValue(Citizen.PointerValueInt()) & 0xFFFFFFFF
    local vDraw = variantDrawable:GetValue(Citizen.PointerValueInt())
    local vType = variantType:GetValue(Citizen.PointerValueInt())

    -- Only tops. The reference checks this too: a hoodie has variants for other
    -- components and swapping one of those in would be invisible at best.
    if vType == Clothing.COMPONENT_TOP and vHash ~= 0 and vHash ~= HASH_ZERO then
      if hasRestrictionTag(vHash, targetFlag) then
        if type(vDraw) ~= 'number' or vDraw < 0 or vDraw > Clothing.MAX_VARIANT_DRAWABLE then
          -- An out-param we could not read is not a variant to apply. Saying so
          -- is more useful than setting the ped to a nonsense drawable.
          return nil, ('variant %d has an implausible drawable (%s)'):format(i, tostring(vDraw))
        end
        return vDraw, ('variant %d of %d, drawable %d'):format(i, count, vDraw)
      end
    end
  end

  return nil, ('none of %d variants carries the flag'):format(count)
end

-- -----------------------------------------------------------------------------
-- Clipping
-- -----------------------------------------------------------------------------

--- A hat only works under a hood if it is one of the knitted beanies.
---
--- Note the asymmetry with the mask below, and that it is deliberate: the hat
--- check asks for ONE specific tag, because a baseball cap genuinely does not
--- fit under a hood while a beanie does.
local function hatAllowsHood(ped)
  local propIndex = GetPedPropIndex(ped, Clothing.PROP_HAT)
  if propIndex == -1 then return true, 'no hat' end

  return hasRestrictionTag(wornPropHash(ped, Clothing.PROP_HAT), HASHED_TAGS.HOOD_HAT),
    'hat'
end

--- A mask works if it carries ANY of the known hood-compatible tags.
local function maskAllowsHood(ped)
  if GetPedDrawableVariation(ped, Clothing.COMPONENT_MASK) == 0 then
    return true, 'no mask'
  end

  local hash = wornComponentHash(ped, Clothing.COMPONENT_MASK)
  for i = 1, #Clothing.MASK_TAGS do
    if hasRestrictionTag(hash, HASHED_TAGS[Clothing.MASK_TAGS[i]]) then
      return true, 'mask carries ' .. Clothing.MASK_TAGS[i]
    end
  end

  return false, 'mask has no hood-compatible tag'
end

-- -----------------------------------------------------------------------------
-- The toggle
-- -----------------------------------------------------------------------------

local function say(message)
  -- There is no client-side chat export; the chat surface is server-side
  -- (`exports['nifty-chat']:system`). So the message goes up and comes back
  -- down the same path every other system message takes. German: player-facing.
  TriggerServerEvent('nifty:server:hoodNotice', message)
end

local function toggle()
  if not settled then return end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end
  if IsEntityDead(ped) then return end

  -- No character, no appearance, no swap. During the creator this returns nil,
  -- which is the same signal that keeps the key quiet before a login.
  local World = exports['nifty-world']
  local appearance = World:getCurrentAppearance()
  if type(appearance) ~= 'table' or type(appearance.components) ~= 'table' then return end

  -- A COPY, and that is the whole point.
  --
  -- `getCurrentAppearance` hands out nifty-world's LIVE table, and the
  -- autosave and the disconnect save both send it. Writing the hood variant
  -- into it therefore put a piece the character does not own into EVERY later
  -- save - and the server refuses an appearance whose pieces it cannot
  -- verify. A refused save returns before the position is written, so the
  -- player's position stopped being persisted as well, and the reason was
  -- four files away from the cause.
  --
  -- A copy keeps the live state the server can accept.
  local ok, copied = pcall(function() return json.decode(json.encode(appearance)) end)
  if not ok or type(copied) ~= 'table' then return end
  appearance = copied

  local slot = appearance.components[tostring(Clothing.COMPONENT_TOP)]
  if type(slot) ~= 'table' then return end

  local topHash = wornComponentHash(ped, Clothing.COMPONENT_TOP)

  -- Not a hoodie, or a tucked one: nothing to toggle.
  if not hasRestrictionTag(topHash, HASHED_TAGS.HOODED_JACKET) then return end
  if hasRestrictionTag(topHash, HASHED_TAGS.HOOD_TUCKED) then return end

  local isHoodDown = hasRestrictionTag(topHash, HASHED_TAGS.HOOD_DOWN)
  local targetTag  = isHoodDown and HASHED_TAGS.HOOD_UP or HASHED_TAGS.HOOD_DOWN

  -- Only check clipping when the hood is about to go UP. Putting it down never
  -- collides with anything.
  if isHoodDown then
    local hatOk, hatWhy = hatAllowsHood(ped)
    if not hatOk then
      return say('Deine Mütze verhindert das Aufziehen der Kapuze.')
    end

    local maskOk, maskWhy = maskAllowsHood(ped)
    if not maskOk then
      return say('Deine Maske verhindert das Aufziehen der Kapuze.')
    end
  end

  local drawable, why = findVariant(topHash, targetTag)
  if not drawable then
    TriggerServerEvent('nifty:server:diag', ('hood: no variant (%s)'):format(tostring(why)))
    return
  end

  -- The collection is the one already on the ped. See the header: this is the
  -- part of the port that is unproven for DLC collections.
  local collection = slot.collection or ''
  local texture = slot.texture or 0

  -- THE VARIANT INDEX IS A GLOBAL ONE, and this project stores the
  -- collection-local one (ADR-0017). The collection setter reads a LOCAL
  -- index, so applying the global one is what produced
  --
  --     CPed::SetVariation: Invalid variation (slotId: 11, drawblId: 300, ...)
  --
  -- The reverse lookup walks the collection once and finds the local index
  -- that means this global one.
  local count = Variation.collectionDrawables(ped, 'components',
    Clothing.COMPONENT_TOP, collection)
  local localDrawable = Variation.localForGlobal(ped, 'components',
    Clothing.COMPONENT_TOP, collection, drawable, count)
  if not localDrawable then
    TriggerServerEvent('nifty:server:diag',
      ('hood: %s | coll=%q hat kein lokales Drawable fuer global %d'):format(
        isHoodDown and 'up' or 'down', tostring(collection), drawable))
    return
  end

  -- The texture goes through the same clamp as every other slot: the variant
  -- can have fewer textures than the top the player was wearing.
  local usedTexture = Variation.apply(ped, 'components',
    Clothing.COMPONENT_TOP, collection, localDrawable, texture)

  -- Report what the engine actually did, not what we asked for. This is the
  -- difference between "it worked" and "it looked like it worked".
  local gotDrawable = GetPedDrawableVariation(ped, Clothing.COMPONENT_TOP)
  local gotTexture  = GetPedTextureVariation(ped, Clothing.COMPONENT_TOP)

  TriggerServerEvent('nifty:server:diag',
    ('hood: %s | coll=%q drawable=%d->%d texture=%d->%d (asked %s)'):format(
      isHoodDown and 'up' or 'down',
      tostring(collection), localDrawable, gotDrawable, usedTexture, gotTexture,
      tostring(why)))

  -- Persist. The saved path validates against nifty-core before it writes, so
  -- this cannot smuggle a drawable past the allowlist.
  --
  -- THE LOCAL INDEX GOES IN, not the global one. The global used to be stored
  -- here, and since the appearance is applied as a local index every time
  -- after that, this wrote a number into the database that means something
  -- else entirely - and the engine refused the slot on every login from then
  -- on, long after the hoodie was forgotten.
  slot.drawable = localDrawable
  slot.texture  = usedTexture
  appearance.components[tostring(Clothing.COMPONENT_TOP)] = slot

  TriggerServerEvent('nifty:server:saveCharacter', { appearance = appearance })
end

RegisterCommand('hood', toggle, false)
RegisterKeyMapping('hood', 'Kapuze auf-/abziehen', 'keyboard', 'F5')

-- -----------------------------------------------------------------------------
-- Startup
-- -----------------------------------------------------------------------------

CreateThread(function()
  -- Wait for the session rather than for the resource: key handlers that fire
  -- before the player exists write to a ped handle that is about to be replaced.
  while not NetworkIsSessionStarted() do Wait(200) end

  Wait(SETTLE_MS)
  settled = true
end)

exports('isHoodie', function()
  local ped = PlayerPedId()
  local hash = wornComponentHash(ped, Clothing.COMPONENT_TOP)
  return hasRestrictionTag(hash, HASHED_TAGS.HOODED_JACKET)
end)