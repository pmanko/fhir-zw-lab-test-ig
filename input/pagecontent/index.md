This IG is the **conformance test kit** for the [Zimbabwe Laboratory Ordering and Results IG](http://mohcc.gov.zw/fhir/lab) (`zw.fhir.ig.lab`). It is published separately so the test data and the executable suite can iterate quickly without destabilising the specification: the main IG holds the profiles, actors and requirements; this IG holds everything you need to *exercise a real system against them*.

It contains two kinds of artifact:

1. **Validated test payloads** — the exact on-the-wire bundles the test suite submits, published here as [examples](artifacts.html) and validated against the main IG's bundle profiles on every build.
2. **An executable actor conformance kit** — Gherkin/[Karate](https://karatelabs.io/) feature files, actor interceptors, and browser simulators that live in the [source repository](https://github.com/pmanko/fhir-zw-lab-test-ig) under `karate/`. See [Running the Kit](running.html) and [Interceptors & Simulators](simulators.html).

### What is tested

Each actor in the [workflow](http://mohcc.gov.zw/fhir/lab/actors.html) has a feature file tagged with its role. The Karate suite plays the client roles itself; the server under test plays the repository roles.

| Feature | Tag | What it asserts |
|---|---|---|
| `order-placer.feature` | `@lab-order-placer` | A conformant ZWLabOrderBundle validates and is accepted as a FHIR transaction |
| `order-repository.feature` | `@lab-order-repository` | Search semantics for stored orders (Task by status, ServiceRequest by patient); rejection of invalid submissions |
| `order-fulfiller.feature` | `@lab-order-fulfiller` | Orders directed to a laboratory can be found and claimed (Task status workflow) |
| `result-provider.feature` | `@lab-result-provider` | A conformant ZWLabReportBundle validates and is stored whole |
| `result-repository.feature` | `@lab-result-repository` | Search and retrieval semantics for stored results and report documents |
| `result-consumer.feature` | `@lab-result-consumer` | Results for a patient can be retrieved and correlated to the originating order |
| `end-to-end.feature` | `@e2e` | The full ①→④ loop, chaining the role features with shared identifiers |
| `auditor.feature` | `@auditor` | Payloads submitted by *external* systems (a real EHR/LIMS, or manual POST) are found on the server and validated against the IG profiles |
| `transactions/*.feature` | — | Transaction-level smoke tests (submit/poll orders and results as single resources), driven entirely by external JSON data files |

### Layered validation

1. **Workflow assertions** in every scenario: status codes, Bundle shapes, search semantics, Task state transitions, referential linkage between results and orders.
2. **Profile validation** (`@validation`-tagged steps): payloads and responses are checked with `$validate?profile=...` against the main IG's profiles — requires the server to have the IG packages loaded.
3. **Validation-on-write**: a strict server rejects non-conformant writes, making the negative scenarios (`@pending-validation`) executable. This is enabled on the ZW sandbox.

### How the test data stays honest

The wire payloads are **derived** from the main IG's own published examples (its package), not hand-maintained, so the spec and the tests cannot drift. The valid bundles are published here and re-validated against the main IG profiles on every build; the intentionally-invalid variants are kept out of the published artifacts but asserted to *fail* validation in CI. See the [source README](https://github.com/pmanko/fhir-zw-lab-test-ig/blob/main/karate/README.md#test-data) for the regeneration command.
