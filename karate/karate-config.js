function fn() {
  var env = karate.env || 'local';

  var config = {
    // canonical of the IG UNDER TEST (zw.fhir.ig.lab) — its profiles are what
    // payloads are validated against. NOT this test IG's own canonical
    // (http://mohcc.gov.zw/fhir/lab/test); do not "fix" this to match.
    igCanonical: 'http://mohcc.gov.zw/fhir/lab',
    // local hapi-sandbox (https://github.com/costateixeira/hapi-sandbox)
    shrUrl: 'http://localhost:8090/fhir'
  };

  if (env === 'hosted' || env === 'zw') {
    // Hosted hapi-sandbox (ZW server): IGs installed, validation-on-write enabled
    config.shrUrl = 'http://173.212.195.88/fhir';
  }

  // SHR_URL always wins, regardless of env (e.g. to test your own repository)
  var override = java.lang.System.getenv('SHR_URL');
  if (override) {
    config.shrUrl = override;
  }

  config.profiles = {
    orderBundle: config.igCanonical + '/StructureDefinition/zw-lab-order-bundle',
    reportBundle: config.igCanonical + '/StructureDefinition/zw-lab-report-bundle',
    task: config.igCanonical + '/StructureDefinition/zw-lab-task',
    serviceRequest: config.igCanonical + '/StructureDefinition/zw-lab-service-request',
    patient: config.igCanonical + '/StructureDefinition/zw-lab-patient',
    specimen: config.igCanonical + '/StructureDefinition/zw-specimen',
    diagnosticReport: config.igCanonical + '/StructureDefinition/zw-lab-diagnostic-report',
    observation: config.igCanonical + '/StructureDefinition/zw-lab-result-observation'
  };

  // aliases used by the transaction-level features (features/transactions/)
  config.baseUrl = config.shrUrl;
  config.profiles.order = config.profiles.serviceRequest;
  config.profiles.result = config.profiles.diagnosticReport;

  // error/fatal issues from a $validate OperationOutcome (empty == conformant)
  config.errorIssues = function (oo) {
    return karate.jsonPath(oo, "$.issue[?(@.severity=='error' || @.severity=='fatal')]");
  };

  config.systems = {
    ehrPatientId: config.igCanonical + '/identifier/ehr-patient-id',
    clientSampleId: config.igCanonical + '/identifier/client-sample-id',
    reportDocument: config.igCanonical + '/identifier/report-document',
    laboratories: config.igCanonical + '/CodeSystem/zw-laboratories'
  };

  karate.configure('headers', { 'Content-Type': 'application/fhir+json', 'Accept': 'application/fhir+json' });
  karate.configure('ssl', true);
  karate.configure('connectTimeout', 10000);
  // generous: validation-on-write on a cold server can take 30s+ per request
  karate.configure('readTimeout', 120000);

  karate.log('ZW Lab test kit — env:', env, '— SHR:', config.shrUrl);

  // One throwaway $validate per JVM so the suite never hits a cold validator:
  // the first validation after the server has been idle loads the IG packages
  // (30s+), which otherwise surfaces mid-suite as body-read timeouts and null
  // responses. Done with a plain Java HTTP client so a warmup failure can
  // never fail the run.
  var System = Java.type('java.lang.System');
  if (!System.getProperty('zw.warmup.done')) {
    System.setProperty('zw.warmup.done', 'true');
    try {
      var HttpClient = Java.type('java.net.http.HttpClient');
      var HttpRequest = Java.type('java.net.http.HttpRequest');
      var BodyPublishers = Java.type('java.net.http.HttpRequest$BodyPublishers');
      var BodyHandlers = Java.type('java.net.http.HttpResponse$BodyHandlers');
      var URI = Java.type('java.net.URI');
      var Duration = Java.type('java.time.Duration');
      var URLEncoder = Java.type('java.net.URLEncoder');
      var Files = Java.type('java.nio.file.Files');
      var Paths = Java.type('java.nio.file.Paths');
      // user.dir == tests/karate (run-tests.sh cds there)
      var order = new java.lang.String(
        Files.readAllBytes(Paths.get(System.getProperty('user.dir'), 'data', 'order-bundle.json')), 'UTF-8');
      var uri = config.shrUrl + '/Bundle/$validate?profile='
        + URLEncoder.encode(config.profiles.orderBundle, 'UTF-8');
      var req = HttpRequest.newBuilder(URI.create(uri))
        .timeout(Duration.ofSeconds(180))
        .header('Content-Type', 'application/fhir+json')
        .POST(BodyPublishers.ofString(order))
        .build();
      var started = System.currentTimeMillis();
      var res = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build()
        .send(req, BodyHandlers.discarding());
      karate.log('warmup: validator answered HTTP', res.statusCode(),
        'in', (System.currentTimeMillis() - started) + 'ms');
    } catch (e) {
      karate.log('warmup failed (continuing anyway):', e.message ? e.message : e);
    }
  }

  return config;
}
