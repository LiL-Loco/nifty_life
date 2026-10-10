--- Shared constants for Nifty Life 2.0.
--- Anything a client and the server must agree on belongs here. Anything the
--- server must never trust from a client does NOT (see sv_main.lua).

Nifty = {}

--- Row identifier generator. Every player-owned row is keyed by a UUID (ADR-0001):
--- slot IDs get recycled and must never end up in a key. Shared so the identity
--- and inventory layers mint identical-shaped IDs.
---
--- SEEDING IS A ONE-TIME EVENT, done here at load. An earlier version called
--- `math.randomseed` INSIDE this function, which is a real bug and not a style
--- point: reseeding resets the generator's state, so two calls in the same
--- millisecond got the same seed and returned the IDENTICAL uuid. That surfaced
--- as `ERROR 1062 Duplicate entry ... for key 'PRIMARY'` on a Peeper post,
--- intermittently, a few runs in. It applies to every table keyed by this —
--- characters, inventory rows, phone accounts, messages — where a collision is
--- not a failed insert but a refused player.
---
--- The random stream is now advanced continuously across calls, which is what
--- makes consecutive UUIDs independent rather than a pure function of the clock.
math.randomseed(os.time() + math.floor((tonumber(os.clock()) or 0) * 1000000))

function Nifty.newUuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'

  return (string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end))
end

Nifty.Schema = {
  -- Table names. Centralised so a rename is one edit, not a grep across
  -- every resource.
  accounts       = 'accounts',
  characters     = 'characters',
  sessions       = 'sessions',
  wallets        = 'wallets',
  inventoryItems = 'inventory_items',
  properties     = 'properties',
  propertyOwners = 'property_owners',
  vehicles       = 'vehicles',
  jobDefs        = 'job_defs',
  characterJobs  = 'character_jobs',
  applications   = 'applications',
  bans           = 'bans',
  settings       = 'settings',
  stuetzePayouts = 'stuetze_payouts',
}

--- Property tiers. Housing count is 60, so scarcity is reintroduced by tier
--- rather than by count (ADR-0013).
Nifty.Tier = {
  OUTLIER  = 'outlier',
  ENTRY    = 'entry',
  STANDARD = 'standard',
  PREMIUM  = 'premium',
  LUXURY   = 'luxury',
}

--- Application state machine (ADR-0007).
Nifty.ApplicationStatus = {
  SUBMITTED     = 'submitted',
  UNDER_REVIEW  = 'under_review',
  APPROVED      = 'approved',
  REJECTED      = 'rejected',
}

--- Profile settings cache. Populated at start from the `settings` table so the
--- server never hardcodes a tunable number (ADR-0009).
Nifty.Settings = {}