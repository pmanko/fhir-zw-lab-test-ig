### Test data package

The validated test payloads are published as a FHIR package, `zw.fhir.ig.lab.test`, so they can be loaded directly into a validator, a test server, or your own tooling:

- [Package (NPM tgz)](package.tgz)
- The valid wire bundles are also browsable under [Artifacts](artifacts.html).

This package depends on the main [Zimbabwe Laboratory Ordering and Results IG](http://mohcc.gov.zw/fhir/lab) (`zw.fhir.ig.lab`); install both to validate the payloads against the profiles.

### Executable kit

The Karate suite, interceptors, and simulators are not packaged — they live in the [source repository](https://github.com/pmanko/fhir-zw-lab-test-ig) under `karate/`. Clone it and follow [Running the Kit](running.html).

### IG assets

- [This IG (definitions, JSON)](full-ig.zip)
