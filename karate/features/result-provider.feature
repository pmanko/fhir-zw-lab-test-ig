@lab-result-provider
Feature: Lab Result Provider — pushes results and the signed-off report document

  Transaction ③ (result push). The Karate suite plays the Lab Result Provider
  (Senaite LIMS in the national architecture) against the Lab Result
  Repository. Covers result-push-01..03.

  Background:
    * url shrUrl
    * def seeded = call read('common/submit-order.feature')

  Scenario: Result resources and the signed-off report document are accepted
    * def created = call read('common/create-report.feature') seeded
    # the report is linked back to the originating order (result-push-03)
    Given path 'DiagnosticReport', created.diagnosticReportId
    When method get
    Then status 200
    And match response.basedOn[0].reference contains seeded.serviceRequestId
    And match response.result[0].reference contains created.observationId

  @validation
  Scenario: A conformant report document passes profile validation
    * def doc = read('../data/report-bundle.json')
    Given path 'Bundle', '$validate'
    And param profile = profiles.reportBundle
    And request doc
    When method post
    Then status 200
    And match response.resourceType == 'OperationOutcome'
    And match response.issue[*].severity !contains 'fatal'
    And match response.issue[*].severity !contains 'error'

  @workshop
  Scenario: TODO (workshop) — a report document without a legal attester fails validation
    # Steps: read data/report-bundle.json, delete the Composition's
    # attester, $validate against profiles.reportBundle and expect an error
    # (ZW.LAB.A.DE80/DE82 sign-off is mandatory).

  @workshop
  Scenario: TODO (workshop) — completing the order Task with the report as output
    # Steps: after pushing the report, set Task.status = 'completed' and add
    # output[diagnosticReport] referencing the new DiagnosticReport.
