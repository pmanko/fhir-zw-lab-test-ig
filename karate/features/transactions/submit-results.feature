Feature: ZW Lab - Submit result (DiagnosticReport)

  Background:
    * callonce read('_ensure-patient.feature')
    * url baseUrl

  Scenario: A valid result is accepted
    # a ZW result must be based on an order (basedOn 1..1)
    * def order = call read('_submit-order.feature')
    * def result = read('data/result-create.json')
    * set result.basedOn[0].reference = 'ServiceRequest/' + order.orderId
    Given path 'DiagnosticReport'
    And request result
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

  Scenario: An invalid result is rejected
    Given path 'DiagnosticReport'
    And request read('data/result-create-invalid.json')
    When method post
    Then assert responseStatus >= 400 && responseStatus < 500
    And match response.resourceType == 'OperationOutcome'

  Scenario: A valid result conforms to the ZW result profile ($validate)
    Given path 'DiagnosticReport', '$validate'
    And param profile = profiles.result
    And request read('data/result-create.json')
    When method post
    Then match response.resourceType == 'OperationOutcome'
    And assert errorIssues(response).length == 0

  Scenario: A non-conforming result is flagged by $validate
    Given path 'DiagnosticReport', '$validate'
    And param profile = profiles.result
    And request read('data/result-profile-invalid.json')
    When method post
    Then match response.resourceType == 'OperationOutcome'
    And assert errorIssues(response).length > 0
