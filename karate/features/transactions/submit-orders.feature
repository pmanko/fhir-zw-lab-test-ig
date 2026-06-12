Feature: ZW Lab - Submit order (ServiceRequest)

  Background:
    * callonce read('_ensure-patient.feature')
    * url baseUrl

  Scenario: A valid order is accepted
    Given path 'ServiceRequest'
    And request read('data/order-create.json')
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

  Scenario: An invalid order is rejected
    Given path 'ServiceRequest'
    And request read('data/order-create-invalid.json')
    When method post
    Then assert responseStatus >= 400 && responseStatus < 500
    And match response.resourceType == 'OperationOutcome'

  Scenario: A valid order conforms to the ZW order profile ($validate)
    Given path 'ServiceRequest', '$validate'
    And param profile = profiles.order
    And request read('data/order-create.json')
    When method post
    Then match response.resourceType == 'OperationOutcome'
    And assert errorIssues(response).length == 0

  Scenario: A non-conforming order is flagged by $validate
    Given path 'ServiceRequest', '$validate'
    And param profile = profiles.order
    And request read('data/order-profile-invalid.json')
    When method post
    Then match response.resourceType == 'OperationOutcome'
    And assert errorIssues(response).length > 0
