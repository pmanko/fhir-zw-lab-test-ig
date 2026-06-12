@ignore
Feature: Create result resources and the signed-off report document (callable helper)

  Plays the Lab Result Provider for setup purposes.
  Expects (from caller): runId, patientId, serviceRequestId, specimenId.
  Returns: observationId, diagnosticReportId, documentBundleId, documentIdentifierValue.

  Scenario:
    # ── Observation (the result value) ──
    * def obs = read('../../data/observation.json')
    * obs.subject = ({ reference: 'Patient/' + patientId })
    * obs.basedOn = ([{ reference: 'ServiceRequest/' + serviceRequestId }])
    * obs.specimen = ({ reference: 'Specimen/' + specimenId })
    Given url shrUrl
    And path 'Observation'
    And request obs
    When method post
    Then status 201
    * def observationId = response.id

    # ── DiagnosticReport (the report, linked back to the order) ──
    * def dr = read('../../data/diagnostic-report.json')
    * dr.subject = ({ reference: 'Patient/' + patientId })
    * dr.basedOn = ([{ reference: 'ServiceRequest/' + serviceRequestId }])
    * dr.specimen = ([{ reference: 'Specimen/' + specimenId }])
    * dr.result = ([{ reference: 'Observation/' + observationId }])
    Given url shrUrl
    And path 'DiagnosticReport'
    And request dr
    When method post
    Then status 201
    * def diagnosticReportId = response.id

    # ── Signed-off report document, stored whole on the repository ──
    * def doc = read('../../data/report-bundle.json')
    * def documentIdentifierValue = 'ZW-LABDOC-' + runId
    * doc.identifier.value = documentIdentifierValue
    Given url shrUrl
    And path 'Bundle'
    And request doc
    When method post
    Then status 201
    * def documentBundleId = response.id
