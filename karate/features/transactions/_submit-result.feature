@ignore
Feature: helper - submit a ZW result based on a fresh order, returns resultId

  Scenario:
    * url baseUrl
    * def order = call read('_submit-order.feature')
    * def result = read('data/result-create.json')
    * set result.basedOn[0].reference = 'ServiceRequest/' + order.orderId
    Given path 'DiagnosticReport'
    And request result
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300
    * def resultId = response.id
