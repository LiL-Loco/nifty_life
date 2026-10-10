# MariaDB via oxmysql as the persistence layer

All server state — characters, money, inventory, properties, vehicles, businesses, applications — lives in MariaDB, accessed from FiveM through `oxmysql`.

We are deliberately not using MSSQL despite that being the engine we work with professionally. FiveM's ecosystem assumes MySQL/MariaDB, and since we ruled out framework-based resources entirely (ADR-0002) there is nothing forcing the choice — so the deciding factor is that MariaDB is the engine we can actually operate, and a solo developer should not be maintaining a bespoke database bridge on top of every other system in this project.

## Consequences

- Player-owned rows are keyed by a stable surrogate key, never by FiveM slot ID (ADR-0001). The slot ID is stored only as ephemeral session data.
- Persisted entities (parked vehicles, business stalls) are server-created at boot and kept alive with `SetEntityOrphanMode(entity, 2)`. Their state — model, coordinates, fuel, damage, owner — lives in MariaDB, because vanilla GTA world state does not survive a restart.
- We own the backup story completely. FiveM ships no backup tooling, and with no players on the server pre-launch (ADR-0003) there is no external signal that the database is damaged or gone.