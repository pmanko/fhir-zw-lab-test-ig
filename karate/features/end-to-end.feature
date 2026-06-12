@e2e
Feature: End-to-end — the full order-to-result loop across all six actors

  Walks the whole workflow in one scenario, passing identifiers between the
  actors exactly as the systems would:
    ① Lab Order Placer pushes the order        (EHR → Order Repository)
    ② Lab Order Fulfiller pulls and claims it  (LIMS ← Order Repository)
    ③ Lab Result Provider pushes the result    (LIMS → Result Repository)
    ④ Lab Result Consumer pulls the result     (EHR ← Result Repository)

  Scenario: A Viral Load order is placed, fulfilled, reported and consumed
    * url shrUrl

    # ── ① Lab Order Placer: push the order ──
    * def order = call read('common/submit-order.feature')

    # ── ② Lab Order Fulfiller: pull the pending order and claim it ──
    Given path 'Task'
    And param status = 'requested'
    And param patient = 'Patient/' + order.patientId
    When method get
    Then status 200
    And match response.entry == '#[1]'
    * def task = response.entry[0].resource

    * task.status = 'in-progress'
    Given path 'Task', task.id
    And request task
    When method put
    Then status 200

    # ── ③ Lab Result Provider: push the result and the signed-off document ──
    * def report = call read('common/create-report.feature') order

    # ... and complete the order Task with the report as its output
    Given path 'Task', task.id
    When method get
    Then status 200
    * def task = response
    * task.status = 'completed'
    * task.output = ([{ type: { coding: [{ system: igCanonical + '/CodeSystem/zw-task-output-type', code: 'diagnostic-report' }] }, valueReference: { reference: 'DiagnosticReport/' + report.diagnosticReportId } }])
    Given path 'Task', task.id
    And request task
    When method put
    Then status 200
    And match response.status == 'completed'

    # ── ④ Lab Result Consumer: pull the result for the patient ──
    Given path 'DiagnosticReport'
    And params ({ 'patient.identifier': systems.ehrPatientId + '|' + order.patientIdentifierValue })
    When method get
    Then status 200
    And match response.entry == '#[1]'
    * def found = response.entry[0].resource
    And match found.basedOn[0].reference contains order.serviceRequestId
    And match found.status == 'final'

    # the completed Task closes the loop back to the original order
    Given path 'Task', task.id
    When method get
    Then status 200
    And match response.status == 'completed'
    And match response.output[0].valueReference.reference contains report.diagnosticReportId
