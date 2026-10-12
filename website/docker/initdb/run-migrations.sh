#!/usr/bin/env bash
# =============================================================================
# run-migrations.sh — apply pending migrations, then the grants. Every deploy.
#
# WHY THIS EXISTS
#
# The MariaDB entrypoint runs /docker-entrypoint-initdb.d exactly ONCE, on an
# empty data directory. After that it is skipped forever, which meant that fixing
# grants.sql deployed nothing: the volume was already populated, so the corrected
# statements never ran. A schema fix reached the repository and silently did not
# reach the database. That is the whole reason this exists.
#
# It runs as a one-shot service on every `docker compose up`, and the application
# declares `depends_on: service_completed_successfully`, so the app does not start
# against a schema that is behind.
#
# WHY THE MIGRATIONS LIVE IN A SUBFOLDER
#
# So the entrypoint cannot run them. If it did, a fresh volume would get them
# applied twice — once by the entrypoint, once by this script — and the second
# pass would execute every ALTER in the chain. Exactly one path applies a
# migration.
#
# HOW "ALREADY APPLIED" IS DECIDED
#
# `schema_migrations` is created by migration 001, so its mere PRESENCE means 001
# ran. That is the whole signal:
#
#   table absent   -> nothing was ever applied here -> run the whole chain
#   table present  -> the old entrypoint path applied the chain but recorded
#                     nothing (nothing ever wrote to this table), so seed
#                     001..030 as applied and run anything NEWER
#
# Without that rule the second run would re-execute every ALTER, because nothing
# was recorded the first time.
#
# --dry-run performs the real reads and stubs every write, so it answers "what is
# pending on THIS database" without changing anything.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$HERE/migrations}"
DB_NAME="${MARIADB_DATABASE:-nifty_life}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
# root is right in the deploy: this service creates accounts and grants
# privileges, which nothing else is allowed to do. The variable exists so the
# script can be pointed at a database as somebody else during a dry run.
DB_USER="${DB_USER:-root}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

for var in MARIADB_ROOT_PASSWORD GAME_DB_PASSWORD DB_PASSWORD DB_ADMIN_PASSWORD \
           WEB_DB_HOST GAME_DB_HOST; do
  if [ -z "${!var:-}" ]; then
    echo "run-migrations.sh: ${var} is not set." >&2
    exit 1
  fi
done

mariadb_exec() { mariadb --protocol=tcp -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${MARIADB_ROOT_PASSWORD}" "$DB_NAME" "$@"; }

q_read() { mariadb_exec -N -B -e "$1"; }
q_write() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] would run: $1"; return 0; fi
  mariadb_exec -e "$1"
}
q_file() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "   [dry-run] would execute $(basename "$1")"; return 0; fi
  mariadb_exec < "$1"
}

recorded() { printf '%s\n' "$APPLIED" | grep -qx "$1"; }

# ---- accounts first ----------------------------------------------------------
# Migrations 016 and 018 contain GRANT statements of their own, so the accounts
# have to exist before the chain runs. This used to be a file in the MariaDB
# entrypoint's initdb.d, which meant a bind mount from the compose context into
# a directory the deploy host does not expose. It runs here instead: this service
# already talks to the database as root, and CREATE USER IF NOT EXISTS is
# idempotent, so calling it on every deploy costs nothing.
echo "ensuring the three accounts exist"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "   [dry-run] would run 000-users.sh"
else
  bash "$HERE/000-users.sh"
fi

# ---- what has already been applied ------------------------------------------
HAS_TABLE="$(q_read "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='schema_migrations';")"

if [ "$HAS_TABLE" = "0" ]; then
  echo "schema_migrations is absent — this database has never been migrated."
  APPLIED=""
else
  echo "schema_migrations is present — recording the chain the old entrypoint path already applied."
  APPLIED="$(q_read "SELECT version FROM schema_migrations;")"
  for f in "$MIGRATIONS_DIR"/[0-9][0-9][0-9]_*.sql; do
    v="$(basename "$f" .sql)"
    if ! recorded "$v"; then
      q_write "INSERT IGNORE INTO schema_migrations (version) VALUES ('${v}');"
      APPLIED="${APPLIED}
${v}"
    fi
  done
fi

# ---- pending migrations ------------------------------------------------------
PENDING=0
for f in "$MIGRATIONS_DIR"/[0-9][0-9][0-9]_*.sql; do
  v="$(basename "$f" .sql)"
  if recorded "$v"; then continue; fi
  PENDING=$((PENDING + 1))
  echo "applying $v"
  q_file "$f"
  q_write "INSERT IGNORE INTO schema_migrations (version) VALUES ('${v}');"
  APPLIED="${APPLIED}
${v}"
done

if [ "$PENDING" -eq 0 ]; then
  echo "no pending migrations — schema is up to date."
else
  echo "${PENDING} migration(s) applied."
fi

# ---- grants, every deploy ----------------------------------------------------
# CREATE USER IF NOT EXISTS and GRANT are both idempotent, so this costs nothing
# when nothing changed and repairs the privileges the moment the file changes.
if [ "$DRY_RUN" -eq 1 ]; then
  echo "   [dry-run] would run grants.sh"
else
  echo "applying grants"
  bash "$HERE/grants.sh"
fi

echo "run-migrations.sh: done."