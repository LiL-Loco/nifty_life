--[[
  Clothing store coordinates.

  Sourced from qb-clothing (https://github.com/qbcore-framework/qb-clothing):
  their config.lua declares 15 clothing positions across Los Santos and the
  surrounding counties. We take the same set; the in-world identity (Ponsonbys,
  Binco, SubUrban, etc.) is what the player reads on a map blip, the
  coordinates are what the server registers ox_target zones at.
]]

Stores = Stores or {}

Stores.Stores = {
  { id = 1,  name = 'Paleto Bay Kleidung',      x =  1693.32, y =  4823.48, z =  41.06 },
  { id = 2,  name = 'Ponsonbys Rockford',       x =  -712.22, y =  -155.35, z =  37.42 },
  { id = 3,  name = 'SubUrban Vespucci',        x = -1192.94, y =  -772.69, z =  17.33 },
  { id = 4,  name = 'Binco Mirror Park',        x =   425.24, y =  -806.01, z =  28.49 },
  { id = 5,  name = 'Binco Pillbox Hill',       x =  -162.66, y =  -303.40, z =  38.73 },
  { id = 6,  name = 'Vinewood Kleidung',        x =    75.95, y = -1392.89, z =  28.38 },
  { id = 7,  name = 'Chumash Kleidung',         x =  -822.19, y = -1074.13, z =  10.33 },
  { id = 8,  name = 'Richman Kleidung',         x = -1450.71, y =  -236.83, z =  48.81 },
  { id = 9,  name = 'Sandy Shores Kleidung',    x =     4.25, y =  6512.81, z =  30.88 },
  { id = 10, name = 'Harmony Kleidung',         x =   615.18, y =  2762.93, z =  41.09 },
  { id = 11, name = 'Grapeseed Kleidung',       x =  1196.79, y =  2709.56, z =  37.22 },
  { id = 12, name = 'Great Chaparral Kleidung', x = -3171.45, y =  1043.86, z =  19.86 },
  { id = 13, name = 'Tataviam Mountains',       x = -1100.96, y =  2710.21, z =  18.11 },
  { id = 14, name = 'Vespucci Beach Kleidung',  x = -1207.65, y = -1456.88, z =   4.38 },
  { id = 15, name = 'Alta St. Kleidung',        x =   121.76, y =  -224.60, z =  53.56 },
}

return Stores
