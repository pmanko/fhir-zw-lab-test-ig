#!/usr/bin/env bash
# Loads the main Lab IG's conformance resources (and its zw.fhir.ig.core
# dependency) onto a FHIR server, so $validate?profile=... works there.
# Both come from resolved packages — this repo holds no conformance resources
# of its own and no longer sits next to the IG source.
# Usage:
#   karate/scripts/load-ig.sh [FHIR_BASE_URL]            # default http://localhost:8090/fhir
#   karate/scripts/load-ig.sh --local [FHIR_BASE_URL]    # lab IG from local #dev build
set -euo pipefail
cd "$(dirname "$0")/.."   # karate/

# pass a leading --local through to the resolver, then take the base URL
RESOLVE_ARGS=()
if [ "${1:-}" = "--local" ]; then RESOLVE_ARGS+=(--local); shift; fi
BASE="${1:-${SHR_URL:-http://localhost:8090/fhir}}"

LAB_PKG="$(scripts/resolve-lab-package.sh "${RESOLVE_ARGS[@]}")"

# zw.fhir.ig.core from the local FHIR cache (current preferred, else any pinned
# version present); the resolver only handles the lab package.
CORE_PKG=""
for c in "$HOME/.fhir/packages/zw.fhir.ig.core#current/package" \
         "$HOME/.fhir/packages"/zw.fhir.ig.core#*/package; do
  [ -d "$c" ] && CORE_PKG="$c" && break
done
[ -n "$CORE_PKG" ] || echo "  (note: no zw.fhir.ig.core package in ~/.fhir/packages — core profiles won't be loaded)" >&2

python3 - "$BASE" "$LAB_PKG" "$CORE_PKG" <<'PY'
import json
import os
import sys
import urllib.parse
import urllib.request

base, lab, core = sys.argv[1], sys.argv[2], sys.argv[3]
CONFORMANCE = ('CodeSystem', 'ValueSet', 'StructureDefinition')

def put(resource):
    rt = resource['resourceType']
    canonical = resource.get('url')
    if canonical:
        # conditional update by canonical URL: avoids id collisions between
        # packages (e.g. both IGs define an SD with id 'citizenship')
        resource = dict(resource)
        resource.pop('id', None)
        target = f"{base}/{rt}?url={urllib.parse.quote(canonical, safe='')}"
    else:
        target = f"{base}/{rt}/{resource['id']}"
    data = json.dumps(resource).encode()
    req = urllib.request.Request(target, data=data, method='PUT',
                                 headers={'Content-Type': 'application/fhir+json'})
    with urllib.request.urlopen(req) as resp:
        return resp.status

def load_dir(path, label):
    if not path or not os.path.isdir(path):
        print(f"  (skipping {label}: {path or '(none)'} not found)")
        return
    ok = failed = 0
    for name in sorted(os.listdir(path)):
        if not name.endswith('.json') or name.startswith('.'):
            continue
        try:
            with open(os.path.join(path, name)) as f:
                r = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if r.get('resourceType') not in CONFORMANCE or 'id' not in r:
            continue
        try:
            put(r)
            ok += 1
        except Exception as e:
            failed += 1
            print(f"  FAILED {name}: {e}")
    print(f"  {label}: {ok} loaded, {failed} failed")

print(f"Loading conformance resources onto {base}")
load_dir(core, 'zw.fhir.ig.core')
load_dir(lab, 'zw.fhir.ig.lab')
PY
