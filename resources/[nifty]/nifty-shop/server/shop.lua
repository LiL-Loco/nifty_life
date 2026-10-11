--[[
  Shop (ADR-0009).

  A shop is where money leaves. That makes it the one place where taking money
  and giving items must be treated as a single act, because half of either is
  the definition of a dupe or a robbery depending on which half failed.

  Order is deliberate: **charge first, deliver second, refund on failure.**
  The reverse order (give, then charge) means a player who cannot pay walks
  away with the goods whenever the debit is refused — and the debit is refused
  routinely, because that is what "cannot afford it" looks like.
]]

local RESOURCE = GetCurrentResourceName()

--- From the base facade, fetched by shared/core.lua at load. These were globals
--- when this file lived inside nifty-core; see the note in shared/core.lua about
--- why a local in fxmanifest would not have survived the chunk boundary.
local GetSetting = Nifty.GetSetting

--- This resource moves money AND items, so both owning systems are reached by
--- export rather than through the facade. The facade deliberately carries data
--- access, not behaviour — `Inventory:add` is not the base's to hand out.
local Economy = exports['nifty-economy']
local Inventory = exports['nifty-inventory']

local Shop = {}

--- What the shop sells. Built from the item catalogue crossed with settings,
--- so adding an item to `item_defs` plus a price row is the whole of adding it
--- to the shop — there is no second list that can fall out of sync.
local function priceFor(code)
  return Economy:round(GetSetting('economy.price.' .. code, 0))
end

--- The shelf. Items without a price setting are simply not for sale, which is
--- the cheapest possible way to hide an internal item.
function Shop.catalogue()
  local result = {}

  for code, def in pairs(Inventory:getAllDefinitions()) do
    local price = priceFor(code)
    if price > 0 then
      result[#result + 1] = {
        code = def.code,
        name = def.name,
        category = def.category,
        price = price,
        stackable = def.stackable,
        maxStack = def.maxStack,
      }
    end
  end

  table.sort(result, function(a, b)
    if a.category == b.category then return a.name < b.name end
    return a.category < b.category
  end)

  return result
end

--- Buy `quantity` of an item.
---
--- @return boolean ok, string|nil error
function Shop.buy(characterId, code, quantity)
  quantity = math.floor(tonumber(quantity) or 1)
  if quantity < 1 or quantity > 99 then return false, 'bad quantity' end

  local def = Inventory:getDefinition(code)
  if not def then return false, 'unknown item' end

  local unitPrice = priceFor(def.code)
  if unitPrice <= 0 then return false, 'not for sale' end

  local total = Economy:round(unitPrice * quantity)

  -- Cash, not bank: this is a corner shop transaction, and charging the bank
  -- would let a broke character eat without ever touching the payout sink that
  -- the whole Stütze argument rests on.
  local paid, err = Economy:debit(characterId, 'cash', total, 'purchase', 'shop', def.code)
  if not paid then return false, err end

  local delivered, deliveryError = Inventory:add(characterId, def.code, quantity)
  if not delivered then
    -- Refund in full. Partial refunds would mean the shop quietly kept money for
    -- an item the player never received.
    Economy:credit(characterId, 'cash', total, 'purchase', 'shop', def.code)
    print(('[%s] refunded %s to %s: could not deliver %s (%s)'):format(
      RESOURCE, tostring(total), characterId, def.code, tostring(deliveryError)))
    return false, deliveryError
  end

  return true, nil
end

--- Sell back. Half price, because a shop that buys at the price it sells is a
--- money printer and a shop that buys at nothing makes every purchase feel like
--- a mistake. Neither is a decision worth defending — this is a placeholder rate
--- until the economy pass.
function Shop.sell(characterId, code, quantity)
  quantity = math.floor(tonumber(quantity) or 1)
  if quantity < 1 then return false, 'bad quantity' end

  local def = Inventory:getDefinition(code)
  if not def then return false, 'unknown item' end

  local unitPrice = priceFor(def.code)
  if unitPrice <= 0 then return false, 'not for sale' end

  -- Take the goods first. Crediting money for items that were never removed
  -- would be an infinite-money exploit with two lines of code.
  local removed, removeError = Inventory:remove(characterId, def.code, quantity)
  if not removed then return false, removeError end

  local payout = Economy:round((unitPrice / 2) * quantity)
  if payout > 0 then
    Economy:credit(characterId, 'cash', payout, 'sale', 'shop', def.code)
  end

  return true, nil
end

--- Move money between a character's own accounts.
---
--- A bank is not a shop, so this is not a shop special case — it is the same
--- movement, and `Economy:transfer` already owns it. Delegating means the
--- compensate-on-failure logic exists in exactly one place; two copies of it
--- means one of them is wrong within a month.
function Shop.deposit(characterId, amount)
  return Economy:transfer(characterId, 'cash', 'bank', amount)
end

function Shop.withdraw(characterId, amount)
  return Economy:transfer(characterId, 'bank', 'cash', amount)
end

exports('catalogue', Shop.catalogue)
exports('buy', Shop.buy)
exports('sell', Shop.sell)
exports('deposit', Shop.deposit)
exports('withdraw', Shop.withdraw)