#!/usr/bin/env bash
# Resolves the main Lab IG (zw.fhir.ig.lab) package directory that the data and
# load scripts derive their payloads from, and prints that directory's path on
# stdout. All diagnostics go to stderr so callers can capture the path cleanly:
#
#   PKG="$(scripts/resolve-lab-package.sh)"          # remote branch build (default)
#   PKG="$(scripts/resolve-lab-package.sh --local)"  # local ~/.fhir cache (#dev)
#   ZW_LAB_PKG=/path/to/extracted/package scripts/resolve-lab-package.sh
#
# Resolution order:
#   1. $ZW_LAB_PKG               — any pre-extracted package dir (e.g. a sibling
#                                  checkout's fsh-generated/resources)
#   2. --local                   — ~/.fhir/packages/zw.fhir.ig.lab#dev/package
#                                  (refreshed by running the publisher in the
#                                  main IG repo; fast inner loop)
#   3. default                   — download + cache the fork's branch build
#                                  package.tgz from build.fhir.org
#
# Always prints the resolved package's id/version/date to stderr so a stale
# #dev cache can't silently produce outdated payloads.
set -euo pipefail
cd "$(dirname "$0")/.."   # karate/

# Branch build the main IG dependency is pinned to (keep in sync with
# sushi-config.yaml's zw.fhir.ig.lab version). Override with $LAB_PKG_URL.
LAB_BRANCH="${LAB_BRANCH:-lab-dep-snapshot}"
LAB_PKG_URL="${LAB_PKG_URL:-https://build.fhir.org/ig/pmanko/fhir-zw-lab-ig/branches/${LAB_BRANCH}/package.tgz}"
CACHE_DIR="target/lab-package"

note() { echo "$@" >&2; }

report() {
  # $1 = package dir; print its package.json identity to stderr
  local pkg="$1/package.json"
  if [ -f "$pkg" ]; then
    python3 - "$pkg" >&2 <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
print("  zw.fhir.ig.lab package: %s#%s (built %s)" % (
    p.get("name", "?"), p.get("version", "?"), p.get("date", "?")))
PY
  fi
}

if [ -n "${ZW_LAB_PKG:-}" ]; then
  [ -d "$ZW_LAB_PKG" ] || { note "ERROR: ZW_LAB_PKG=$ZW_LAB_PKG not a directory"; exit 1; }
  note "lab package: \$ZW_LAB_PKG override → $ZW_LAB_PKG"
  report "$ZW_LAB_PKG"
  echo "$ZW_LAB_PKG"
  exit 0
fi

if [ "${1:-}" = "--local" ]; then
  DEV="$HOME/.fhir/packages/zw.fhir.ig.lab#dev/package"
  [ -d "$DEV" ] || { note "ERROR: $DEV not found — run the IG publisher in the main IG repo to populate the #dev cache"; exit 1; }
  note "lab package: local #dev cache → $DEV"
  report "$DEV"
  echo "$DEV"
  exit 0
fi

# default: download + cache the fork branch build
mkdir -p "$CACHE_DIR"
note "lab package: downloading $LAB_PKG_URL"
if ! curl -fsSL -o "$CACHE_DIR/package.tgz" "$LAB_PKG_URL"; then
  note "ERROR: could not download $LAB_PKG_URL"
  note "       (is pmanko/fhir-zw-lab-ig registered with the FHIR auto-builder and has branch '$LAB_BRANCH' built?)"
  note "       Fall back to a local main-IG build with: $(basename "$0") --local"
  exit 1
fi
rm -rf "$CACHE_DIR/package"
tar -xzf "$CACHE_DIR/package.tgz" -C "$CACHE_DIR"
report "$CACHE_DIR/package"
# absolute path so callers in other dirs resolve it correctly
echo "$(cd "$CACHE_DIR/package" && pwd)"
