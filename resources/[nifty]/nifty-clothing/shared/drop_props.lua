--[[
  Drop-prop mapping.

  When a player drops an inventory item on the ground (right-click
  -> Wegwerfen), nifty-clothing spawns a GTA world object at the
  player's location. This file is the per-item-code -> model hash
  mapping. Codes without a specific entry fall back to
  DropProps.default, which is the GTA Online drop-bag model.

  V1 catalogue is conservative: only items that have an unambiguous
  in-game model - most clothing items share the carrier bag because
  freemode has no per-piece prop. Future iterations can extend with
  more entries; the dispatch is open-ended.
]]

DropProps = DropProps or {}

DropProps.byCode = {
  -- Electronics
  ['phone']                 = `prop_phone_ing`,

  -- Food / drink (a generic shop bag is what GTA shows)
  ['bread']                 = `v_ret_ta_bag01`,
  ['water']                 = `p_cs_bottle_01b`,
  ['coffee']                = `v_ret_ta_bag01`,

  -- Medical
  ['bandage']               = `p_cs_bottle_med`,
  ['painkillers']           = `p_cs_pills`,

  -- Tools
  ['lockpick']              = `prop_cs_dagger_01`,
  ['screwdriver']            = `p_tool_screwdriver`,
  ['car_key']               = `prop_cd_key`,
  ['house_key']             = `prop_cd_key`,

  -- Documents
  ['id_card']               = `p_paper_bag01`,
  ['drivers_licence']       = `p_paper_bag01`,
}

-- Used for any code without a specific entry, and as a fallback when
-- the requested model is not in the client's cdimage (IsModelInCdimage).
DropProps.default = `hei_prop_carrier_bag_02a`

--- Resolve a model hash for an item code. May return a hash the
--- client's cdimage does NOT contain - callers should test
--- IsModelInCdimage and fall back to DropProps.default.
function DropProps.forCode(code)
  if type(code) ~= 'string' or code == '' then return DropProps.default end
  return DropProps.byCode[code] or DropProps.default
end

return DropProps
