# Backup architecture: hourly dumps plus binlog point-in-time recovery

Loss is designed out, not hoped against. MariaDB runs with binary logging enabled so the database can be
replayed to any moment in time; hourly full dumps plus continuous binlogs give a recovery point of
**seconds rather than hours**.

## Shape

- **Hourly full dump** during play, via `mariadb-dump`. This is the base layer.
- **Binary logs** (`log_bin`) retained and rotated. This is what actually turns "hourly" into "seconds" —
  restoring the latest dump and replaying binlogs forward recovers the database to a precise timestamp.
- **Dump on clean shutdown and before every start.** The on-shutdown dump covers logical errors; the
  pre-start dump guarantees you never boot into a state you cannot describe.
- **Offsite, encrypted copies** (age or gpg) to storage outside the server machine. A dump on the same
  disk protects against nothing physical.
- **Retention:** 7 daily, 4 weekly, 12 monthly. Monthly copies are what let us roll back a mistake made
  weeks ago.
- **Whole-data-folder backups**, not just the database. This covers the server configuration, txAdmin's own
  data directory, and custom resources — "nothing lost" includes configuration, not only rows.
- **Restore drill**: restore the latest dump into an empty database, replay the binlogs, boot FXServer
  against it, and verify. Run it once before launch, then on a schedule. An untested backup is a hope.

## Consequences

- Encryption at rest is not optional: these dumps contain player identity data and application answers.
- RPO and RTO become stated, documented numbers rather than assumptions — RPO seconds, RTO bounded by
  how long a full restore plus boot takes, which the drill measures for real.
- Because there are no players before launch (ADR-0003), a scheduled restore drill is the only mechanism
  that can detect a silently broken backup. It cannot be "done later, when there's time".
- The exact restore procedure must be verified against the real deployment rather than assumed from
  documentation; the drill is what makes that verification real.
- Storage grows continuously through binlogs, so log rotation and retention pruning are part of the design,
  not maintenance debt.