@lab-order-fulfiller
Feature: Lab Order Fulfiller — pulls orders and claims them

  Transaction ② (order pull). The Karate suite plays the Lab Order Fulfiller
  (Senaite LIMS in the national architecture) against the Lab Order Repository.
  Covers order-pull-01 and order-pull-02.

  Background:
    * url shrUrl
    * def seeded = call read('common/submit-order.feature')

  Scenario: Pull a requested order and claim it (requested → accepted → in-progress)
    # pull: find order Tasks waiting for the laboratory
    Given path 'Task'
    And param status = 'requested'
    And param patient = 'Patient/' + seeded.patientId
    When method get
    Then status 200
    And match response.type == 'searchset'
    And match response.entry == '#[1]'
    * def task = response.entry[0].resource

    # claim: accept the Task
    * task.status = 'accepted'
    Given path 'Task', task.id
    And request task
    When method put
    Then status 200
    And match response.status == 'accepted'

    # start work: move the Task to in-progress
    * def task = response
    * task.status = 'in-progress'
    Given path 'Task', task.id
    And request task
    When method put
    Then status 200
    And match response.status == 'in-progress'

    # the new state is visible to every other actor
    Given path 'Task', task.id
    When method get
    Then status 200
    And match response.status == 'in-progress'

  Scenario: A claimed order no longer appears in the requested work list
    Given path 'Task'
    And param status = 'requested'
    And param patient = 'Patient/' + seeded.patientId
    When method get
    Then status 200
    * def task = response.entry[0].resource
    * task.status = 'accepted'
    Given path 'Task', task.id
    And request task
    When method put
    Then status 200

    Given path 'Task'
    And param status = 'requested'
    And param patient = 'Patient/' + seeded.patientId
    When method get
    Then status 200
    * def entries = response.entry || []
    And match entries == '#[0]'

  @workshop
  Scenario: TODO (workshop) — reject an order with a rejection reason
    # Steps: set Task.status = 'rejected' and add a statusReason drawn from
    # the VSZWRejectionReasons value set; assert the placer can see why.

  @workshop
  Scenario: TODO (workshop) — retrieve the full order context for testing
    # Steps: from the claimed Task, resolve basedOn (ServiceRequest), the
    # Specimen and Patient, and assert the clinical context inputs
    # (pregnancy, ART regimen) are present on the Task.
