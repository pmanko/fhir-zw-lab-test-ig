The kit lives in the [source repository](https://github.com/pmanko/fhir-zw-lab-test-ig) under `karate/`. It needs no Maven/Gradle project — the standalone `karate.jar` is downloaded automatically on first run.

### Prerequisites

- Java 17+ (`java -version`). With [SDKMAN](https://sdkman.io/) run `sdk env install` in the repo root (version pinned in `.sdkmanrc`); `run-tests.sh` also picks up the pinned JDK automatically if your default Java is older.
- Network access to the FHIR server under test.

### Running

```bash
cd karate
./run-tests.sh                          # default: happy path, all roles (ZW sandbox)
./run-tests.sh @lab-order-placer        # one actor's suite
./run-tests.sh @e2e                     # the full order-to-result loop
KARATE_ENV=local ./run-tests.sh         # local sandbox (URL in karate-config.js)
SHR_URL=https://my-shr/fhir ./run-tests.sh   # any FHIR base URL
```

The HTML report lands in `karate/target/karate-reports/karate-summary.html`.

### Local sandbox

```bash
git clone https://github.com/costateixeira/hapi-sandbox && cd hapi-sandbox
docker compose up -d        # serves http://localhost:8090/fhir
```

For the `@validation` scenarios the server needs the main IG's conformance resources (and the ZW Core dependency). Load them from the resolved packages with:

```bash
cd karate
scripts/load-ig.sh                          # default http://localhost:8090/fhir
scripts/load-ig.sh --local                  # use the local main-IG #dev build
scripts/load-ig.sh https://my-shr/fhir      # any server
```

Notes:

- HAPI caches terminology lookups for several minutes, so `@validation` scenarios may need a short wait right after the first load.
- The test payloads carry only the national codes. The IG examples also include LOINC translations, but an offline sandbox cannot validate LOINC (HAPI only accepts it via its terminology uploader); validating those is deferred to a terminology-capable validator.

### Tags

| Tag | Meaning |
|---|---|
| `@lab-*` | The actor role a feature certifies |
| `@validation` | Steps that call `$validate` — require the IG packages loaded on the server |
| `@pending-validation` | Negative tests that need validation-on-write enabled on the server |
| `@auditor` | The external-submission audit (needs `AUDIT_PATIENT_IDENTIFIER`) |
| `@workshop` | Intentionally unimplemented placeholder scenarios, authored in workshop sessions (excluded from every default run) |
| `@ignore` | Callable helpers in `features/common/`, never run directly |

### Testing your own system

**Your system plays a repository role** — run the repository suites against it:

```bash
SHR_URL=https://your-server/fhir ./run-tests.sh @lab-order-repository
SHR_URL=https://your-server/fhir ./run-tests.sh @lab-result-repository
```

**Your system plays a client role** (Order Placer, Fulfiller, Result Provider, Consumer) — use an [interceptor or the after-the-fact auditor](simulators.html).
