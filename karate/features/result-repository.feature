@lab-result-repository
Feature: Lab Result Repository — stores and serves result reports

  The server under test (SHR in the national architecture) plays the Lab
  Result Repository. Each scenario seeds an order and a result, then asserts
  the repository's storage and retrieval behaviour (result-push-02,
  result-pull-01, result-pull-02).

  Background:
    * url shrUrl
    * def seeded = call read('common/submit-order.feature')
    * def created = call read('common/create-report.feature') seeded

  Scenario: A submitted DiagnosticReport is retrievable by patient
    Given path 'DiagnosticReport'
    And param patient = 'Patient/' + seeded.patientId
    When method get
    Then status 200
    And match response.type == 'searchset'
    And match response.entry == '#[1]'
    And match response.entry[0].resource.id == created.diagnosticReportId

  Scenario: A submitted DiagnosticReport is retrievable by the order it fulfils
    Given path 'DiagnosticReport'
    And params ({ 'based-on': 'ServiceRequest/' + seeded.serviceRequestId })
    When method get
    Then status 200
    And match response.type == 'searchset'
    And match response.entry == '#[1]'

  Scenario: The signed-off report document is stored whole and retrievable by identifier
    Given path 'Bundle'
    And param identifier = systems.reportDocument + '|' + created.documentIdentifierValue
    When method get
    Then status 200
    And match response.type == 'searchset'
    And match response.entry == '#[1]'
    * def doc = response.entry[0].resource
    And match doc.type == 'document'
    # document rule: the Composition comes first, with the legal sign-off intact
    And match doc.entry[0].resource.resourceType == 'Composition'
    And match doc.entry[0].resource.attester[0].mode == 'legal'

  @pending-validation
  Scenario: The repository rejects a non-conformant report document (write validation)
    # result-push-02 — needs validation-on-write on the server (live on the ZW
    # sandbox). Stripping the Composition violates both the document rules
    # (first entry must be a Composition) and the ZWLabReportBundle profile.
    * def doc = read('../data/report-bundle.json')
    * doc.entry = doc.entry.slice(1)
    Given path 'Bundle'
    And request doc
    When method post
    Then assert responseStatus >= 400 && responseStatus < 500
    And match response.resourceType == 'OperationOutcome'
    And match response.issue[*].severity contains 'error'
