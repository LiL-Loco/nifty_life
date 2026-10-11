-- Our own spawn points. NOT a skater park - the Cfx fivem-map-skater that
-- used to live in this slot had ~30 rooftop spawns with a_m_y_skater_01,
-- which is what made the Cfx forceRespawn flash a skater on every join.
--
-- Each spawnpoint uses mp_m_freemode_01 so the flash is a normal freemode.
-- nifty-world's enterWorld then sets the actual character model from
-- character.gender, so the visual sequence is:
--   skater/empty -> normal freemode (Cfx respawn) -> character model (nifty-world)
-- instead of:
--   skater/empty -> skater (Cfx) -> character (nifty-world)
--
-- Coords are GTA V landmarks picked by hand from the single-player map; not
-- copied from any specific resource. Add more here as the city gets a
-- police station, hospital, etc. that needs its own spawn area.

-- Downtown: Legion Square
spawnpoint 'mp_m_freemode_01' { x =  195.17, y =  -933.77, z = 30.69, heading = 143.5 }

-- West: Vespucci Beach
spawnpoint 'mp_m_freemode_01' { x = -1290.0,  y = -1480.0,  z =  4.34, heading = 125.0 }

-- North: Paleto Bay
spawnpoint 'mp_m_freemode_01' { x = -260.0,   y =  6630.0,  z =  7.0,  heading = 220.0 }