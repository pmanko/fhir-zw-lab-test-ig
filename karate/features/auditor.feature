@auditor
Feature: Auditor — validate payloads submitted by an external system

  For testing a real EHR/LIMS (or a manual submission) playing a client role:
  the external system pushes to the repository as usual, then this suite finds
  what arrived for the given patient and validates it against the IG profiles.

  Run with:
    AUDIT_PATIENT_IDENTIFIER='<system>|<value>' ./run-tests.sh @auditor
  e.g.
    AUDIT_PATIENT_IDENTIFIER='http://mohcc.gov.zw/fhir/lab/identifier/ehr-patient-id|EHR-ZW-00123' ./run-tests.sh @auditor

  Background:
    * url shrUrl
    * def auditIdentifier = java.lang.System.getenv('AUDIT_PATIENT_IDENTIFIER')
    * if (!auditIdentifier) karate.fail('Set AUDIT_PATIENT_IDENTIFIER=<system>|<value> to run the auditor')

  Scenario: Everything submitted for the audited patient conforms to the IG profiles
    # ── locate the patient as submitted by the external system ──
    Given path 'Patient'
    And param identifier = auditIdentifier
    When method get
    Then status 200
    * if (!response.entry || response.entry.length == 0) karate.fail('AUDIT: no Patient on ' + shrUrl + ' matches identifier ' + auditIdentifier + ' — the push never stored a patient (rejected? forwarded elsewhere?), so there is nothing to audit')
    * def patientId = response.entry[0].resource.id

    # ── collect the patient's lab workflow resources ──
    * def toItems =
      """
      function(bundle, profile) {
        var out = [];
        var entries = bundle.entry || [];
        for (var i = 0; i < entries.length; i++) {
          var r = entries[i].resource;
          out.push({ resourceType: r.resourceType, id: r.id, profile: profile });
        }
        return out;
      }
      """
    * def items = toItems({ entry: [{ resource: { resourceType: 'Patient', id: patientId } }] }, profiles.patient)

    Given path 'ServiceRequest'
    And param subject = 'Patient/' + patientId
    When method get
    Then status 200
    * def items = items.concat(toItems(response, profiles.serviceRequest))

    Given path 'Task'
    And param patient = 'Patient/' + patientId
    When method get
    Then status 200
    * def items = items.concat(toItems(response, profiles.task))

    Given path 'Specimen'
    And param subject = 'Patient/' + patientId
    When method get
    Then status 200
    * def items = items.concat(toItems(response, profiles.specimen))

    Given path 'DiagnosticReport'
    And param patient = 'Patient/' + patientId
    When method get
    Then status 200
    * def items = items.concat(toItems(response, profiles.diagnosticReport))

    Given path 'Observation'
    And param patient = 'Patient/' + patientId
    When method get
    Then status 200
    * def items = items.concat(toItems(response, profiles.observation))

    # ── validate each found resource against its IG profile ──
    * karate.log('Auditing', items.length, 'resources for patient', patientId)
    * def results = call read('common/validate-resource.feature') items
