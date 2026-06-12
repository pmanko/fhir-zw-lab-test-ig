#!/usr/bin/env bash
# One-command conformance session for a real system. Starts the pass-through
# proxy, shows a friendly live feed of every request's verdict, and on Ctrl+C
# automatically audits everything the system stored and prints a summary.
#
#   ./test-session.sh ehr          # test a real EHR   (proxy on :8080)
#   ./test-session.sh lab 8081     # test a lab system (proxy on :8081)
#   TARGET=https://my-shr/fhir ./test-session.sh ehr   # different real server
#
# Point the system under test at http://<this-machine>:<port> and use it
# normally. Nothing else to configure, nothing to repoint.
set -uo pipefail
cd "$(dirname "$0")"

ACTOR="${1:?usage: test-session.sh <ehr|lab> [port]}"
PORT="${2:-8080}"
# if the requested port is taken (e.g. Docker/OrbStack forwards on 8080/8081),
# walk up to the next free one
while lsof -ti tcp:"$PORT" >/dev/null 2>&1; do
  HOLDER="$(lsof -ti tcp:"$PORT" 2>/dev/null | head -1)"
  if ps -p "${HOLDER:-0}" -o command= 2>/dev/null | grep -q 'karate.*mock'; then
    echo "⚠ port $PORT is held by a LEFTOVER conformance proxy (pid $HOLDER) from an earlier session."
    echo "  Anything still pointed at :$PORT will talk to that zombie, not to this session."
    echo "  Free it with:  kill $HOLDER"
  fi
  echo "(port $PORT is in use — trying $((PORT + 1)))"
  PORT=$((PORT + 1))
done
TARGET="${TARGET:-http://173.212.195.88/fhir}"
SESSION="target/sessions/$(date +%Y%m%d-%H%M%S)-${ACTOR}"
mkdir -p "$SESSION"
# state files are scoped to this proxy's port (see run-interceptor.sh), so a
# leftover proxy from an earlier session can never feed this session's audit
rm -f "target/session-${PORT}-patients.txt" "session-${PORT}-patients.txt"
rm -f "target/session-${PORT}-validation-reports.json" "session-${PORT}-validation-reports.json"

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | cut -d' ' -f1 || echo localhost)"

echo "──────────────────────────────────────────────────────────────"
echo " ZW Lab conformance session — actor: ${ACTOR}"
echo " Point your system's FHIR base URL at:  http://${LAN_IP}:${PORT}"
echo " Requests flow through to:              ${TARGET}"
echo " Every push is scored against the ZW profiles on the way."
echo " No real system handy? Open simulator/${ACTOR}-simulator.html"
echo " and set its base to:                   http://localhost:${PORT}"
echo " Stop with Ctrl+C to get your audit and summary."
echo "──────────────────────────────────────────────────────────────"

MODE=proxy TARGET="$TARGET" ./run-interceptor.sh "$ACTOR" "$PORT" > "$SESSION/proxy.log" 2>&1 &
PROXY_PID=$!

cleanup() {
  trap - INT TERM
  echo
  echo "── ending session ──"
  kill "${FEED_PID:-}" 2>/dev/null
  kill "$PROXY_PID" 2>/dev/null
  pkill -P "$PROXY_PID" 2>/dev/null
  sleep 1

  PASS=$(rg -c 'ZWPROXY\|push\|[^|]*\|0 errors|ZWPROXY\|pull\|[^|]*\|ok' "$SESSION/proxy.log" 2>/dev/null || echo 0)
  FAIL=$(rg -c 'ZWPROXY\|push\|[^|]*\|[1-9][0-9]* errors|REJECTED' "$SESSION/proxy.log" 2>/dev/null || echo 0)
  FWD=$(rg -c 'ZWPROXY\|[^|]*\|.*\|forwarded' "$SESSION/proxy.log" 2>/dev/null || echo 0)
  echo "session summary:  ✓ ${PASS} conformant   ✗ ${FAIL} with findings   → ${FWD} passed through"

  # per-request verdicts: table for the terminal, JSON artifact for the session folder
  VERDICTS=$(rg 'ZWPROXY\|' "$SESSION/proxy.log" 2>/dev/null | sed -E 's/^([0-9:.]+) .*ZWPROXY\|/\1|/')
  if [ -n "$VERDICTS" ]; then
    echo
    echo "── per-request verdicts ──"
    printf '%s\n' "$VERDICTS" | awk -F'|' '
      BEGIN { printf "  %-13s %-5s %-30s %s\n", "time", "actn", "subject", "result" }
      { printf "  %-13s %-5s %-30s %s\n", $1, $2, $3, $4 }'
    printf '%s\n' "$VERDICTS" | awk -F'|' '
      BEGIN { print "["; sep="" }
      { gsub(/"/, "\\\"")
        printf "%s  {\"time\":\"%s\",\"action\":\"%s\",\"subject\":\"%s\",\"result\":\"%s\",\"report\":\"%s\"}", sep, $1, $2, $3, $4, $5
        sep=",\n" }
      END { print "\n]" }' > "$SESSION/verdicts.json"
    echo "  (saved as JSON: $SESSION/verdicts.json)"
  else
    echo "⚠ no requests reached this session's proxy — nothing to report or audit."
    echo "  Your system / simulator must point at:  http://${LAN_IP}:${PORT}  (or http://localhost:${PORT})"
    echo "  If it was configured before this session started, it may still be talking"
    echo "  to an older proxy — check with:  pkill -f 'karate.*mock'  and start over."
  fi

  # full per-request validation error reports written by the proxy; the ids
  # in here match the trailing field of the ZWPROXY log lines
  for f in "target/session-${PORT}-validation-reports.json" "session-${PORT}-validation-reports.json"; do
    [ -s "$f" ] && cp "$f" "$SESSION/validation-reports.json" && break
  done

  PATIENTS_FILE=""
  for f in "target/session-${PORT}-patients.txt" "session-${PORT}-patients.txt"; do
    [ -s "$f" ] && PATIENTS_FILE="$f" && break
  done
  if [ -n "$PATIENTS_FILE" ]; then
    cp "$PATIENTS_FILE" "$SESSION/patients.txt"
    echo
    echo "── auditing what your system stored on ${TARGET} ──"
    while IFS= read -r ident; do
      [ -z "$ident" ] && continue
      echo "· auditing patient ${ident}"
      AUDIT_PATIENT_IDENTIFIER="$ident" SHR_URL="$TARGET" FEATURES=features/auditor.feature ./run-tests.sh @auditor || true
    done < "$SESSION/patients.txt"
  else
    echo "(no patient identifiers seen in pushes — skipping the audit)"
  fi

  # keep this session's audit report with the session — target/karate-reports
  # is "latest run" and gets overwritten by any later test run
  if [ -n "$PATIENTS_FILE" ] && [ -d target/karate-reports ]; then
    cp -R target/karate-reports "$SESSION/audit-report"
  fi

  # browser dashboard: verdicts table side by side with the audit's Karate
  # report (generated after the audit so the iframe has something to show)
  if [ -n "$VERDICTS" ]; then
    {
      cat <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>ZW Lab session verdicts</title>
<style>
 body{font-family:-apple-system,'Segoe UI',sans-serif;margin:1.5rem;background:#fafafa;color:#222}
 h1{font-size:1.2rem;margin-bottom:.2rem} h2{font-size:.95rem;color:#444;margin:.2rem 0 .6rem}
 .meta{color:#666;margin-bottom:1rem;font-size:.9rem}
 .sum{margin:0 0 1.2rem;font-size:1rem}
 .panes{display:flex;gap:1.5rem;align-items:flex-start;flex-wrap:wrap}
 .pane-right{flex:1;min-width:460px}
 table{border-collapse:collapse;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.12)}
 th,td{padding:.55rem 1rem;border-bottom:1px solid #eee;text-align:left;font-size:.9rem}
 th{background:#f3f4f6;font-size:.8rem;text-transform:uppercase;letter-spacing:.04em;color:#555}
 tr.ok td.result{color:#15803d;font-weight:600}
 tr.bad td.result{color:#b91c1c;font-weight:600}
 tr.fwd td.result{color:#777}
 tr.click{cursor:pointer} tr.click:hover td{background:#f1f5f9}
 tr.detail td{background:#fbfbfd;font-size:.85rem;color:#333}
 .issue{border-left:3px solid #b91c1c;padding:.15rem .6rem;margin:.3rem 0}
 .issue b{text-transform:uppercase;font-size:.7rem;color:#b91c1c;margin-right:.4rem}
 .issue code{background:#f3f4f6;padding:0 .35rem;border-radius:4px;font-size:.78rem}
 .issue .msg{margin-top:.1rem}
 .prof{color:#888;font-size:.75rem;margin-top:.4rem}
 iframe{width:100%;height:78vh;border:1px solid #ddd;background:#fff}
 a{color:#2563eb} .note{font-size:.85rem;color:#666}
</style></head><body>
HTML
      echo "<h1>ZW Lab conformance session — ${ACTOR}</h1>"
      echo "<div class=meta>$(basename "$SESSION") &middot; target: ${TARGET}</div>"
      echo "<div class=sum>&#10003; ${PASS} conformant &nbsp;&nbsp; &#10007; ${FAIL} with findings &nbsp;&nbsp; &rarr; ${FWD} passed through</div>"
      echo "<div class=panes><div>"
      echo "<h2>Live traffic — what your system sent</h2>"
      echo "<table><tr><th>time</th><th>action</th><th>subject</th><th>result</th></tr>"
      printf '%s\n' "$VERDICTS" | awk -F'|' '{
        gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;")
        cls = ($4 ~ /^0 errors/ || $4 ~ /^ok/) ? "ok" : ($4 ~ /forwarded/) ? "fwd" : "bad"
        printf "<tr class=%s data-report=\"%s\"><td>%s</td><td>%s</td><td>%s</td><td class=result>%s</td></tr>\n", cls, $5, $1, $2, $3, $4 }'
      echo "</table>"
      echo "<p class=note>click a validated request for its full error report &middot; also saved as verdicts.json + validation-reports.json in this folder</p>"
      echo "</div><div class=pane-right>"
      echo "<h2>Stored-data audit — what ended up on the server</h2>"
      if [ -f "$SESSION/audit-report/karate-summary.html" ]; then
        echo '<iframe src="audit-report/karate-summary.html"></iframe>'
      else
        echo '<p class=note>no audit ran (no patient identifiers seen in pushes)</p>'
      fi
      echo "</div></div>"
      # per-request error reports: clicking a verdict row expands the issues
      # the proxy's \$validate hop found for that exact request
      echo "<script>const REPORTS = $(cat "$SESSION/validation-reports.json" 2>/dev/null || echo '[]');</script>"
      cat <<'HTML'
<script>
const byId = {};
(Array.isArray(REPORTS) ? REPORTS : []).forEach(r => { byId[r.id] = r; });
document.querySelectorAll('tr[data-report]').forEach(tr => {
  const r = byId[tr.dataset.report];
  if (!r) return;
  tr.classList.add('click');
  tr.title = 'click for the full error report';
  tr.addEventListener('click', () => {
    const next = tr.nextElementSibling;
    if (next && next.classList.contains('detail')) { next.remove(); return; }
    const d = document.createElement('tr'); d.className = 'detail';
    const td = document.createElement('td'); td.colSpan = 4;
    if (!r.issues || !r.issues.length) {
      td.textContent = 'no conformance findings';
    } else {
      r.issues.forEach(i => {
        const div = document.createElement('div'); div.className = 'issue';
        const sev = document.createElement('b'); sev.textContent = i.severity || 'error';
        const loc = document.createElement('code'); loc.textContent = i.location || '(bundle)';
        const msg = document.createElement('div'); msg.className = 'msg'; msg.textContent = i.message || '';
        div.append(sev, loc, msg);
        td.appendChild(div);
      });
    }
    if (r.profile) {
      const p = document.createElement('div'); p.className = 'prof';
      p.textContent = 'validated against ' + r.profile;
      td.appendChild(p);
    }
    d.appendChild(td); tr.after(d);
  });
});
</script>
HTML
      echo "</body></html>"
    } > "$SESSION/verdicts.html"
    echo "browser dashboard: $(pwd)/$SESSION/verdicts.html"
    command -v open >/dev/null 2>&1 && open "$SESSION/verdicts.html"
  fi

  echo
  echo "session folder:   $(pwd)/$SESSION/"
  echo "latest report:    $(pwd)/target/karate-reports/karate-summary.html"
  exit 0
}
trap cleanup INT TERM

sleep 4
if ! kill -0 "$PROXY_PID" 2>/dev/null; then
  echo "ERROR: proxy failed to start — see $SESSION/proxy.log" >&2
  exit 1
fi
echo "live feed (one line per request):"

feed() {
  tail -n +1 -F "$SESSION/proxy.log" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      *ZWPROXY\|push\|*\|0\ errors*)  echo "  ✓ $(echo "$line" | sed -E 's/.*ZWPROXY\|push\|([^|]*)\|.*/push \1 — conformant/')" ;;
      *ZWPROXY\|push\|*errors*)       echo "  ✗ $(echo "$line" | sed -E 's/.*ZWPROXY\|push\|([^|]*)\|([0-9]+) errors.*/push \1 — \2 errors (details in X-ZW-Validation \/ proxy.log)/')" ;;
      *ZWPROXY\|pull\|*REJECTED*)     echo "  ✗ $(echo "$line" | sed -E 's/.*ZWPROXY\|pull\|([^|]*)\|.*/pull \1 — rejected: missing patient scope/')" ;;
      *ZWPROXY\|pull\|*\|ok*)         echo "  ✓ $(echo "$line" | sed -E 's/.*ZWPROXY\|pull\|([^|]*)\|.*/pull \1 — patient-scoped, forwarded/')" ;;
      *ZWPROXY\|*forwarded*)          echo "  → $(echo "$line" | sed -E 's/.*ZWPROXY\|[^|]*\|([^|]*)\|.*/\1 passed through/')" ;;
    esac
  done
}
feed &
FEED_PID=$!

# `wait` (unlike a foreground pipeline) is interruptible, so Ctrl+C reaches
# the trap immediately.
wait "$FEED_PID"
