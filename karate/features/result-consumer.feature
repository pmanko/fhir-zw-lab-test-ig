@lab-result-consumer
Feature: Lab Result Consumer — pulls results for its patients

  Transaction ④ (result pull). The Karate suite plays the Lab Result Consumer
  (Impilo EHR in the national architecture) against the Lab Result Repository.
  Covers result-pull-01..03.

  Background:
    * url shrUrl
    * def seeded = call read('common/submit-order.feature')
    * def created = call read('common/create-report.feature') seeded

  Scenario: Results for a patient are found via the patient's business identifier
    # the consumer only knows its own (EHR) patient identifier
    Given path 'DiagnosticReport'
    And params ({ 'patient.identifier': systems.ehrPatientId + '|' + seeded.patientIdentifierValue })
    When method get
    Then status 200
    And match response.type == 'searchset'
    And match response.entry == '#[1]'
    * def report = response.entry[0].resource

    # correlate the result back to the order this consumer placed (result-pull-03)
    And match report.basedOn[0].reference contains seeded.serviceRequestId
    And match report.status == 'final'

    # follow through to the result value
    * def obsRef = report.result[0].reference
    Given path 'Observation', obsRef.split('/')[1]
    When method get
    Then status 200
    And match response.resourceType == 'Observation'
    And match response.valueQuantity == '#notnull'

  Scenario: The signed-off report document can be fetched for display
    Given path 'Bundle'
    And param identifier = systems.reportDocument + '|' + created.documentIdentifierValue
    When method get
    Then status 200
    And match response.entry == '#[1]'
    * def doc = response.entry[0].resource
    And match doc.entry[0].resource.resourceType == 'Composition'
    And match doc.entry[0].resource.title == '#string'

  @workshop
  Scenario: TODO (workshop) — only results for the consumer's own patients are visible
    # Discussion point: patient-level scoping/authorization at the repository
    # (OpenHIM policy in the national architecture).

  @workshop
  Scenario: TODO (workshop) — poll for new results since the last check
    # Steps: search DiagnosticReport with _lastUpdated=ge<timestamp> and the
    # patient identifier; assert only newly issued reports are returned.
