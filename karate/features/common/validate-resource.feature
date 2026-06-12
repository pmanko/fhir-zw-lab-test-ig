@ignore
Feature: Validate one stored resource against an IG profile (callable helper)

  Expects (from caller): resourceType, id, profile.
  Calls instance-level $validate on the server, which must have the IG
  packages loaded.

  Scenario:
    Given url shrUrl
    And path resourceType, id, '$validate'
    And param profile = profile
    When method get
    Then status 200
    And match response.resourceType == 'OperationOutcome'
    And match response.issue[*].severity !contains 'fatal'
    And match response.issue[*].severity !contains 'error'
