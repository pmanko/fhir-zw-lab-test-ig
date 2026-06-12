@ignore
Feature: helper - submit a ZW order, returns orderId

  Scenario:
    * call read('_ensure-patient.feature')
    * url baseUrl
    Given path 'ServiceRequest'
    And request read('data/order-create.json')
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300
    * def orderId = response.id
