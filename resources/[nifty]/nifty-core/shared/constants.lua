--- Shared constants for Nifty Life 2.0.
--- Anything a client and the server must agree on belongs here. Anything the
--- server must never trust from a client does NOT (see sv_main.lua).

Nifty = {}

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

return Nifty