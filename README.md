# Zimbabwe Lab IG — Conformance Test Kit (`zw.fhir.ig.lab.test`)

The test kit for the [Zimbabwe Laboratory Ordering and Results IG](http://mohcc.gov.zw/fhir/lab) (`zw.fhir.ig.lab`), published as its own IG so test data and the executable suite can iterate quickly without destabilising the spec.

Two things live here:

- **`input/` + `sushi-config.yaml`** — a small FHIR IG that publishes the validated test payloads and the kit's documentation. Built by SUSHI + the IG publisher; the [ci-build site](https://build.fhir.org/ig/pmanko/fhir-zw-lab-test-ig) is its only release channel.
- **`karate/`** — the executable [Karate](https://karatelabs.io/) actor-conformance suite, actor interceptors, browser simulators, and the live-session runner. See [`karate/README.md`](karate/README.md).

## Quick start

```bash
# regenerate the wire payloads from the main IG package, then build the IG
karate/scripts/sync-test-data.sh            # or --local against a local main-IG build
sushi .                                      # fast: compiles + validates dependency resolution
./_genonce.sh                                # full publisher build (or use the auto-builder)

# run the conformance suite
cd karate && ./run-tests.sh                  # against the ZW sandbox by default
```

## How it depends on the main IG

`sushi-config.yaml` declares a dependency on `zw.fhir.ig.lab`. Until the order/report bundle profiles, actors, and requirements reach mohcc's default-branch auto-build, this is pinned to the fork's branch build:

```yaml
dependencies:
  zw.fhir.ig.lab:
    id: lab
    version: current$lab-dep-snapshot   # → switch to `current` once on mohcc main
```

The test payloads are **derived** from that package's published examples by `karate/scripts/sync-test-data.sh` (resolved via `resolve-lab-package.sh`), so the data cannot drift from the spec. The valid wire bundles are written to `input/resources/` and profile-validated on every build; the intentionally-invalid variants stay in `karate/data/` (outside `input/`, so the publisher never rejects the build) and are asserted to *fail* validation in CI.

## CI

- **`payload-validation`** (every push/PR): validates the wire payloads against the main IG package — valid ones must pass, invalid ones must fail. No FHIR server needed.
- **`karate-live`** (manual / scheduled): runs the full Karate suite against the live ZW sandbox.

The ci-build website (full publisher QA, example validation, the `package.tgz`) is produced by the FHIR auto-builder on every push — there is no separate publish workflow.
