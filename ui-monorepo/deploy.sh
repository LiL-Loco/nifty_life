#!/bin/bash
# Build every NUI panel and put the artefacts where the resources expect them.
#
# WHY THIS FILE EXISTS
#
# The panels are built here and deployed here — there is no CI on this host. Until
# this existed the copy was done by hand, and a green `bun run build` in the
# monorepo proved nothing about what was actually running: on 2026-10-20 a build
# succeeded and the deployed nifty-world/ui/dist was still five hours old. A build
# that nobody copies is not a deployment.
#
# It copies rather than symlinks on purpose. FiveM serves a resource from one
# directory; a symlink into the monorepo would mean the served files depend on a
# path outside the resource, which is exactly the kind of thing that works until
# someone moves a folder.
#
# Usage:  ./deploy.sh          build + copy
#         ./deploy.sh --copy   copy only (when the source is already on this host)

set -euo pipefail

MONO=/root/ui-monorepo
RES=/home/fivem/server-data/resources/[nifty]
export PATH="$HOME/.bun/bin:$PATH"

# package -> destination, relative to the resource root. The difference matters:
# six panels land in ui/dist and are declared as `ui_page`, the loading screen
# lands in dist and is declared as `loadscreen`.
copy_one() {
  local pkg="$1" dest="$2"
  local src="$MONO/packages/$pkg/dist"

  if [ ! -d "$src" ]; then
    echo "  FEHLT  $pkg — kein dist/ (Build fehlgeschlagen?)" >&2
    return 1
  fi
  if [ ! -f "$src/index.html" ]; then
    echo "  FEHLT  $pkg — dist/index.html existiert nicht" >&2
    return 1
  fi

  local target="$RES/$dest"
  rm -rf "$target"
  mkdir -p "$target"
  cp -a "$src/." "$target/"
  chown -R fivem:fivem "$target"
  printf "  %-14s -> %-28s (%s bytes index.html)\n" "$pkg" "$dest" "$(stat -c%s "$src/index.html")"
}

if [ "${1:-}" != "--copy" ]; then
  echo "== bauen =="
  cd "$MONO"
  bun run build
  echo
fi

echo "== kopieren =="
copy_one chat         nifty-chat/ui/dist
copy_one creator      nifty-creator/ui/dist
copy_one clothing     nifty-clothing/ui/dist
copy_one inventory    nifty-inventory/ui/dist
copy_one world        nifty-world/ui/dist
copy_one armwrestling nifty-armwrestling/ui/dist
copy_one loadscreen   nifty-loadscreen/dist

echo
echo "fertig. Neustart noetig:  systemctl restart fivem"
