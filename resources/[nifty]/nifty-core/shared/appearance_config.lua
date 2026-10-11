--[[
  Appearance and spawn configuration (ADR-0017).

  SHARED: loaded on both client and server. The client uses it to offer only
  options the server will accept; the server uses it to reject anything else.
  It is deliberately one file — a duplicated allowlist would drift, and the
  failure mode of a drifted allowlist is a creator that offers something the
  server silently refuses.

  WHY THIS FILE EXISTS

  The collection natives (GetNumberOfPedCollectionDrawableVariations and
  friends) are CLIENT-ONLY. The server cannot ask the engine whether a given
  component/collection/drawable combination is real. Appearance submitted by a
  client is therefore untrusted input, exactly like an item id in an inventory
  event. The allowlist below is what the server validates against instead.
]]

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
  --- player - two of them are the same blend.
  ---
  --- THE RANGE IS OBSERVED, NOT ASKED FOR. There is no native that reports how many
  --- heritage presets exist, so this bound comes from what the freemode peds
  --- actually use: 0..20 plus 42..44 on one side, 21..41 plus 45 on the other -
  --- 46 in total. Offering the slider up to 63 would let a player pick an index
  --- the engine has no face for, and the result would be whatever it clamps to,
  --- silently, and looking like the game had ignored them.
  ---
  --- The third parent draws from the WHOLE range, not from one side of it. That is
  --- the point of a third face: it can be whoever, including a preset the
  --- "mother" list also happens to contain.
  MAX_HEADBLEND_PRESET = 45,

  --- Tattoo collections: the DLC overlay collections a facial decoration can come
  --- from. Same idea as ALLOWED_COLLECTIONS above, same reason it exists - the
  --- server cannot ask the engine which collections are installed, so this list is
  --- the whole of what it will accept.
  ---
  --- It is generated from the file names in nifty-creator/data/tattoos, which are
  --- one file per collection. If a content update adds one, this list is where it
  --- gets added, and the check that keeps them in step is that a tattoo the server
  --- accepts but no data file describes simply never appears in the menu.
  ALLOWED_TATTOO_COLLECTIONS = {
    ['mp2023_01_overlays'] = true,
    ['mp2023_02_overlays'] = true,
    ['mp2024_02_overlays'] = true,
    ['mpairraces_overlays'] = true,
    ['mpbeach_overlays'] = true,
    ['mpbiker_overlays'] = true,
    ['mpbusiness_overlays'] = true,
    ['mpchristmas2_overlays'] = true,
    ['mpchristmas2017_overlays'] = true,
    ['mpchristmas2018_overlays'] = true,
    ['mpchristmas3_overlays'] = true,
    ['mpgunrunning_overlays'] = true,
    ['mpheist3_overlays'] = true,
    ['mpheist4_overlays'] = true,
    ['mphipster_overlays'] = true,
    ['mpimportexport_overlays'] = true,
    ['mplowrider_overlays'] = true,
    ['mplowrider2_overlays'] = true,
    ['mpluxe_overlays'] = true,
    ['mpluxe2_overlays'] = true,
    ['mpsecurity_overlays'] = true,
    ['mpsmuggler_overlays'] = true,
    ['mpstunt_overlays'] = true,
    ['mpsum2_overlays'] = true,
    ['mptuner_overlays'] = true,
    ['mpvinewood_overlays'] = true,
    ['mpxmas_604490_overlays'] = true,
    ['multiplayer_overlays'] = true,
  },

  --- How many tattoos one character may wear at once.
  ---
  --- The engine is happy to layer many decals on the same skin; the previous
  --- "one per zone" rule was a UI choice, not an engine limit. The creator no
  --- longer enforces it, and the cap here is left in only as a storage sanity
  --- check against a malicious client that would fill the database with junk.
  --- 100 is well above any practical tattoo collection.
  MAX_TATTOOS = 20,
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
---
--- Timing model for the 3-stage flyover in cl_creator.lua's `startCamera`:
---   t=0       → far/high overview is rendered (stage 1)
---   t=camMove → mid-range cam lerps in over camInterp ms (stage 2)
---   t=camMove+camInterp+camSettle → close-up cam lerps in over 600 ms (stage 3)
--- Total ~camMove + camInterp + camSettle + 600, then the menu opens.
CreatorScene = {
  x = -812.80, y = 175.31, z = 76.75,   -- Vinewood Hills overlook
  heading = 195.0,
  camHeight = 0.35,
  camRadius = 2.6,
  camPitch = -8.0,
  camFarFov = 50.0,       -- stage 1, wide overview
  camNearFov = 35.0,      -- stage 2, mid-range
  camNearZ = 1.6,         -- stage 2 height
  camMove = 1500,         -- ms before stage 2 begins
  camInterp = 1500,       -- ms each stage-to-stage blend lasts
  camSettle = 400,        -- ms between stage 2 finishing and stage 3 starting
}