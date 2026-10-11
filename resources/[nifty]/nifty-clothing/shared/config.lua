--[[
  Clothing constants and native hashes.

  Shared so that the server-side validation and the client-side toggle agree on
  what "the top" is, without either of them inventing a number.

  PORTED FROM root-cause/ragemp-hood-up (MIT), see LEARNINGS.md for the
  licence and for the two places this port deliberately departs from it.
]]

-- The table has to be CREATED before the first field assignment, not opened
-- as if it already existed. A previous version of this file started with
-- `Clothing.COMPONENT_TOP = 11` directly, which on the very first load (the
-- only load order that matters - the one that establishes the global) was an
-- `attempt to index a nil value (global 'Clothing')`. The error stopped being
-- raised only because the resource still reported "Started"; the rest of the
-- resource was then running against a Clothing table that did not exist.
Clothing = Clothing or {}

--- The only component and prop this system ever touches.
Clothing.COMPONENT_TOP    = 11
Clothing.COMPONENT_MASK   = 1
Clothing.PROP_HAT         = 0

--- Native hashes, written out rather than called by name.
---
--- Several of these are undocumented or have documentation that disagrees with
--- what the engine actually does (see LEARNINGS.md, GET_SHOP_PED_COMPONENT).
--- Calling them by hash removes the dependency on a name that may be absent in
--- this build, and keeps the port traceable next to its source.
Clothing.NATIVES = {
  -- Hash name of the component a ped is currently wearing.
  GET_HASH_NAME_FOR_COMPONENT             = 0x0368B3A838070348,
  -- Same, for a prop.
  GET_HASH_NAME_FOR_PROP                   = 0x5D6160275CAEC8DD,
  -- Third argument is an out-param: non-zero when the component carries the tag.
  DOES_SHOP_PED_APPAREL_HAVE_RESTRICTION_TAG = 0x341DE7ED1D2A1BFD,
  -- How many variants a shop component has.
  GET_SHOP_PED_APPAREL_VARIANT_COMPONENT_COUNT = 0xC17AD0E5752BECDA,
  -- Out-params: variant hash, variant drawable index, component type.
  GET_VARIANT_COMPONENT                    = 0x6E11F282F11863B6,
}

--- Restriction tags, as the strings the engine knows them by.
---
--- Stored as names, not hashes, so the hash is computed once at load and the
--- spelling stays checkable against the clothing definition files.
Clothing.TAGS = {
  HOODED_JACKET = 'HOODED_JACKET',
  HOOD_UP       = 'HOOD_UP',
  HOOD_DOWN     = 'HOOD_DOWN',
  HOOD_TUCKED   = 'HOOD_TUCKED',
  HOOD_HAT      = 'HOOD_HAT',
}

--- Tags a mask may carry for it not to clip through a raised hood.
---
--- NOTE: this list is checked with SOME (any tag matches), which is the
--- reference behaviour and is deliberately kept. A mask that carries any one of
--- these is considered compatible; the alternative - requiring all of them -
--- would make the check reject almost every real ski or gas mask.
Clothing.MASK_TAGS = {
  'HOOD_COMPAT',
  'REBREATHER',
  'HAZ_MASK',
  'SKI_MASK',
  'GAS_MASK',
  'BIKER_MASK',
}

--- A sanity ceiling on a variant drawable index.
---
--- The engine hands out indices we cannot predict from here, and an absurd one
--- is the signature of a mis-read out-param rather than of a rare garment. The
--- creator's own bound is used so the two cannot drift apart.
Clothing.MAX_VARIANT_DRAWABLE = AppearanceConfig.MAX_DRAWABLE

return Clothing