@ignore
Feature: Build a uniquified order bundle (callable helper)

  Returns: orderBundle, runId, patientIdentifierValue, sampleIdentifierValue.
  Each call gets fresh patient/sample identifiers so search assertions in the
  calling scenario are deterministic on a shared server.

  Scenario:
    * def runId = 'KT' + java.lang.System.currentTimeMillis()
    * def patientIdentifierValue = 'EHR-' + runId
    * def sampleIdentifierValue = 'SPEC-' + runId
    * def orderBundle = read('../../data/order-bundle.json')
    * def uniquify =
      """
      function(b) {
        for (var i = 0; i < b.entry.length; i++) {
          var e = b.entry[i];
          var r = e.resource;
          if (r.resourceType == 'Patient') {
            for (var j = 0; j < r.identifier.length; j++) {
              if (r.identifier[j].system == systems.ehrPatientId) {
                r.identifier[j].value = patientIdentifierValue;
              }
            }
            e.request.ifNoneExist = 'identifier=' + systems.ehrPatientId + '|' + patientIdentifierValue;
          }
          if (r.resourceType == 'Specimen') {
            for (var j = 0; j < r.identifier.length; j++) {
              if (r.identifier[j].system == systems.clientSampleId) {
                r.identifier[j].value = sampleIdentifierValue;
              }
            }
          }
        }
        return b;
      }
      """
    * def orderBundle = uniquify(orderBundle)
