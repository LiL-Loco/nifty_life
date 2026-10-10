# Launch Gate

The server is launched when every item below is complete. The list is **closed**: ideas discovered during
development are logged as v2 and do not block launch. See ADR-0003 for why there is no partial release.

**Owner:** solo. **Target runtime:** FiveM Legacy (ADR-0001). **Core:** hand-rolled, no framework (ADR-0002).

## Systems

1. Whitelist gate at connection
2. Character — name, age, gender; **exactly one per account** (ADR-0008)
3. **Full character creator** — NUI appearance editor, all 13 components + 13 prop anchors,
   collection-based storage, server-side validation (ADR-0017)
4. Persistence layer (ID-safe keys, no FiveM slot ID as key)
5. Money — cash, bank, transfers
6. Inventory
7. Job system + police, EMS, taxi, mechanic — **open to anyone, no qualification** (ADR-0008)
8. Teamspeak voice — linked to the whitelist, closed to non-approved accounts (ADR-0015)
9. Housing — buy/rent, storage, keys
10. Vehicle ownership — buy, store, fuel, insurance, repair
11. Businesses — own, stock, staff, revenue
12. Phone + documents (licence, registration, medical)
13. Dispatch for police + EMS (LSPD = Mission Row, EMS = Pillbox). **No fire service** — GTA ships no
    enterable fire station, and an emergency service without a building is worse than none (ADR-0012).
14. Criminal layer — drugs, robberies

## Platform

15. txAdmin configured, permissions, ban system
16. Server convars hardened — `sv_entityLockdown`, entity lockdown mode, `sv_kick_players_cnl_*` set
17. Scheduled restart automation for the weekend window — Fri 19:00 start, Sun 22:00 stop (ADR-0010)
18. Event security — every client event validated server-side

## Operations

19. Website (Node/TS) live, with the application form + application status page
20. Whitelist enforcement wired to the website — Discord ID at `playerConnecting`, **and Teamspeak access
    driven from the same whitelist** so non-approved accounts cannot listen (ADR-0015)
21. Rules page, accepted by players
22. Player onboarding — first job, first property, expectations
23. Staff SOP for bans and applications
24. Automated backups — hourly dumps + binlog PITR, offsite encrypted, retention 7d/4w/12m (ADR-0006)
25. **One proven full restore** into an empty database, FXServer booted against it
26. Discord OAuth application + staff bot with approve/reject buttons (ADR-0007)
27. Two DB users with split privilege: `fivem` full, `website` INSERT-only on applications (ADR-0007)
28. Application state machine: submitted → under review → approved / rejected

## Design principles

- **Farming exists but is never mandatory.** A guaranteed Stütze provides a floor so nobody is stuck at zero,
  but is sized **below** subsistence so idling is never worth doing. Every aspirational purchase — vehicle,
  property, tuning, weapons — must be earnable without touching a farm loop (ADR-0009).
- **Vanilla geography.** GTA's map and landmarks are used as-is. "Vanilla" does **not** mean "no scripts"
  (that would contradict ADR-0002) nor "every building is GTA's" (ADR-0012) — interiors are repurposed.
- **Generic primitives.** Ownership is one system that houses, vehicles and businesses are data for, so
  later features are rows rather than new subsystems.
- **Downtime is the reset.** The server is down Monday–Thursday; nothing decays while it is off (ADR-0004).
- **Nothing is lost.** Persistent entities are server-owned; the world survives indefinitely.

## Not decided yet

- **Economy numbers** — Stütze amount, all prices, wages, sink costs (structure fixed in ADR-0009)
- **Teamspeak licensing** — licence tier must be verified against 48 slots (ADR-0015)
- **Interior count** — reachable stock apartments to be counted on a live server (ADR-0013)