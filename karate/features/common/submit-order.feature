@ignore
Feature: Submit a new order to the Lab Order Repository (callable helper)

  Plays the Lab Order Placer for setup purposes: builds a uniquified order
  bundle, POSTs it as a FHIR transaction, and returns the created ids.
  Returns: runId, patientIdentifierValue, sampleIdentifierValue,
           taskId, serviceRequestId, patientId, specimenId.

  Scenario:
    * def built = call read('build-order.feature')
    * def runId = built.runId
    * def patientIdentifierValue = built.patientIdentifierValue
    * def sampleIdentifierValue = built.sampleIdentifierValue

    Given url shrUrl
    And request built.orderBundle
    When method post
    Then status 200
    And match response.type == 'transaction-response'
    And match each response.entry[*].response.status == '#regex 2\\d\\d.*'

    # transaction-response entries come back in request order:
    # Task, ServiceRequest, Patient, Specimen, Location, Organization
    * def idOf = function(loc){ var p = loc.split('/'); var i = p.indexOf('_history'); return i > 1 ? p[i - 1] : p[p.length - 1] }
    * def locations = $response.entry[*].response.location
    * def taskId = idOf(locations[0])
    * def serviceRequestId = idOf(locations[1])
    * def patientId = idOf(locations[2])
    * def specimenId = idOf(locations[3])
