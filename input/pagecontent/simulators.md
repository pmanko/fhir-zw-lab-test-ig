When the system you want to test is a **client** — it places orders, fulfils them, or provides results — you don't run a Karate suite against it. Instead you put something in front of the real server and drive your client through its normal flow. Two complementary options.

### Live, per request: the interceptor

An actor interceptor **waits** for your client. It doesn't reimplement a FHIR server — it sits in front of the real one and, per request:

- a **push** (placing an order / submitting a report) is forwarded to the real server's `$validate` against the matching ZW profile, so the payload is validated, never stored, and your client gets the `OperationOutcome` back;
- a **pull** (fetching orders / results) is **gated** — it must be patient-scoped (`subject` or `patient` parameter) or it's rejected with `400`, and a correct query is forwarded to the repository.

Every request is logged so you can watch exactly what the client did.

```bash
cd karate
./run-interceptor.sh ehr 8080    # tests an EHR (order placer + result consumer)
./run-interceptor.sh lab 8081    # tests a lab system (order fulfiller + result provider)
TARGET=https://my-shr/fhir ./run-interceptor.sh ehr 8080   # choose the real server behind it
```

Point the system under test at `http://localhost:<port>`, drive it through its order/result flow, and stop with `Ctrl+C`.

#### One-command sessions

`test-session.sh` wraps the interceptor with a live feed and an end-of-session audit:

```bash
cd karate
./test-session.sh ehr            # proxy on :8080 (auto-picks the next free port)
./test-session.sh lab 8081
```

Every push is scored against the ZW profiles on the way through (verdict shown live and in an `X-ZW-Validation` response header); on `Ctrl+C` the session audits everything the system stored, prints a per-request verdict table, and opens a browser dashboard with the verdicts beside the Karate audit report.

### After the fact: the auditor

Let your system submit to the real sandbox as usual, then validate everything that arrived for the patient:

```bash
AUDIT_PATIENT_IDENTIFIER='http://mohcc.gov.zw/fhir/lab/identifier/ehr-patient-id|EHR-ZW-00123' \
  ./run-tests.sh @auditor
```

### No system yet? Browser simulators

`karate/simulator/` holds one zero-dependency page per actor — open them straight from disk, or point them at a running session proxy. Pick a payload, click **Submit**, and the page POSTs with fresh identifiers per submit; the conformance verdict and full response (including per-issue error detail) are shown inline. The pull buttons demo patient-scoped vs refused queries.

- `ehr-simulator.html` plays the Lab Order Placer / Result Consumer: submits order bundles (valid / invalid / the real Impilo sample / your own) and pulls DiagnosticReports.
- `lab-simulator.html` plays the Order Fulfiller / Result Provider: submits report documents (valid / invalid / your own) and pulls ServiceRequest orders.

Typical demo: `./test-session.sh ehr` in one terminal, the matching simulator in the browser — every click appears in the session's live feed and counts toward the end-of-session audit. Both pages are generated from one template; regenerate after changing payload data with `scripts/build-simulator.sh`.
