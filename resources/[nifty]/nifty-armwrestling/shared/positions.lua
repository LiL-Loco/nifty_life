-- Arm-wrestling table positions across the map.
--
-- Each entry is a { x, y, z, heading } tuple. The original RAGE script had 12
-- cases; we keep all of them. The server is authoritative: clients only read
-- these to find the nearest table when the player presses the interaction key.
--
-- Two players at the same table = the same match. Two players at different
-- tables = two independent matches.
return {
  { x =  1116.5148, y = -3153.2751, z =   -37.569, heading =  90.000 },
  { x =  1003.2322, y = -3165.7360, z =   -34.598, heading =   0.000 },
  { x =  1443.3403, y = -2219.0103, z =   60.349, heading = 105.023 },
  { x =   -82.4445, y = -1327.7800, z =   28.797, heading = 180.000 },
  { x =   901.9729, y =  -172.1309, z =   73.566, heading =   0.000 },
  { x =   369.0920, y = -2445.4500, z =    5.519, heading =-178.027 },
  { x =  1221.2200, y =  2726.0600, z =   37.504, heading = -63.208 },
  { x =  1051.6752, y =  2663.6100, z =   39.026, heading = 111.578 },
  { x =   270.2250, y =  2603.9600, z =   44.231, heading = 140.468 },
  { x =  -191.9170, y =  6273.2600, z =   30.971, heading =  -3.811 },
  { x =  1685.7200, y =  4970.3900, z =   42.096, heading =  15.230 },
  { x =  2340.8700, y =  3130.4700, z =   47.684, heading = 126.139 },
}
