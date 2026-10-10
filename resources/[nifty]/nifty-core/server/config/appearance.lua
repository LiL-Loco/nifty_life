--- Appearance validation configuration (ADR-0017).
---
--- WHY THIS FILE EXISTS
---
--- The collection natives (GetNumberOfPedCollectionDrawableVariations and friends)
--- are CLIENT-ONLY. The server therefore cannot ask the engine whether a given
--- component/collection/drawable combination is real. Appearance submitted by a
--- client is untrusted input, exactly like an item id in an inventory event.
---
--- So the server validates against this allowlist instead. Anything not
--- explicitly permitted here is rejected before it reaches the database. The
--- point is not to reimplement the engine's validity rules — it is to stop a
--- client persisting an appearance the game cannot render.

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
  --- This is deliberately an allowlist rather than a denylist: a new DLC
  --- collection must be added here on purpose, so it can never start feeding
  --- characters content nobody reviewed.
  ALLOWED_COLLECTIONS = {
    ['']                  = true,  -- base game
    female_beach          = true,
    female_bikerdlc_01    = true,
    female_biker         = true,
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
--- Default is where a new character arrives. `housing` is used once property
--- is built (ADR-0013).
SpawnPoints = {
  default = {
    label  = 'Los Santos International',
    x = -1035.71, y = -2731.87, z = 12.86, heading = 0.0,
  },
  losSantos = {
    label  = 'Legion Square',
    x = 195.32, y = -933.77, z = 29.72, heading = 145.0,
  },
}