@ignore
Feature: helper - ensure the fixed test patient exists (idempotent PUT)

  The transaction payloads in data/ reference a fixed patient id so they can
  be edited without touching the .feature scripts. This helper creates that
  patient on servers that don't already have it (e.g. a fresh sandbox with
  referential integrity enabled).

  Scenario:
    * url baseUrl
    * def patient = read('data/patient.json')
    Given path 'Patient', patient.id
    And request patient
    When method put
    Then assert responseStatus == 200 || responseStatus == 201
