# Permanent world, frozen while the server is offline

Everything persists across restarts indefinitely: properties, parked vehicles, businesses and their stock, character state, money and reputation. There is no seasonal or weekly wipe. The world is only advanced while the server is running, so the four-day shutdown Monday–Thursday does not advance time — parked cars stay parked and stalls keep their stock.

This follows directly from the no-grinding rule: with a weekend-only window, a player who shows up every third weekend must be able to return to a life that is intact. Wiping would mean a month-long absence costs a player everything they built, which is the exact failure the no-grind design exists to prevent.

## Consequences

- Persisted entities are server-created and owned by the server, not vanilla world state. Vanilla GTA parked cars do not survive a restart on their own; a persistent vehicle must be recreated server-side and kept alive with `SetEntityOrphanMode(entity, 2)`, which stops the server garbage-collecting it while still letting the owning player request deletion. Client-side RPC `CreateVehicle` is explicitly *not* reliable for this — the docs describe it as fallible and not guaranteed to run on the client.
- Any time-based system must explicitly define offline behaviour rather than inheriting wall-clock time. Defaulting to frozen is a deliberate decision to make, because the naive implementation advances on server restart.
- "Nothing is lost" is now a hard durability requirement against months of accumulated player investment, which makes tested backups part of the persistence design rather than an operational afterthought.
- A permanent world of 20–40 players stagnates over time. Seasonal resets are logged as the planned response to a stale world, not as the default.