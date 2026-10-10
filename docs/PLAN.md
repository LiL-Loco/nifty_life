# Nifty Life 2.0 — Plan

A whitelisted, weekend-only FiveM roleplay server. No framework, no purchased assets, GTA V's own
geography. Built entirely by one person, launched only when complete.

- **Vocabulary:** [CONTEXT.md](../CONTEXT.md) — the canonical terms. If a word disagrees with this file, it is wrong.
- **Scope definition:** [launch-gate.md](./launch-gate.md) — the closed, frozen list of what must exist at launch.
- **Decisions:** [adr/](./adr/) — 15 ADRs, each a decision with its reasoning.

## What this is

Nifty Life 2.0: 20–40 players, 48 slots, online Friday 19:00 to Sunday 22:00. Players apply through a
website, get reviewed by a human, and play one character that persists indefinitely. Voice is Teamspeak,
linked to the whitelist. Money comes from jobs and businesses; a guaranteed Stütze exists so nobody is ever
stuck, but no player is ever *required* to grind. Jobs are police, EMS, taxi and mechanic.

## Decisions at a glance

| # | Decision |
|---|---|
| 0001 | Target Legacy, not Enhanced — but keep the data layer ID-safe so it stays reversible |
| 0002 | Hand-rolled core, no framework; no community scripts that assume one |
| 0003 | Build complete before launch; no public beta |
| 0004 | Permanent world, frozen while the server is offline |
| 0005 | MariaDB via `oxmysql`; never MSSQL |
| 0006 | Hourly dumps + binlog PITR, offsite encrypted, restore-tested |
| 0007 | Discord OAuth whitelist, Tier 1 coupling only, manual review |
| 0008 | One character per person; jobs open to anyone |
| 0009 | Unconditional Stütze, optional farming; prices deferred |
| 0010 | Fri 19:00 – Sun 22:00, 48 slots, one restart, connections refused outside |
| 0011 | Lua for game logic, HTML/CSS/JS for NUI |
| 0012 | No purchased MLO — stock GTA interiors; no fire service |
| 0013 | Housing via teleporters into GTA apartment interiors, free to own |
| 0014 | Build order: spine first, content last, vertical slice to prove it |
| 0015 | Teamspeak-based voice, closed to non-approved accounts |
| 0016 | Bob74_IPL for interior loading — selective, not load-everything |

## Build order

Schema → persistence → identity → money/inventory → generic systems (jobs, ownership) → content.

A **vertical slice** — connect, create character, take a job, earn, buy, own, reconnect, still there — is
proven privately before any content work starts. See ADR-0014.

## The three things most likely to hurt

1. **ADR-0003 + ADR-0002 combined.** No framework means nothing to launch until the core works, and no public
   launch means no players to tell you it doesn't. Solo, this is the burnout shape.
2. **The Stütze amount (ADR-0009).** Unconditional payment with no eligibility means the amount is the only
   thing preventing AFK from being the optimal strategy. If it ever reaches subsistence, the economy inverts.
   This is the single number most likely to be got wrong.
3. **Housing pool (ADR-0013).** The larger apartment set is GTA Online and probably not loadable in FiveM.
   If the reachable pool lands near four rather than twelve, housing becomes the binding constraint on the
   entire economy.

## Open items

- **Economy numbers** — Stütze amount, all prices, wages, sink costs. Structure is fixed (ADR-0009);
  numbers deliberately deferred. Any placeholder committed to the database must be bulk-editable.
- **Teamspeak licensing** — verify the licence tier covers 48 slots before launch (ADR-0015).
- **Interior count verification** — count reachable stock apartments on a live server before committing to a
  housing count (ADR-0013).
- **Teamspeak onboarding friction** — players must install and configure Teamspeak before their first session;
  this is the largest expected source of lost applicants and is not yet written (launch-gate item 20).