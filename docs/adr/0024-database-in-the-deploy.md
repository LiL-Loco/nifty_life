# Database in the deploy, not on the host

**Status:** accepted (2026-10-11)
**Supersedes:** the bare-metal assumption in ADR-0005 and ADR-0006 — it does not
supersede their decisions about *which* engine and *why* backups matter.

## Context

The website deploys to Coolify, which builds it with Nixpacks into a container.
Its configuration carried `DB_HOST=127.0.0.1`, which is correct for local
development and meaningless inside a container: there, loopback is the container
itself, not the machine running MariaDB. The first deployment therefore came up
with no database it could reach, and the schema had no way to exist in that
environment.

Two arrangements were possible:

1. Leave MariaDB bare-metal and let the container reach it.
2. Run MariaDB as a service beside the application, inside the deploy.

The owner chose **2**, accepting that a database engine becomes part of a
container-based deployment. This ADR records what that costs, because ADR-0006
described a backup architecture that a stock MariaDB container does not provide.

## Decision

`website/docker-compose.yml` runs `app` and `mariadb` on a fixed subnet
(`172.30.0.0/24`). `app` reaches the database by service name, not by address.
On first boot with an empty data volume, the MariaDB entrypoint executes
`website/docker/initdb/` in this order:

- `000-users.sh` — creates the three accounts, at two hosts each.
- `001…030_*.sql` — the migrations, copied byte-identically from
  `database/migrations/`.
- `900-grants.sh` — applies the privileges from `database/grants.sql`.

**The project could not build a new database before this.** Migrations 016 and
018 contain GRANT statements of their own
(`GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email TO
'nifty_website'@'localhost'`), so the accounts have to exist before the schema
does. The documented order — schema, then `grants.sql` — therefore cannot work
from scratch, and on the bare-metal database it never did because the accounts
already existed. The MariaDB entrypoint aborts the entire init on the first
error, so migrations 019 through 030 and the grants were silently skipped: the
container came up "healthy" with 31 tables, no accounts, and no privileges.
`000-users.sh` exists for that reason, and it creates each account at
`localhost` as well as at the deploy host, because the migrations grant to
`localhost` and the application connects from a container address. The
`@'localhost'` rows stay inert — nothing connects from inside the MariaDB
container.

The MariaDB port is published on `127.0.0.1:3307` only. The game server on the
host still needs it, and that binding is what makes `GAME_DB_HOST=%` acceptable —
nothing outside the host can open a TCP connection to it.

## Consequences

**The grant host patterns had to change.** `database/grants.sql` binds the web
accounts to `'localhost'`, written for a loopback-reached MariaDB. No container
on any network is `localhost`, so every web query would have been denied and the
failure would have looked like a password problem. The deploy substitutes
`WEB_DB_HOST` (the compose subnet, so only containers on this network match) and
`GAME_DB_HOST` (`%`, because the game server's apparent source address depends on
how the published port is NATted, which is not something this repository
controls). The web boundary is therefore *narrower or equal* to what ADR-0007
assumed, not weaker — except that it is now a network boundary rather than a
host boundary, and a container that joins this network inherits the web grants.

**`grants.sql` cannot be applied as a `.sql` file.** The MariaDB entrypoint
performs no variable substitution on `.sql`, so the accounts would be created
with the literal `CHANGE_ME_*` placeholders and the failure would surface as an
"access denied" that never mentions a password. Hence `900-grants.sh`. The
template is a byte-identical copy of `database/grants.sql`, so the reasoning in
its comments cannot drift from the grants that are applied.

**The schema now exists in two places.** `website/docker/initdb/` is a
byte-identical copy of `database/migrations/`. They cannot share files — the
deploy clones only the website repository — so keeping them in sync is now a
manual obligation rather than an automatic one.

**What ADR-0006 still provides:** binary logging, because
`--log-bin` is set in the compose file. Point-in-time recovery remains possible.

**What ADR-0006 no longer provides, and nobody has rebuilt yet:** the hourly
`mariadb-dump`, the encrypted offsite copies, the 7/4/12 retention, and the
scheduled restore drill. A container with a volume is not a backup. Until those
exist, losing the `db_data` volume loses the database, and no drill would notice.

**The game server has to be repointed.** It connects through oxmysql
(`server.cfg`) and must now reach MariaDB at `127.0.0.1:3307` rather than
`127.0.0.1:3306`.

**The first boot takes a while** and the healthcheck allows 120 seconds of grace
before it starts reporting. Migrations run once per empty volume and are then
skipped, which is deliberate: a container is not allowed to re-apply migrations
to live data behind anyone's back.

## One stale comment in grants.sql

Building this surfaced a contradiction inside `database/grants.sql` itself. Line
37 grants `SELECT, INSERT ON nifty_life.applications` to `nifty_website`, and
line 24 describes submitting an application as the website's job. The
verification block at line 224 nevertheless claims:

    --   INSERT INTO applications (...)   -- denied: no INSERT

That line is wrong, and `database/verify.ps1` (line 273) asserts the opposite
explicitly — "PASS website can submit an application (allow)". The grant and the
tooling agree; only the comment is stale. It is left unfixed here because this
ADR is about the deployment, but it should be corrected before someone trusts
that comment.

## What was verified, and what was not

Verified by running the stack locally: all 30 migrations apply to an empty
volume, the three accounts are created, and the privilege boundary holds from the
application container's own address — the web pool can insert an application but
not update its status, not read wallets, not read `web_pairing_codes` and not
touch `staff`; the admin pool can flip a decision but not rewrite an applicant's
answers. Twenty checks, all as specified.

**Not verified:** `GAME_DB_HOST=%` is a guess about how the published port is
NATted on the deploy host, which cannot be reproduced on a Windows machine with
its own MariaDB. The game server's connection to `127.0.0.1:3307` has to be
confirmed on the real host.