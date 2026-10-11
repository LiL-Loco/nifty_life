--[[
  Clothing store price table.

  The lookup is three-layer:
    1. Prices.components[slot_id][drawable] - one-off cheap prices for specific items
    2. Prices.components[slot_id]._default  - slot-wide default when nothing else applies
    3. Prices._default                     - top-level fallback for slots not listed at all

  A `Prices.for(kind, slot_id, drawable)` call returns a number or 0; never nil.
  0 is reserved for items the staff has marked unsellable (the menu hides them).

  V1 ships a tiny curated seed; balancing is a numbers pass, not a code pass.
  /reload-clothing reads this file again so changes do not need a server restart.
]]

Prices = Prices or {}

Prices.components = {
  -- Tops (slot 11) - the most-traded slot.
  [11] = {
    [0]  = 500,  [1]  = 500,  [3]  = 600,  [7]  = 1200,
    [11] = 1500, [15] = 800,  _default = 700,
  },
  -- Torsos (slot 3).
  [3]  = {
    [0]  = 350, [1] = 350, [2] = 450, _default = 400,
  },
  -- Legs (slot 4).
  [4]  = {
    [0]  = 500, [1] = 550, [2] = 700, _default = 600,
  },
  -- Shoes (slot 6).
  [6]  = {
    [0]  = 400, [1] = 450, [3] = 600, _default = 500,
  },
  -- Accessories (slot 8).
  [8]  = {
    [0]  = 800, [1] = 350, [2] = 450, _default = 400,
  },
  -- Undershirts (slot 8 alt in some references, but we keep one entry).
  [5]  = { [0] = 250, [1] = 300, _default = 250 },
  -- Masks (slot 1).
  [1]  = { [0] = 200, [1] = 350, _default = 300 },
  -- Hair (slot 2) and the rest of components 9..12 share one default.
  [2]  = { _default = 400 },
  [9]  = { _default = 200 },
  [10] = { _default = 200 },
  [12] = { _default = 200 },
  [0]  = { _default = 200 },
}

Prices.props = {
  -- Hats (prop 0).
  [0] = {
    [0]  = 200, [2] = 400, [5] = 350, [7] = 600,
    _default = 250,
  },
  -- Glasses (prop 1).
  [1] = { [0] = 300, [1] = 350, _default = 350 },
  -- Ears (prop 2).
  [2] = { _default = 150 },
  -- Watches / bracelets / accessory (props 6, 7) - one default each.
  [6] = { _default = 400 },
  [7] = { _default = 500 },
}

Prices._default = 300   -- used when no slot-specific entry exists.

--- Resolve a price. Returns a number; never nil.
---
--- Lua reserves the keyword `for`, so this is `Prices.priceOf` rather than
--- `Prices.for`. Same shape, name only.
function Prices.priceOf(kind, slot_id, drawable)
  local byKind = (kind == 'component') and Prices.components
              or (kind == 'prop')     and Prices.props
              or nil
  if not byKind then return Prices._default end

  local slotMap = byKind[tostring(slot_id)]
  if type(slotMap) == 'table' then
    -- Per-(slot, drawable) entry.
    local d = tonumber(drawable)
    if d and slotMap[tostring(d)] then return slotMap[tostring(d)] end
    -- Slot-wide default.
    if slotMap._default then return slotMap._default end
  end

  return Prices._default
end

return Prices
