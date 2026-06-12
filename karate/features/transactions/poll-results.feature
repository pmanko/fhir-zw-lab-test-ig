Feature: ZW Lab - Poll results (DiagnosticReport)

  Background:
    * url baseUrl

  Scenario: Polling a patient with no results returns an empty bundle
    Given path 'DiagnosticReport'
    And params read('data/result-search-empty.json')
    When method get
    Then status 200
    And assert response.entry == null || response.entry.length == 0

  Scenario: After submitting a result, polling returns it
    * call read('_submit-result.feature')
    Given path 'DiagnosticReport'
    And params read('data/result-search-match.json')
    When method get
    Then status 200
    And assert response.entry != null && response.entry.length > 0
