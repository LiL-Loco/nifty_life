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
  --- Hard bounds. A drawable index above these is malformed rather than exotic,
  --- and the server has no way to ask the engine what actually exists (see the note
  --- at the top of this file) - so this number is the ONLY thing standing between a
  --- client and an arbitrary integer in the database.
  ---
  --- THEY ARE ESTIMATES, NOT MEASUREMENTS. The client knows the real counts - it
  --- asks the engine - and the creator logs them, so the first boot produces the
  --- numbers these bounds should actually be. Until then they are wide enough that
  --- no real garment is refused and narrow enough that 10^9 is not.
  ---
  --- The failure mode if they are too tight is worth naming, because it is not
  --- obvious: the player picks a hat, the server refuses the save with "drawable out
  --- of range", and the creator says "Das Aussehen konnte nicht gespeichert werden"
  --- for a hat that demonstrably exists on screen.
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

  --- Face sliders, head overlays and colours.
  ---
  --- The same problem as the drawable bounds above, one level worse: the engine
  --- knows how many styles overlay 4 (makeup) has and how many overlay 2
  --- (eyebrows) has, the server does not, and the numbers are per-ped. So these
  --- are bounds, not counts - generous enough that nothing real is refused, tight
  --- enough that a client cannot store an arbitrary integer.
  ---
  --- Overlays 0..12 are the game's own set (blemishes, facial hair, eyebrows,
  --- ageing, makeup, blush, complexion, sun damage, lipstick, moles, chest hair,
  --- body blemishes, and the additive body-blemish slot). Adding a thirteenth is
  --- not possible; the game has exactly thirteen.
  MIN_OVERLAY_ID     = 0,
  MAX_OVERLAY_ID     = 12,

  --- The engine treats style 255 as "disable this overlay". 255 is deliberately
  --- OUT of range here: disabling in this project means opacity 0, which the
  --- player can see and undo. A stored 255 would be invisible state.
  MAX_OVERLAY_STYLE  = 100,

  --- Colour indices. `_GetNumHairColors` and `_GetNumMakeupColors` both return far
  --- fewer than this; the bound only exists so an index cannot be absurd.
  MAX_OVERLAY_COLOUR = 80,

  --- Colour type for `_SetPedHeadOverlayColor`: 0 fixed grey, 1 the hair palette,
  --- 2 the makeup palette. Only 1 and 2 are selectable per overlay.
  MAX_OVERLAY_COLOUR_TYPE = 2,

  --- Face features are sliders 0..19, each -1.0..1.0. `SetPedFaceFeature`.
  MAX_FACE_FEATURE = 19,

  --- Eye colour: the game has exactly thirty-two. `SetPedEyeColor`.
  MAX_EYE_COLOUR = 31,

  --- Head blend presets (`SetPedHeadBlendData`). The engine identifies them as
  --- plain indices, not as a name, and the twenty-four "father" entries in
  --- third-party menus are English first names that mean nothing to a German
  --- player - two of them are the same blend. Presets 0..20 are the fathers,
  --- 21..45 the mothers; the upper bound is the whole range with room for the
  --- next content update.
  MAX_HEADBLEND_PRESET = 63,
}

--- Spawn points, referenced by `characters.spawn_point`.
---
--- ONE, ON PURPOSE. Not a truncation. A spawn point is a place a character can
--- begin, and a server with one weekend block and one map has exactly one answer to
--- "where does a new character wake up" - the airport, because it is where the
--- game itself puts a fresh ped and nobody has to be told about it.
---
--- The structure is a TABLE anyway, because `characters.spawn_point` is a string
--- column and `Validate.spawnPoint` resolves it against this list. Adding a second
--- entry later is a one-line change and needs no migration; there is simply no
--- second entry now, and `default` is what the migration 021 procedure writes.
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