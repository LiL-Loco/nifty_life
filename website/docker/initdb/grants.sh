#!/usr/bin/env bash
# =============================================================================
# 900-grants.sh — create the three database accounts, from the template.
#
# WHY THIS IS A .sh AND NOT A .sql
#
# The MariaDB entrypoint pipes *.sql straight into the server. It performs NO
# variable substitution, so a plain grants.sql would create the accounts with
# the literal passwords CHANGE_ME_GAME / CHANGE_ME_WEB / CHANGE_ME_ADMIN and
# fail silently: the schema comes up, the website then cannot authenticate, and
# the logs say "access denied" without ever mentioning a password.
#
# A .sh is executed with the environment available, which is what lets the
# passwords come from the deploy's secret store instead of from this repo.
#
# WHY THE HOST PATTERNS ARE SUBSTITUTED
#
# grants.sql binds the web accounts to 'localhost' because it was written for a
# bare-metal MariaDB reached over loopback. In compose the app connects from a
# container IP, so 'localhost' matches nothing and every query is denied. The
# substitute values must therefore be real host patterns, not names.
#
# The template itself is NOT modified: it stays a byte-identical copy of
# database/grants.sql so the reasoning in its comments cannot drift away from
# the grants that are actually applied.
# =============================================================================
set -euo pipefail

# Next to this script, not in the initdb.d root: the template is not something
# the entrypoint should ever see, let alone run.
TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/grants.sql.template"

# MARIADB_ROOT_PASSWORD is the name the container actually receives.
for var in MARIADB_ROOT_PASSWORD GAME_DB_PASSWORD DB_PASSWORD DB_ADMIN_PASSWORD \
           WEB_DB_HOST GAME_DB_HOST; do
  if [ -z "${!var:-}" ]; then
    echo "900-grants.sh: ${var} is not set — the accounts cannot be created." >&2
    echo "900-grants.sh: the schema is loaded but the website will not be able to connect." >&2
    exit 1
  fi
done

if [ ! -f "$TEMPLATE" ]; then
  echo "900-grants.sh: template missing at ${TEMPLATE}" >&2
  exit 1
fi

# Escape a value for use as a sed REPLACEMENT: & means "the match", \ escapes,
# and | is our delimiter. Without this a password containing any of those three
# characters produces either broken SQL or the wrong password.
esc() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

sed \
  -e "s|CHANGE_ME_GAME|$(esc "$GAME_DB_PASSWORD")|g" \
  -e "s|CHANGE_ME_WEB|$(esc "$DB_PASSWORD")|g" \
  -e "s|CHANGE_ME_ADMIN|$(esc "$DB_ADMIN_PASSWORD")|g" \
  -e "s|'@'localhost'|$(esc "'@'${WEB_DB_HOST}'")|g" \
  -e "s|'@'127.0.0.1'|$(esc "'@'${GAME_DB_HOST}'")|g" \
  "$TEMPLATE" \
  | mariadb --protocol=socket -u root -p"${MARIADB_ROOT_PASSWORD}" "${MARIADB_DATABASE:-nifty_life}"

echo "900-grants.sh: accounts created (web=${WEB_DB_HOST}, game=${GAME_DB_HOST}, admin=${WEB_DB_HOST})."