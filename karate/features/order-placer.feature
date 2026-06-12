@lab-order-placer
Feature: Lab Order Placer — pushes laboratory orders to the Lab Order Repository

  ┌─────────────────────────────────────────────────────────────────────────┐
  │ WHAT THIS FILE IS                                                       │
  │                                                                         │
  │ A conformance test for ONE role in the lab workflow: the system that    │
  │ PLACES lab orders (in Zimbabwe's architecture, the Impilo EHR).         │
  │ The test suite plays that role — it builds a lab order and sends it —   │
  │ and the server being tested plays the record-keeper (the Lab Order      │
  │ Repository, i.e. the Shared Health Record).                            │
  │                                                                         │
  │ Each "Scenario" below is one yes/no check, readable top to bottom:     │
  │   Given … = set up the message    When … = send it                     │
  │   Then / And match … = what MUST come back for the system to conform   │
  │                                                                         │
  │ The order itself is a FHIR "transaction Bundle" — one envelope          │
  │ carrying the order (Task + ServiceRequest), the patient, and the        │
  │ specimen together, so they arrive as a single all-or-nothing unit.     │
  │ The national profile that defines what a correct envelope looks like   │
  │ is ZWLabOrderBundle. This file is Transaction ① (order push) on the    │
  │ workflow diagram.                                                       │
  └─────────────────────────────────────────────────────────────────────────┘

  Background:
    # Every scenario talks to the same server under test (the SHR);
    # its address comes from the environment (local / hosted / zw).
    * url shrUrl

  # ───────────────────────────────────────────────────────────────────────
  # CHECK 1 — "Is our order well-formed?"
  # Before sending anything for real, we ask the server to JUDGE the order
  # against the national profile ($validate = "check, don't store").
  # PASS = the verdict comes back with no errors. Nothing is saved yet.
  # ───────────────────────────────────────────────────────────────────────
  @validation
  Scenario: A conformant order bundle passes profile validation
    # Build a fresh example order (new patient + sample IDs every run,
    # so repeated demos never collide with each other).
    * def built = call read('common/build-order.feature')
    Given path 'Bundle', '$validate'
    And param profile = profiles.orderBundle
    And request built.orderBundle
    When method post
    Then status 200
    # The verdict document (OperationOutcome) must contain no errors.
    And match response.resourceType == 'OperationOutcome'
    And match response.issue[*].severity !contains 'fatal'
    And match response.issue[*].severity !contains 'error'

  # ───────────────────────────────────────────────────────────────────────
  # CHECK 2 — "Does the repository actually accept and store our order?"
  # Same kind of order, but now sent for real. PASS = the server stores
  # every resource in the envelope and answers "2xx created/ok" for each.
  # This is the moment an order officially enters the national record.
  # ───────────────────────────────────────────────────────────────────────
  Scenario: A valid order is accepted as a FHIR transaction
    * def built = call read('common/build-order.feature')
    Given request built.orderBundle
    When method post
    Then status 200
    # The reply mirrors the envelope: one success line per resource sent.
    And match response.resourceType == 'Bundle'
    And match response.type == 'transaction-response'
    And match each response.entry[*].response.status == '#regex 2\\d\\d.*'

  # ───────────────────────────────────────────────────────────────────────
  # CHECK 3 — "Is a BROKEN order caught?"
  # We deliberately send a faulty order and expect the validator to object.
  # A test kit that only proves good data passes would be half a test kit —
  # it must also prove bad data is flagged.
  # ───────────────────────────────────────────────────────────────────────
  @validation
  Scenario: A non-conformant order bundle is flagged by profile validation
    # The faulty order: ServiceRequest without a test code, Patient without
    # the EHR identifier — realistic mistakes, not random corruption.
    * def order = read('../data/order-bundle-invalid.json')
    Given path 'Bundle', '$validate'
    And param profile = profiles.orderBundle
    And request order
    When method post
    Then assert responseStatus == 200 || responseStatus == 422
    # PASS = the verdict explicitly lists errors.
    And match response.resourceType == 'OperationOutcome'
    And match response.issue[*].severity contains 'error'

  # ───────────────────────────────────────────────────────────────────────
  # CHECK 4 — "Does the repository REFUSE to store a broken order?"
  # Stronger than check 3: not just flagged when asked, but rejected at the
  # door (HTTP 4xx) when submitted for real. This requires the server to
  # validate on every write — enabled on the ZW sandbox; plain local
  # servers accept anything, hence the @pending-validation tag that skips
  # this scenario until the strict server is in front of us.
  # ───────────────────────────────────────────────────────────────────────
  @pending-validation
  Scenario: A non-conformant order is rejected by the repository (write validation)
    # order-push-03 — needs validation-on-write on the server (live on the ZW
    # sandbox; the permissive local default accepts everything, hence the tag).
    * def order = read('../data/order-bundle-invalid.json')
    Given request order
    When method post
    Then assert responseStatus >= 400 && responseStatus < 500
    And match response.resourceType == 'OperationOutcome'
    And match response.issue[*].severity contains 'error'

  # ───────────────────────────────────────────────────────────────────────
  # FUTURE CHECK — "Sending the same order twice must not duplicate it."
  # Placeholder for the workshop: real clinics resubmit after timeouts.
  # ───────────────────────────────────────────────────────────────────────
  @workshop
  Scenario: TODO (workshop) — resubmitting the same order does not create duplicates
    # Hint: add identifiers to Task/ServiceRequest and use conditional create
    # (entry.request.ifNoneExist) like the Patient entry does.
