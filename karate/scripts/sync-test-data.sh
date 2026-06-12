#!/usr/bin/env bash
# Derives the test payloads from the main Lab IG's published examples, so the
# test data cannot drift from the spec. Source is the zw.fhir.ig.lab *package*
# (resolved by resolve-lab-package.sh — remote branch build by default, or
# `--local` for the ~/.fhir #dev cache), NOT a sibling fsh-generated/ folder:
# this repo no longer lives next to the IG source.
#
#   karate/scripts/sync-test-data.sh            # remote branch build (reproducible)
#   karate/scripts/sync-test-data.sh --local    # local main-IG #dev build (fast loop)
#   ZW_LAB_PKG=/path/to/package karate/scripts/sync-test-data.sh
#
# Two outputs:
#   karate/data/*.json        wire payloads (valid + INVALID variants) the Karate
#                             suite and simulators submit — NOT published
#   input/resources/*.json    the VALID wire bundles, with id + meta.profile, so
#                             the IG publisher renders and profile-validates them
set -euo pipefail
cd "$(dirname "$0")/.."   # karate/

SRC="$(scripts/resolve-lab-package.sh "$@")"
mkdir -p data ../input/resources

python3 - "$SRC" <<'PY'
import copy
import json
import os
import sys
from urllib.parse import quote

src = sys.argv[1]
CANONICAL = 'http://mohcc.gov.zw/fhir/lab'

def load(name):
    # package layout keeps examples under example/, conformance at the root;
    # a raw fsh-generated/resources dir keeps everything flat — try both.
    for cand in (os.path.join(src, name), os.path.join(src, 'example', name)):
        if os.path.exists(cand):
            with open(cand) as f:
                return json.load(f)
    raise FileNotFoundError(name + ' (looked in ' + src + ' and ' + src + '/example)')

def save(name, obj):
    with open(os.path.join('data', name), 'w') as f:
        json.dump(obj, f, indent=2)
        f.write('\n')

def save_published(name, bundle, profile):
    # the valid wire bundle, fit for the IG publisher: needs an id, and a
    # meta.profile so it is validated against (and rendered as an example of)
    # the main IG's bundle profile.
    pub = copy.deepcopy(bundle)
    pub['id'] = name
    meta = pub.setdefault('meta', {})
    meta['profile'] = [CANONICAL + '/StructureDefinition/' + profile]
    with open(os.path.join('..', 'input', 'resources', 'Bundle-' + name + '.json'), 'w') as f:
        json.dump(pub, f, indent=2)
        f.write('\n')

# ── Order transaction bundle (Lab Order Placer payload) ──────────────────────
order = load('Bundle-example-zw-lab-order-bundle.json')
order.pop('id', None)

# The Task/ServiceRequest reference the ordering facility (Location) and the
# receiving laboratory (Organization), which won't exist on a fresh server.
# Append them as conditional-create entries so the transaction is
# self-contained and idempotent for shared context resources.
facility = load('Location-example-order-facility.json')
laboratory = load('Organization-example-national-virology-lab.json')
lab_code = laboratory['identifier'][0]
order['entry'].append({
    'fullUrl': 'urn:uuid:5a3952e2-1c1a-4a6b-9c5d-0b6e9a3e0005',
    'resource': facility,
    'request': {
        'method': 'POST',
        'url': 'Location',
        'ifNoneExist': 'name=' + quote(facility['name']),
    },
})
order['entry'].append({
    'fullUrl': 'urn:uuid:5a3952e2-1c1a-4a6b-9c5d-0b6e9a3e0006',
    'resource': laboratory,
    'request': {
        'method': 'POST',
        'url': 'Organization',
        'ifNoneExist': 'identifier=' + quote(lab_code['system'] + '|' + lab_code['value'], safe=''),
    },
})

# Rewrite intra-bundle relative references to the entry fullUrls (urn:uuid) so
# the server rewires them to the created resources when processing the
# transaction.
refmap = {}
for e in order.get('entry', []):
    r = e.get('resource', {})
    if r.get('id'):
        refmap[r['resourceType'] + '/' + r['id']] = e['fullUrl']

def rewrite(node):
    if isinstance(node, dict):
        if node.get('reference') in refmap:
            node['reference'] = refmap[node['reference']]
        for v in node.values():
            rewrite(v)
    elif isinstance(node, list):
        for v in node:
            rewrite(v)

for e in order['entry']:
    rewrite(e['resource'])
    e['resource'].pop('id', None)   # POST entries get server-assigned ids
    e['resource'].pop('text', None)
save('order-bundle.json', order)
save_published('zw-test-order-wire', order, 'zw-lab-order-bundle')

# Invalid variant: ServiceRequest without a test code, Patient without the
# required EHR identifier — must fail ZWLabOrderBundle profile validation.
bad = copy.deepcopy(order)
for e in bad['entry']:
    r = e['resource']
    if r['resourceType'] == 'ServiceRequest':
        r.pop('code', None)
    if r['resourceType'] == 'Patient':
        r.pop('identifier', None)
        e['request'].pop('ifNoneExist', None)
save('order-bundle-invalid.json', bad)

# Offline sandboxes cannot validate LOINC (HAPI only accepts LOINC via its
# terminology uploader), and an unknown code system inside a bound
# CodeableConcept fails validation. The wire payloads therefore carry only the
# national codes — which is what the profiles require. The IG examples keep
# the LOINC translations; validating them is deferred to a
# terminology-capable validator.
def strip_loinc_codings(node):
    if isinstance(node, dict):
        for key in ('code',):
            cc = node.get(key)
            if isinstance(cc, dict) and isinstance(cc.get('coding'), list):
                kept = [c for c in cc['coding'] if c.get('system') != 'http://loinc.org']
                if kept:
                    cc['coding'] = kept
        for v in node.values():
            strip_loinc_codings(v)
    elif isinstance(node, list):
        for v in node:
            strip_loinc_codings(v)

# ── Report document bundle (Lab Result Provider payload, stored whole) ───────
report = load('Bundle-example-zw-vl-report-bundle.json')
report.pop('id', None)
for e in report.get('entry', []):
    r = e.get('resource', {})
    # drop IG-publisher-generated narrative the package carries (the wire
    # payload doesn't need it; it also references main-IG pages that don't
    # exist here). The order bundle strips entry text the same way.
    r.pop('text', None)
    if r.get('resourceType') in ('Observation', 'DiagnosticReport'):
        strip_loinc_codings(r)
save('report-bundle.json', report)
save_published('zw-test-report-wire', report, 'zw-lab-report-bundle')

# Invalid variant: DiagnosticReport without a test code, Patient without the
# required EHR identifier — must fail ZWLabReportBundle profile validation.
bad_report = copy.deepcopy(report)
for e in bad_report['entry']:
    r = e['resource']
    if r['resourceType'] == 'DiagnosticReport':
        r.pop('code', None)
    if r['resourceType'] == 'Patient':
        r.pop('identifier', None)
save('report-bundle-invalid.json', bad_report)

# ── Standalone result resources (provider creates these against live ids) ────
obs = load('Observation-example-zw-vl-observation.json')
for k in ('id', 'text', 'subject', 'basedOn', 'specimen'):
    obs.pop(k, None)
strip_loinc_codings(obs)
save('observation.json', obs)

dr = load('DiagnosticReport-example-zw-vl-diagnostic-report.json')
for k in ('id', 'text', 'subject', 'basedOn', 'specimen', 'result',
          'performer', 'resultsInterpreter'):
    dr.pop(k, None)
save('diagnostic-report.json', dr)

# ── Static search parameter files ─────────────────────────────────────────────
save('order-search-none.json', {
    'patient.identifier':
        'http://mohcc.gov.zw/fhir/lab/identifier/ehr-patient-id|NO-SUCH-PATIENT'
})

print('Wire payloads written to karate/data/')
print('Published examples written to input/resources/Bundle-zw-test-{order,report}-wire.json')
PY

echo
echo "Next: re-run scripts/build-simulator.sh (the simulator HTML embeds these payloads)."
