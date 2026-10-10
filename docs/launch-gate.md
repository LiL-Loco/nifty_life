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
8. Housing — buy/rent, storage, keys
9. Vehicle ownership — buy, store, fuel, insurance, repair
10. Businesses — own, stock, staff, revenue
11. Phone device as an inventory item + phone account with a permanent server-assigned number (ADR-0018, 0021)
12. Phone apps — Messages, Email, documents (licence, registration, medical)
13. Social network "Peeper" — broadcast feed, asymmetric follows, posts, optional Place tag (ADR-0019)
14. Social moderation — report button + staff search by character, keyword or date (ADR-0019)
14a. **Peeper on the website**, bound to the character by a game-issued pairing code (ADR-0022). Not a
    separate web identity — one author per person across both surfaces.
15. Voice calls via temporary Teamspeak channels, rate-limited (ADR-0020)
16. Dispatch for police + EMS (LSPD = Mission Row, EMS = Pillbox). **No fire service** — GTA ships no
    enterable fire station, and an emergency service without a building is worse than none (ADR-0012).
17. Criminal layer — drugs, robberies

## Platform

18. txAdmin configured, permissions, ban system
19. Teamspeak server + UID linking, access driven by the whitelist (ADR-0015)
20. Server convars hardened — `sv_entityLockdown`, entity lockdown mode, `sv_kick_players_cnl_*` set
21. Scheduled restart automation for the weekend window — Fri 19:00 start, Sun 22:00 stop (ADR-0010)
22. Event security — every client event validated server-side

## Operations

23. Website (Node/TS) live, with the application form + application status page
24. Rules page, accepted by players
25. Player onboarding — first job, first property, expectations
26. Staff SOP for bans and applications
27. Automated backups — hourly dumps + binlog PITR, offsite encrypted, retention 7d/4w/12m (ADR-0006)
28. **One proven full restore** into an empty database, FXServer booted against it
29. Discord OAuth application + staff bot with approve/reject buttons (ADR-0007)
30. Two DB users with split privilege: `fivem` full, `website` INSERT-only on applications (ADR-0007)
31. Application state machine: submitted → under review → approved / rejected

## Design principles

- **Farming exists but is never mandatory.** A guaranteed Stütze provides a floor so nobody is stuck at zero,
  but is sized **below** subsistence so idling is never worth doing. Every aspirational purchase — vehicle,
  property, tuning, weapons — must be earnable without touching a farm loop (ADR-0009).
- **Vanilla geography.** GTA's map and landmarks are used as-is. "Vanilla" does **not** mean "no scripts"
  (that would contradict ADR-0002) nor "every building is GTA's" (ADR-0012) — interiors are repurposed.
- **Generic primitives.** Ownership is one system that houses, vehicles and businesses are data for, so
  later features are rows rather than new subsystems. The same pattern applies to the phone: one device
  concept, one account concept, several apps on top.
- **Downtime is the reset.** The server is down Monday–Thursday; nothing decays while it is off (ADR-0004).
- **Nothing is lost.** Persistent entities are server-owned; the world survives indefinitely. This applies to
  *the world* — property, vehicles, money — and deliberately **not** to social posts (ADR-0019).

## Not decided yet

- **Economy numbers** — Stütze amount, all prices, wages, sink costs (structure fixed in ADR-0009)

- **Teamspeak channel automation** — the query-based call lifecycle needs an early end-to-end proof before
  phone UI is built on it (ADR-0020)
- **Interior count** — reachable stock apartments to be counted on a live server (ADR-0013)
- **Contacts** — the contacts app is implied by Messages but its model is not yet decided
- **Website author resolution** — ADR-0022 leaves one accepted gap: `INSERT ON peeper_posts` does not
  constrain `author_character` to a linked Discord ID. A stored procedure that takes the Discord ID
  closes it properly. Recorded in `database/grants.sql`; not yet written.