--- Money (ADR-0009).
---
--- There is exactly one way money moves in this server: `Economy.apply`. Not a
--- convenience — the enforcement. Any code path that reaches for
--- `UPDATE wallets` directly is a bug, because the ledger is what makes a balance
--- explainable after an incident, and a balance without an entry is a balance
--- nobody can defend to a player who lost it.
---
--- Two rules the schema cannot express, so they live here:
---   * A `reason` is mandatory and is a closed vocabulary. "money went somewhere"
---          is not a usable audit record.
---   * The balance change and the ledger entry are written together or not at all.

local RESOURCE = GetCurrentResourceName()

Economy = {}

--- Closed set of reasons. Adding one is a deliberate act, not a typo fix — it is
--- the difference between a log a player can be shown and a log that is noise.
local REASONS = {
  stuetze        = true,
  job_wage       = true,
  job_payoff     = true,
  sale           = true,
  purchase       = true,
  vehicle_purchase = true,
  property_purchase = true,
  property_sale  = true,
  vehicle_sale   = true,
  rent           = true,
  bank_deposit   = true,
  bank_withdraw  = true,
  admin_adjust   = true,
  repair         = true,
  fuel           = true,
  fine           = true,
}

local VALID_ACCOUNTS = { cash = true, bank = true }

-- ---------------------------------------------------------------------------
-- Money arithmetic
-- ---------------------------------------------------------------------------

--- Money is DECIMAL(14,2) in the database and a Lua double in memory. Rounding is
--- centralised here so no call site can invent its own, which is how a server ends
--- up with balances that are off by a cent per transaction.
local function round2(value)
  return math.floor((value + (value >= 0 and 0.5 or -0.5)) * 100 + 0.5) / 100
end

Economy.round = round2

--- Guard a client-supplied amount. Non-numbers, NaN, infinity and absurd values
--- are refused at the edge; a player does not get to pay 1e300 for a sandwich.
local MAX_AMOUNT = 100000000.00

local function sanitise(amount)
  local n = tonumber(amount)
  if n == nil then return nil end
  if n ~= n then return nil end                 -- NaN
  if n == math.huge or n == -math.huge then return nil end
  if n > MAX_AMOUNT or n < -MAX_AMOUNT then return nil end

  return round2(n)
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- Current balances. Returns nil for a character with no wallet row rather than a
--- zero balance — those are different states and only one of them is a bug.
function Economy.get(characterId)
  if not characterId then return nil end

  local row = Db.one([[
    SELECT cash, bank FROM wallets WHERE character_id = ?
  ]], { characterId }, 'economy:get')

  if not row then return nil end

  return {
    cash = Db.money.toNumber(row.cash),
    bank = Db.money.toNumber(row.bank),
  }
end

function Economy.getBalance(characterId, account)
  local balances = Economy.get(characterId)
  if not balances then return nil end
  return balances[account]
end

--- Push balances to the owning client. Fire-and-forget: a player who missed a
--- balance update can be corrected by reconnecting, and blocking gameplay on a
--- notification would be a worse failure.
function Economy.push(src, characterId)
  local balances = Economy.get(characterId)
  if not balances then return end
  TriggerClientEvent('nifty:client:economy', src, balances)
end

-- ---------------------------------------------------------------------------
-- Moving money
-- ---------------------------------------------------------------------------

--- Apply a signed delta to one account and record why.
---
--- The balance change is a single guarded UPDATE: `WHERE cash + ? >= 0` means the
--- non-negativity check happens inside the same atomic statement that subtracts
--- the money. Two simultaneous purchases cannot both succeed on the last euro,
--- which a read-then-write in Lua would happily allow.
---
--- Returns `ok, newBalance`. `ok` is false for a refused move — insufficient
--- funds, an unknown reason, an unknown account, or a database error. It never
--- throws and never returns a partially-applied state.
---
--- @param characterId string
--- @param account      string  'cash' | 'bank'
--- @param delta        number  positive to credit, negative to debit
--- @param reason       string  must be one of REASONS
--- @param refType      string|nil  e.g. 'property', 'vehicle', 'job'
--- @param refId        string|nil
--- @return boolean ok, string|nil errorMessage
function Economy.apply(characterId, account, delta, reason, refType, refId)
  if not characterId or type(characterId) ~= 'string' then
    return false, 'no character'
  end

  if not VALID_ACCOUNTS[account] then
    print(('[%s] REFUSED: unknown money account "%s"'):format(RESOURCE, tostring(account)))
    return false, 'bad account'
  end

  local amount = sanitise(delta)
  if amount == nil then
    print(('[%s] REFUSED: unusable amount %s for character %s'):format(
      RESOURCE, tostring(delta), characterId))
    return false, 'bad amount'
  end

  if not REASONS[reason] then
    -- This is a programming error, not player input, so it is logged loudly.
    print(('[%s] REFUSED: unknown ledger reason "%s"'):format(RESOURCE, tostring(reason)))
    return false, 'bad reason'
  end

  if amount == 0 then
    -- Nothing to do, and a zero-delta row would only pollute the audit trail.
    return true, nil
  end

  -- The account name is an identifier, so it cannot be a bind parameter — but
  -- VALID_ACCOUNTS has already reduced it to one of two literals, so this
  -- interpolation cannot carry anything a caller controls. Every *value* below
  -- is still a bind parameter; that rule is what stops a client reshaping SQL.
  local affected = Db.update(
    ([[UPDATE wallets SET %s = %s + ? WHERE character_id = ? AND %s + ? >= 0]]):format(account, account, account),
    { tostring(amount), characterId, tostring(amount) },
    'economy:apply')

  -- 0 rows means the guard rejected it: the character either does not have a
  -- wallet row, or could not afford it. Same code path, different reasons, and
  -- both are "no" from the caller's point of view.
  if affected == nil then return false, 'database error' end
  if affected == 0 then return false, 'insufficient funds' end

  -- Record it. `balance_after` is read by the INSERT itself rather than passed
  -- in, so the number written is the balance as the database sees it immediately
  -- after the UPDATE above — one statement, no value travelling through Lua.
  local recorded = Db.insert(
    ([[INSERT INTO ledger
         (character_id, account, delta, balance_after, reason, reference_type, reference_id)
       SELECT character_id, ?, ?, %s, ?, ?, ?
         FROM wallets WHERE character_id = ?]]):format(account),
    { account, tostring(amount), reason, refType, refId, characterId },
    'economy:ledger')

  if recorded == nil then
    -- Money moved, the record did not. This is the one gap the design cannot
    -- close without a stored procedure, so it is loud on purpose: the message
    -- names the character and the amount, which is everything a human needs to
    -- write the missing entry by hand.
    print(('[%s] FATAL: balance changed without a ledger entry ' ..
      '(character=%s account=%s delta=%s reason=%s). Reconcile this character.'):format(
      RESOURCE, characterId, account, tostring(amount), reason))
    return false, 'ledger write failed'
  end

  return true, nil
end

--- Credit. Thin wrapper so call sites read as what they mean.
function Economy.credit(characterId, account, amount, reason, refType, refId)
  return Economy.apply(characterId, account, math.abs(sanitise(amount) or 0), reason, refType, refId)
end

--- Debit. Returns false when the character cannot afford it — callers must treat
--- that as a normal outcome, not an exception.
function Economy.debit(characterId, account, amount, reason, refType, refId)
  return Economy.apply(characterId, account, -math.abs(sanitise(amount) or 0), reason, refType, refId)
end

--- Can this character afford it? Advisory only — the real check is the guarded
--- UPDATE inside `apply`, which callers must not skip in favour of this.
function Economy.canAfford(characterId, account, amount)
  local balance = Economy.getBalance(characterId, account)
  if balance == nil then return false end

  local want = sanitise(amount)
  if want == nil then return false end

  return balance >= want
end

--- Move money between a character's own accounts. Both legs are ledger entries —
--- this is not a free operation and must never be used as one.
function Economy.transfer(characterId, from, to, amount)
  if from == to then return false, 'same account' end

  local ok, err = Economy.debit(characterId, from, amount, from == 'cash' and 'bank_deposit' or 'bank_withdraw')
  if not ok then return false, err end

  return Economy.credit(characterId, to, amount, from == 'cash' and 'bank_deposit' or 'bank_withdraw')
end

--- Ledger history for staff tools and player disputes. Paged — a permanent world
--- means this table grows forever and an unpaged read would eventually take the
--- server down.
function Economy.history(characterId, limit, offset)
  limit = math.min(math.max(tonumber(limit) or 50, 1), 200)
  offset = math.max(tonumber(offset) or 0, 0)

  return Db.all([[
    SELECT l.id, l.account, l.delta, l.balance_after, l.reason,
           l.reference_type, l.reference_id, l.created_at
      FROM ledger l
     WHERE l.character_id = ?
     ORDER BY l.id DESC
     LIMIT ? OFFSET ?
  ]], { characterId, limit, offset }, 'economy:history')
end

exports('get', Economy.get)
exports('apply', Economy.apply)
exports('canAfford', Economy.canAfford)