@ignore
Feature: EHR interceptor - order placer + results consumer

  Waits for an EHR client (point it at this server). It does not store anything; it intercepts and:
   - when the EHR PLACES an order, forwards it to the real server's $validate and relays the outcome
   - when the EHR CONSUMES results, requires the query to be scoped to a patient, then forwards it
  Scenarios are matched top-down, first match wins.

  Background:
    * configure cors = true
    * def System = Java.type('java.lang.System')
    * def target = System.getProperty('target', 'http://173.212.195.88/fhir')
    * def orderProfile = 'http://mohcc.gov.zw/fhir/lab/StructureDefinition/zw-lab-service-request'
    * def orderBundleProfile = 'http://mohcc.gov.zw/fhir/lab/StructureDefinition/zw-lab-order-bundle'

  # EHR pushes a full order transaction Bundle to the server root (transaction ①)
  # -> validate against the ZW order bundle profile (not stored / not executed)
  Scenario: methodIs('post') && pathMatches('/') && request.resourceType == 'Bundle'
    * def bundle = request
    * karate.log('>> EHR pushed an order bundle; validating against', orderBundleProfile)
    Given url target
    And path 'Bundle', '$validate'
    And param profile = orderBundleProfile
    And request bundle
    When method post

  # EHR places an order -> validate against the ZW order profile (not stored)
  Scenario: methodIs('post') && pathMatches('/ServiceRequest')
    * def order = request
    * karate.log('>> EHR placed an order; validating against', orderProfile)
    Given url target
    And path 'ServiceRequest', '$validate'
    And param profile = orderProfile
    And request order
    When method post

  # EHR consumes results, correctly scoped to a patient -> forward to the repository
  # (explicit forward: karate.proceed() drops the response body in karate 2.x mock mode)
  Scenario: methodIs('get') && pathMatches('/DiagnosticReport') && (requestParams.subject != null || requestParams.patient != null)
    * karate.log('>> EHR result query (ok):', requestUri)
    Given url target
    And path 'DiagnosticReport'
    And params requestParams
    When method get

  # EHR consumes results WITHOUT a patient scope -> reject as a malformed query
  Scenario: methodIs('get') && pathMatches('/DiagnosticReport')
    * karate.log('>> EHR result query MISSING patient scope:', requestUri)
    * def responseStatus = 400
    * def response = { resourceType: 'OperationOutcome', issue: [{ severity: 'error', code: 'required', diagnostics: 'result query must be scoped to a patient (subject or patient parameter)' }] }

  Scenario:
    * karate.proceed(target)
