#!/usr/bin/env bash
# Generates simulator/ehr-simulator.html and simulator/lab-simulator.html —
# zero-dependency pages (open them straight from disk in any browser) that
# play one actor each: pick a payload, click Submit, and it POSTs to the
# conformance proxy / server you point it at. Both pages are rendered from
# the SAME template below; only the actor config (payloads, submit endpoint,
# pull queries) differs. Payloads are embedded from tests/karate/data/ so the
# pages work from file://. Re-run after changing the data files.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p simulator

python3 - <<'PY'
import json

def load(p):
    with open(p) as f:
        return json.load(f)

# One entry per actor. The HTML/JS template is shared; everything that
# differs between the EHR and the lab lives here.
ACTORS = {
    'ehr': {
        'file': 'simulator/ehr-simulator.html',
        'title': 'EHR Simulator',
        'subtitle': 'plays the Lab Order Placer / Result Consumer',
        'port': 8080,
        'payloads': [
            {'key': 'valid', 'label': 'Valid order bundle (from the IG example)',
             'data': load('data/order-bundle.json')},
            {'key': 'invalid', 'label': 'Invalid order bundle (missing code + identifier)',
             'data': load('data/order-bundle-invalid.json')},
            {'key': 'impilo', 'label': 'Real Impilo order sample',
             'data': load('data/impilo-order-sample.json')},
        ],
        'submit': {'label': 'Submit order (POST bundle)', 'path': '/'},
        'pulls': [
            {'label': 'Pull results (patient-scoped)', 'path': '/DiagnosticReport',
             'params': {'patient': 'Patient/9d480e52-5ae2-4c5d-bebb-1cdb9e3c4683'}},
            {'label': 'Pull results (unscoped — should be refused)', 'path': '/DiagnosticReport'},
        ],
        'freshen': [['EHR-ZW-00123', 'EHR-SIM-'], ['ZW-SPEC-2024-00456', 'SPEC-SIM-']],
    },
    'lab': {
        'file': 'simulator/lab-simulator.html',
        'title': 'Lab (LIMS) Simulator',
        'subtitle': 'plays the Order Fulfiller / Result Provider',
        'port': 8081,
        'payloads': [
            {'key': 'valid', 'label': 'Valid report document (from the IG example)',
             'data': load('data/report-bundle.json')},
            {'key': 'invalid', 'label': 'Invalid report document (missing code + identifier)',
             'data': load('data/report-bundle-invalid.json')},
        ],
        'submit': {'label': 'Submit report (POST /Bundle)', 'path': '/Bundle'},
        'pulls': [
            {'label': 'Pull orders (patient-scoped)', 'path': '/ServiceRequest',
             'params': {'patient.identifier': 'http://mohcc.gov.zw/fhir/lab/identifier/ehr-patient-id|EHR-ZW-00123'}},
            {'label': 'Pull orders (unscoped — should be refused)', 'path': '/ServiceRequest'},
        ],
        'freshen': [['EHR-ZW-00123', 'EHR-SIM-'], ['ZW-SPEC-2024-00456', 'SPEC-SIM-'],
                    ['ZW-LABDOC-2024-00456', 'LABDOC-SIM-']],
    },
}

TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>ZW Lab — __TITLE__</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, Segoe UI, Helvetica, Arial, sans-serif; max-width: 1000px;
         margin: 24px auto; padding: 0 16px; line-height: 1.45; }
  h1 { font-size: 20px; } h1 small { font-weight: normal; color: #777; font-size: 13px; }
  fieldset { border: 1px solid #bbb4; border-radius: 8px; margin-bottom: 14px; padding: 10px 14px; }
  legend { font-size: 12px; color: #888; padding: 0 6px; }
  label { font-size: 13px; margin-right: 14px; }
  input[type=text] { width: 320px; font-family: ui-monospace, monospace; font-size: 13px; padding: 4px 6px; }
  select { font-size: 13px; padding: 3px; }
  textarea { width: 100%; height: 260px; font-family: ui-monospace, monospace; font-size: 12px;
             border: 1px solid #bbb4; border-radius: 6px; padding: 8px; box-sizing: border-box; }
  button { font-size: 14px; padding: 7px 16px; border-radius: 6px; border: 1px solid #888a;
           cursor: pointer; margin-right: 8px; background: transparent; }
  button.primary { background: #1f6feb; color: white; border-color: #1f6feb; }
  #verdict { font-size: 14px; font-weight: 600; margin: 12px 0 6px; }
  #verdict.pass { color: #1a7f37; } #verdict.fail { color: #cf222e; } #verdict.info { color: #777; }
  #report .issue { border-left: 3px solid #cf222e; padding: 4px 10px; margin: 6px 0; font-size: 12.5px; }
  #report .issue b { text-transform: uppercase; font-size: 11px; color: #cf222e; margin-right: 6px; }
  #report .issue code { font-size: 11.5px; background: #8883; padding: 1px 5px; border-radius: 4px; }
  #report .issue .msg { margin-top: 2px; }
  #report .none { color: #1a7f37; font-size: 12.5px; margin: 6px 0; }
  #report .more { color: #777; font-size: 12px; margin: 6px 0; }
  pre#out { border: 1px solid #bbb4; border-radius: 6px; padding: 10px; font-size: 11.5px;
            max-height: 420px; overflow: auto; white-space: pre-wrap; }
</style>
</head>
<body>
<h1>ZW Lab — __TITLE__ <small>__SUBTITLE__</small></h1>

<fieldset>
  <legend>where to send</legend>
  <label>Proxy / server base <input type="text" id="base" value="http://localhost:__PORT__"/></label>
  <label><input type="checkbox" id="fresh" checked/> fresh identifiers per submit</label>
</fieldset>

<fieldset>
  <legend>payload</legend>
  <label>Choose:
    <select id="pick" onchange="pickPayload()"></select>
  </label>
  <textarea id="payload" spellcheck="false"></textarea>
</fieldset>

<div id="actions"></div>

<div id="verdict" class="info">no request sent yet</div>
<div id="report"></div>
<pre id="out"></pre>

<script>
// Everything actor-specific is data; the code below is identical across the
// generated simulator pages.
const CFG = __CONFIG__;
const PAYLOADS = __PAYLOADS__;

const sel = document.getElementById('pick');
CFG.payloads.forEach(p => sel.add(new Option(p.label, p.key)));
sel.add(new Option('Custom (paste your own)', 'custom'));

function pickPayload() {
  const k = sel.value;
  if (k !== 'custom') document.getElementById('payload').value = JSON.stringify(PAYLOADS[k], null, 2);
}
pickPayload();

const bar = document.getElementById('actions');
const submitBtn = document.createElement('button');
submitBtn.className = 'primary';
submitBtn.textContent = CFG.submit.label;
submitBtn.onclick = submitPayload;
bar.appendChild(submitBtn);
CFG.pulls.forEach(p => {
  const b = document.createElement('button');
  b.textContent = p.label;
  b.onclick = () => pull(p);
  bar.appendChild(b);
});

function base() { return document.getElementById('base').value.replace(/\\/+$/, ''); }

function freshen(text) {
  if (!document.getElementById('fresh').checked) return text;
  const ts = Date.now();
  CFG.freshen.forEach(([from, prefix]) => { text = text.replaceAll(from, prefix + ts); });
  return text;
}

function show(kind, headline, body) {
  const v = document.getElementById('verdict');
  v.className = kind; v.textContent = headline;
  document.getElementById('out').textContent = body;
  document.getElementById('report').innerHTML = '';
}

// human-readable error report: one block per validation issue, with the
// element path it points at and the validator's message
function renderReport(verdict, issues) {
  const el = document.getElementById('report');
  el.innerHTML = '';
  if (issues && issues.length) {
    issues.forEach(i => {
      const d = document.createElement('div'); d.className = 'issue';
      const sev = document.createElement('b'); sev.textContent = i.severity || 'error';
      const loc = document.createElement('code'); loc.textContent = i.location || '(bundle)';
      const msg = document.createElement('div'); msg.className = 'msg'; msg.textContent = i.message || '';
      d.append(sev, loc, msg);
      el.appendChild(d);
    });
    const total = parseInt(verdict, 10);
    if (total > issues.length) {
      const m = document.createElement('div'); m.className = 'more';
      m.textContent = 'showing the first ' + issues.length + ' of ' + total +
        ' findings — the full list is in the session’s validation-reports.json / dashboard';
      el.appendChild(m);
    }
  } else if (verdict && verdict.startsWith('0 ')) {
    el.innerHTML = '<div class="none">no conformance findings</div>';
  }
}

async function send(method, url, bodyText) {
  show('info', '… sending ' + method + ' ' + url, '');
  try {
    const res = await fetch(url, {
      method,
      headers: bodyText ? { 'Content-Type': 'application/fhir+json' } : { 'Accept': 'application/fhir+json' },
      body: bodyText || undefined
    });
    const verdict = res.headers.get('X-ZW-Validation');
    const text = await res.text();
    let pretty = text;
    let parsed = null;
    try { parsed = JSON.parse(text); pretty = JSON.stringify(parsed, null, 2); } catch (e) {}
    // issue details: from the proxy's report header, or — when talking to a
    // strict server directly — from an OperationOutcome response body
    let issues = null;
    const rep = res.headers.get('X-ZW-Validation-Report');
    if (rep) { try { issues = JSON.parse(decodeURIComponent(rep)); } catch (e) {} }
    if ((!issues || !issues.length) && parsed && parsed.resourceType === 'OperationOutcome' && parsed.issue) {
      issues = parsed.issue.filter(i => i.severity === 'error' || i.severity === 'fatal')
        .map(i => ({ severity: i.severity,
                     location: (i.expression || i.location || [])[0] || '',
                     message: i.diagnostics || (i.details && i.details.text) || '' }));
    }
    const ok = res.ok && (!verdict || verdict.startsWith('0 '));
    const head = 'HTTP ' + res.status + (verdict ? '   ·   conformance: ' + verdict : '');
    show(ok ? 'pass' : 'fail', (ok ? '✓ ' : '✗ ') + head, pretty);
    renderReport(verdict, issues);
  } catch (e) {
    show('fail', '✗ request failed — is the proxy running?', String(e));
  }
}

function submitPayload() {
  const text = freshen(document.getElementById('payload').value);
  send('POST', base() + CFG.submit.path, text);
}

function pull(p) {
  // URLSearchParams percent-encodes '|' etc. — raw pipes get dropped by the
  // proxy's HTTP parser before scenario matching
  const qs = new URLSearchParams(p.params || {}).toString();
  send('GET', base() + p.path + (qs ? '?' + qs : ''));
}
</script>
</body>
</html>
"""

for actor, cfg in ACTORS.items():
    config = {
        'actor': actor,
        'payloads': [{'key': p['key'], 'label': p['label']} for p in cfg['payloads']],
        'submit': cfg['submit'],
        'pulls': cfg['pulls'],
        'freshen': cfg['freshen'],
    }
    payloads = {p['key']: p['data'] for p in cfg['payloads']}
    html = (TEMPLATE
            .replace('__TITLE__', cfg['title'])
            .replace('__SUBTITLE__', cfg['subtitle'])
            .replace('__PORT__', str(cfg['port']))
            .replace('__CONFIG__', json.dumps(config, indent=2, ensure_ascii=False))
            .replace('__PAYLOADS__', json.dumps(payloads, indent=2, ensure_ascii=False)))
    with open(cfg['file'], 'w') as f:
        f.write(html)
    print(cfg['file'] + ' written')
PY
