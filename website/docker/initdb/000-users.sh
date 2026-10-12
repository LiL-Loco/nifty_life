#!/usr/bin/env bash
# =============================================================================
# 000-users.sh — create the three accounts BEFORE the schema exists.
#
# WHY THIS HAS TO RUN FIRST, AND WHY NOBODY NOTICED
#
# Migration 016 and migration 018 contain GRANT statements of their own:
#
#   GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email
#     TO 'nifty_website'@'localhost';
#
# Those run while the migrations are still being applied, so the account has to
# exist by then. On the bare-metal database the accounts were created first and
# the schema was applied afterwards, so the order was never exercised from
# scratch — the project could not build a NEW database at all. It only surfaced
# because the compose stack creates an empty one, and the MariaDB entrypoint
# aborts the entire init on the first error: 019 through 030 silently never ran,
# and grants.sql never got a chance to either.
#
# The 0-prefix puts this file ahead of 001_core_identity.sql.
#
# WHY EACH ACCOUNT IS CREATED TWICE
#
# The migrations grant to 'localhost'. The application connects from a container
# address. Neither can be dropped without breaking the other, so each account is
# created at both hosts. The @'localhost' rows exist only so migration 016/018
# can succeed; nothing ever connects from inside this container, so they stay
# inert. The real privileges come from 900-grants.sh, which applies them at the
# deploy host.
# =============================================================================
set -euo pipefail

# MARIADB_ROOT_PASSWORD is the name the container actually receives; the compose
# file does not duplicate it under a second key.
for var in MARIADB_ROOT_PASSWORD GAME_DB_PASSWORD DB_PASSWORD DB_ADMIN_PASSWORD \
           WEB_DB_HOST GAME_DB_HOST; do
  if [ -z "${!var:-}" ]; then
    echo "000-users.sh: ${var} is not set." >&2
    exit 1
  fi
done

# Escape a value for use as a sed REPLACEMENT (& means "the match", \ escapes,
# | is the delimiter). Without this, a password containing any of those
# characters yields broken SQL or the wrong password.
esc() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

GAME_PW="$(esc "$GAME_DB_PASSWORD")"
WEB_PW="$(esc "$DB_PASSWORD")"
ADMIN_PW="$(esc "$DB_ADMIN_PASSWORD")"

# LOCAL_HOST is where migrations 016/018 grant to. DEPLOY_HOST is where the
# application and the game server actually connect from.
LOCAL_HOST='localhost'
WEB_DEPLOY="$(esc "$WEB_DB_HOST")"
GAME_DEPLOY="$(esc "$GAME_DB_HOST")"

# TCP, not a unix socket. This used to say `--protocol=socket`, which was correct
# while the MariaDB entrypoint ran this file INSIDE the database container. It no
# longer does: run-migrations.sh calls it from a separate container, where there
# is no socket at all and the database is reachable only over the network.
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"

mariadb --protocol=tcp -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS 'nifty'       @'${LOCAL_HOST}' IDENTIFIED BY '${GAME_PW}';
CREATE USER IF NOT EXISTS 'nifty'       @'${GAME_DEPLOY}' IDENTIFIED BY '${GAME_PW}';
GRANT ALL PRIVILEGES ON nifty_life.* TO 'nifty'@'${GAME_DEPLOY}';

CREATE USER IF NOT EXISTS 'nifty_website' @'${LOCAL_HOST}' IDENTIFIED BY '${WEB_PW}';
CREATE USER IF NOT EXISTS 'nifty_website' @'${WEB_DEPLOY}' IDENTIFIED BY '${WEB_PW}';

CREATE USER IF NOT EXISTS 'nifty_admin'   @'${LOCAL_HOST}' IDENTIFIED BY '${ADMIN_PW}';
CREATE USER IF NOT EXISTS 'nifty_admin'   @'${WEB_DEPLOY}' IDENTIFIED BY '${ADMIN_PW}';
SQL

echo "000-users.sh: accounts created at ${LOCAL_HOST} and ${WEB_DB_HOST} (game: ${GAME_DB_HOST})."