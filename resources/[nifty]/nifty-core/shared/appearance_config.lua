--- Appearance and spawn configuration (ADR-0017).
---
--- SHARED: loaded on both client and server. The client uses it to offer only
--- options the server will accept; the server uses it to reject anything else.
--- It is deliberately one file — a duplicated allowlist would drift, and the
--- failure mode of a drifted allowlist is a creator that offers something the
--- server silently refuses.
---
--- WHY THIS FILE EXISTS
---
--- The collection natives (GetNumberOfPedCollectionDrawableVariations and
--- friends) are CLIENT-ONLY. The server cannot ask the engine whether a given
--- component/collection/drawable combination is real. Appearance submitted by a
--- client is therefore untrusted input, exactly like an item id in an inventory
--- event. The allowlist below is what the server validates against instead.

AppearanceConfig = {
  --- Hard bounds. Real drawable and texture counts sit comfortably inside these;
  --- anything beyond is malformed rather than exotic.
  MAX_DRAWABLE = 300,
  MAX_TEXTURE  = 80,

  --- Component ids 0..12 and prop anchor points 0..12.
  MIN_COMPONENT_ID = 0,
  MAX_COMPONENT_ID = 12,

  --- Collection names permitted. The base game collection is the empty string;
  --- the rest are GTA DLC collections present in a stock install.
  ---
  --- This is an allowlist rather than a denylist: a new DLC collection must be
  --- added here on purpose, so it can never start feeding characters content
  --- nobody reviewed.
  ALLOWED_COLLECTIONS = {
    ['']                  = true,  -- base game
    female_beach          = true,
    female_bikerdlc_01    = true,
    female_biker          = true,
    female_heist         = true,
    female_xmas           = true,
    male_bikerdlc_01      = true,
    male_biker            = true,
    male_heist            = true,
    male_xmas             = true,
    mp_f_bikerdlc_01      = true,
    mp_m_bikerdlc_01      = true,
    mp_f_freemode_01      = true,
    mp_m_freemode_01      = true,
  },

  --- Ped models offered by the creator. Freemode models carry the full
  --- component range; anything else has far fewer options.
  PED_MODELS = {
    mp_m_freemode_01 = 'male',
    mp_f_freemode_01 = 'female',
  },
}

--- Spawn points, referenced by `characters.spawn_point`.
SpawnPoints = {
  default = {
    label  = 'Los Santos International',
    x = -1035.71, y = -2731.87, z = 12.86, heading = 0.0,
  }
}

--- Where the character creator stages the player. Outdoors on purpose: the
--- project buys no MLO (ADR-0012), so there is no bespoke studio interior.
CreatorScene = {
  x = -812.80, y = 175.31, z = 76.75,   -- Vinewood Hills overlook
  heading = 195.0,
  camHeight = 0.35,
  camRadius = 2.6,
  camPitch = -8.0,
}