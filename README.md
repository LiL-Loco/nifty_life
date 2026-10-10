# Nifty Life 2.0

A whitelisted, weekend-only FiveM roleplay server. No framework, no purchased assets, GTA V's own
geography. Built by one person, launched only when complete.

- **Plan:** [docs/PLAN.md](./docs/PLAN.md)
- **Vocabulary:** [CONTEXT.md](./CONTEXT.md)
- **Scope:** [docs/launch-gate.md](./docs/launch-gate.md) — frozen, 27 items
- **Housing plan:** [docs/housing-catalogue.md](./docs/housing-catalogue.md)
- **Decisions:** [docs/adr/](./docs/adr/)

## Build order (ADR-0014)

1. Schema
2. Persistence layer
3. Identity
4. Money and inventory
5. Generic systems (jobs, ownership)
6. Content

A **vertical slice** — connect, create a character, take a job, earn, buy, own, reconnect, still there —
is proven privately before any content work begins.

## Non-negotiable invariants

These are enforced in the data model, not left to discipline. Breaking any of them breaks an ADR.

- **No player-owned row is ever keyed by FiveM slot ID.** Slot IDs are recycled (ADR-0001). The
  `sessions` table holds them as ephemeral data only, and is the single place they appear.
- **One character per account** (ADR-0008), enforced by a `UNIQUE` constraint, not by application logic.
- **The website cannot approve.** `applications` is INSERT-only for the website DB user (ADR-0007).
- **Prices are data, never code** (ADR-0009). Every tunable number lives in the `settings` table.
- **Ownership is one primitive.** Housing, vehicles and businesses are rows in `properties`, not three
  subsystems.

## Layout

```
database/migrations/     SQL migrations, numbered, never edited after release
resources/[nifty]/       FiveM resources; [nifty] is the resource group
website/                 Node/TS website + Discord staff bot (ADR-0007)
docs/                    Plan, ADRs, housing catalogue
```

## Setup

Database credentials go in `server.cfg` (git-ignored) or a `.env` — never in code or a commit.
Copy `server.cfg.example` as a starting point.