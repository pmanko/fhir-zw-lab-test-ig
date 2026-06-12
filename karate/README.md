# ZW Lab Actor Conformance Test Kit

Executable Gherkin/[Karate](https://karatelabs.io/) tests for the six actors of the
Zimbabwe laboratory ordering and results workflow defined by this IG:

| Role | Feature | Tag |
|---|---|---|
| Lab Order Placer | `features/order-placer.feature` | `@lab-order-placer` |
| Lab Order Repository | `features/order-repository.feature` | `@lab-order-repository` |
| Lab Order Fulfiller | `features/order-fulfiller.feature` | `@lab-order-fulfiller` |
| Lab Result Provider | `features/result-provider.feature` | `@lab-result-provider` |
| Lab Result Repository | `features/result-repository.feature` | `@lab-result-repository` |
| Lab Result Consumer | `features/result-consumer.feature` | `@lab-result-consumer` |
| Full loop ①→④ | `features/end-to-end.feature` | `@e2e` |
| External-submission audit | `features/auditor.feature` | `@auditor` |

Alongside the actor suites, `features/transactions/` holds **transaction-level
smoke tests** (one feature per transaction: `submit-orders`, `poll-orders`,
`submit-results`, `poll-results`). They POST/search single resources rather
than bundles, and all per-test data lives in external JSON files under
`features/transactions/data/` — drive each case by editing those files rather
than the `.feature` scripts.

The Karate suite plays the client roles itself; the FHIR server under test
plays the repository roles. By default that server is a
[hapi-sandbox](https://github.com/costateixeira/hapi-sandbox) with this IG and
the ZW Core IG loaded.

## Prerequisites

- Java 17+ (`java -version`). With [SDKMAN](https://sdkman.io/) just run
  `sdk env install` in the repo root (version pinned in `.sdkmanrc`);
  `run-tests.sh` also picks it up automatically if your default java is older.
- Network access to the FHIR server under test

The standalone `karate.jar` is downloaded automatically on first run — no
Maven/Gradle project needed.

## Running

```bash
./run-tests.sh                          # default: happy path, all roles
./run-tests.sh @lab-order-placer        # one actor's suite
./run-tests.sh @e2e                     # the full order-to-result loop
KARATE_ENV=hosted ./run-tests.sh        # hosted sandbox (URL in karate-config.js)
SHR_URL=https://my-shr/fhir ./run-tests.sh   # any FHIR base URL
```

The HTML report lands in `target/karate-reports/karate-summary.html`.

### Local sandbox

```bash
git clone https://github.com/costateixeira/hapi-sandbox && cd hapi-sandbox
docker compose up -d        # serves http://localhost:8090/fhir
```

For the `@validation` scenarios the server needs this IG's conformance
resources (and the ZW Core dependency). Load them with:

```bash
scripts/load-ig.sh                          # default http://localhost:8090/fhir
scripts/load-ig.sh https://my-shr/fhir      # any server
```

Notes:

- HAPI caches terminology lookups for several minutes, so `@validation`
  scenarios may need a short wait right after the first load.
- The test payloads carry only the national codes. The IG examples also
  include LOINC translations, but an offline sandbox cannot validate LOINC
  (HAPI only accepts it via its terminology uploader); validating those is
  deferred to a terminology-capable validator.

## Tags

| Tag | Meaning |
|---|---|
| `@lab-*` | The actor role a feature certifies |
| `@validation` | Steps that call `$validate` — require the IG packages loaded on the server |
| `@workshop` | Intentionally unimplemented placeholder scenarios, to be authored in workshop sessions (excluded from every default run) |
| `@pending-validation` | Negative tests that need validation-on-write enabled on the sandbox |
| `@auditor` | The external-submission audit (needs `AUDIT_PATIENT_IDENTIFIER`) |
| `@ignore` | Callable helpers in `features/common/`, never run directly |

## Testing your own system

**Your system plays a repository role**: run the repository suites against it:

```bash
SHR_URL=https://your-server/fhir ./run-tests.sh @lab-order-repository
SHR_URL=https://your-server/fhir ./run-tests.sh @lab-result-repository
```

**Your system plays a client role** (Order Placer, Fulfiller, Result Provider,
Consumer) — two complementary options:

*Live, per-request: the interceptor.* An actor interceptor **waits** for your
client. It doesn't reimplement a FHIR server — it sits in front of the real
one and, per request: a **push** (placing an order / submitting a report) is
forwarded to the real server's `$validate` against the matching ZW profile, so
the payload is validated, never stored, and your client gets the
`OperationOutcome` back; a **pull** (fetching orders / results) is **gated** —
it must be patient-scoped (`subject` or `patient` param) or it's rejected with
`400`, and a correct query is forwarded to the repository. Every request is
logged so you can watch exactly what the client did.

```bash
./run-interceptor.sh ehr 8080    # tests an EHR (order placer + result consumer)
./run-interceptor.sh lab 8081    # tests a lab system (order fulfiller + result provider)
# choose the real server behind the interceptor:
TARGET=https://my-shr/fhir ./run-interceptor.sh ehr 8080
```

Point the system under test at `http://localhost:<port>`, drive it through its
order/result flow, and stop with `Ctrl+C`.

*After the fact: the auditor.* Let your system submit to the real sandbox as
usual, then validate everything that arrived for the patient:

```bash
AUDIT_PATIENT_IDENTIFIER='http://mohcc.gov.zw/fhir/lab/identifier/ehr-patient-id|EHR-ZW-00123' \
  ./run-tests.sh @auditor
```

## Test data

Payloads in `data/` are **derived from the main Lab IG's published examples**
so tests and spec cannot drift. The source is the `zw.fhir.ig.lab` *package*
(this repo no longer lives next to the IG source), resolved by
`scripts/resolve-lab-package.sh`:

```bash
scripts/sync-test-data.sh             # default: the fork's branch build on build.fhir.org
scripts/sync-test-data.sh --local     # the local ~/.fhir #dev build (after building the IG)
```

The sync writes two things: the wire payloads here in `data/` (valid **and**
intentionally-invalid variants, which the Karate suite and simulators submit),
and the two valid wire bundles into `../input/resources/`, where the IG
publisher renders and profile-validates them. Re-run
`scripts/build-simulator.sh` afterwards — the simulator HTML embeds the data.

Helpers in `features/common/` uniquify patient/sample identifiers per run, so
the suite can run repeatedly against a shared server without collisions.

## Filling in a workshop placeholder

1. Pick a `@workshop` scenario — the TODO comment describes the steps.
2. Write the steps (copy patterns from the implemented scenarios above it).
3. Remove the `@workshop` tag and run the feature:
   `./run-tests.sh @lab-order-fulfiller`

## Simulators (no system? no problem)

`simulator/` holds one zero-dependency page per actor — open them straight
from disk in Chrome. Pick a payload, click **Submit**, and the page POSTs to
the proxy with fresh identifiers per submit; the conformance verdict and full
response are shown inline. The pull buttons demo patient-scoped vs refused
queries.

- `ehr-simulator.html` plays the Lab Order Placer / Result Consumer:
  submits order bundles (valid / invalid / the real Impilo sample / your
  own) and pulls DiagnosticReports.
- `lab-simulator.html` plays the Order Fulfiller / Result Provider:
  submits report documents (valid / invalid / your own) and pulls
  ServiceRequest orders.

Typical demo: `./test-session.sh ehr` (or `./test-session.sh lab 8081`) in
one terminal, the matching simulator in the browser — every click appears in
the session's live feed and counts toward the end-of-session audit. Both
pages are generated from the same template; regenerate after changing
payload data: `scripts/build-simulator.sh`.
