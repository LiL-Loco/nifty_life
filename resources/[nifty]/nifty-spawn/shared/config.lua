Spawn = Spawn or {}

-- Five locations the player can choose between on first spawn / character
-- selection. Coords are GTA V landmarks, picked so the choices feel different
-- (city centre, desert, north coast, airport, beach) without sending the
-- player into the ocean.
Spawn.Locations = {
  { key = 'legion',   label = 'Legion Square',  x =  200.0,  y =  -890.0, z = 30.5, heading = 140.0 },
  { key = 'sandy',    label = 'Sandy Shores',   x = 1950.0,  y =  3720.0, z = 32.0, heading = 300.0 },
  { key = 'paleto',   label = 'Paleto Bay',     x = -260.0,  y =  6630.0, z =  7.0, heading = 220.0 },
  { key = 'airport',  label = 'Flughafen',      x = -1040.0, y = -2740.0, z = 20.0, heading = 330.0 },
  { key = 'beach',    label = 'Vespucci Strand', x = -1280.0, y = -1480.0, z =  4.0, heading = 120.0 },
}

-- Camera tuning. "High overview, then drop in to a slightly-angled view of
-- the point" - values are mine.
Spawn.CAM_HIGH_Z    = 200.0
Spawn.CAM_NEAR_Z   =  55.0
Spawn.CAM_FAR_FOV  = 100.0
Spawn.CAM_NEAR_FOV =  85.0
Spawn.CAM_INTERP_MS = 800
Spawn.CAM_SETTLE_MS = 600

return Spawn