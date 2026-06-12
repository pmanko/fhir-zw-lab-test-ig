@ignore
Feature: Lab system interceptor - order consumer + report submitter

  Waits for a lab-system client (point it at this server). It does not store anything; it intercepts and:
   - when the lab CONSUMES orders, requires the query to be scoped to a patient, then forwards it
   - when the lab SUBMITS a report, forwards it to the real server's $validate and relays the outcome
  Scenarios are matched top-down, first match wins.

  Background:
    * configure cors = true
    * def System = Java.type('java.lang.System')
    * def target = System.getProperty('target', 'http://173.212.195.88/fhir')
    * def resultProfile = 'http://mohcc.gov.zw/fhir/lab/StructureDefinition/zw-lab-diagnostic-report'

  # Lab consumes orders, correctly scoped to a patient -> forward to the repository
  # (explicit forward: karate.proceed() drops the response body in karate 2.x mock mode)
  Scenario: methodIs('get') && pathMatches('/ServiceRequest') && (requestParams.subject != null || requestParams.patient != null)
    * karate.log('>> Lab order query (ok):', requestUri)
    Given url target
    And path 'ServiceRequest'
    And params requestParams
    When method get

  # Lab consumes orders WITHOUT a patient scope -> reject as a malformed query
  Scenario: methodIs('get') && pathMatches('/ServiceRequest')
    * karate.log('>> Lab order query MISSING patient scope:', requestUri)
    * def responseStatus = 400
    * def response = { resourceType: 'OperationOutcome', issue: [{ severity: 'error', code: 'required', diagnostics: 'order query must be scoped to a patient (subject or patient parameter)' }] }

  # Lab submits a report -> validate against the ZW result profile (not stored)
  Scenario: methodIs('post') && pathMatches('/DiagnosticReport')
    * def report = request
    * karate.log('>> Lab submitted a report; validating against', resultProfile)
    Given url target
    And path 'DiagnosticReport', '$validate'
    And param profile = resultProfile
    And request report
    When method post

  Scenario:
    * karate.proceed(target)
