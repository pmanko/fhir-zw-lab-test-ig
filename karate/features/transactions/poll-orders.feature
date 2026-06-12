Feature: ZW Lab - Poll orders (ServiceRequest)

  Background:
    * url baseUrl

  Scenario: Polling a patient with no orders returns an empty bundle
    Given path 'ServiceRequest'
    And params read('data/order-search-empty.json')
    When method get
    Then status 200
    And assert response.entry == null || response.entry.length == 0

  Scenario: After submitting an order, polling returns it
    * call read('_submit-order.feature')
    Given path 'ServiceRequest'
    And params read('data/order-search-match.json')
    When method get
    Then status 200
    And assert response.entry != null && response.entry.length > 0
