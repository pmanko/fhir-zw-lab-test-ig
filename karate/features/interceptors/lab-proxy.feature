@ignore
Feature: Lab-system conformance proxy - order fulfiller + result provider (pass-through)

  Point a real lab system (LIMS) at this proxy ONCE and leave it there. Every
  request is forwarded to the real server, so the system works normally — and
  every push is also validated against the ZW profiles on the way through.
  The verdict comes back in the X-ZW-Validation response header and a ZWPROXY
  log line; patient identifiers seen in pushes are recorded for the session
  auditor. Scenarios are matched top-down, first match wins.

  Background:
    * configure cors = true
    * def System = Java.type('java.lang.System')
    * def target = System.getProperty('target', 'http://173.212.195.88/fhir')
    # state files are port-scoped so a stale proxy from an earlier session
    # can never contaminate another session's audit or report
    * def zwPort = System.getProperty('zw.port')
    * def patientsFile = 'session' + (zwPort ? '-' + zwPort : '') + '-patients.txt'
    * def reportsFile = 'session' + (zwPort ? '-' + zwPort : '') + '-validation-reports.json'
    * def profiles =
      """
      {
        Bundle: 'http://mohcc.gov.zw/fhir/lab/StructureDefinition/zw-lab-report-bundle',
        DiagnosticReport: 'http://mohcc.gov.zw/fhir/lab/StructureDefinition/zw-lab-diagnostic-report'
      }
      """
    # error/fatal issues from a $validate OperationOutcome, in report form
    * def extractIssues =
      """
      function(oo) {
        var out = [];
        var list = (oo && oo.issue) ? oo.issue : [];
        for (var i = 0; i < list.length; i++) {
          var it = list[i];
          if (it.severity == 'error' || it.severity == 'fatal') {
            out.push({ severity: it.severity,
                       location: (it.expression && it.expression.length) ? it.expression[0] : ((it.location && it.location.length) ? it.location[0] : ''),
                       message: it.diagnostics ? it.diagnostics : ((it.details && it.details.text) ? it.details.text : '') });
          }
        }
        return out;
      }
      """
    # full per-request error reports, accumulated for the session dashboard;
    # the returned id is appended to the ZWPROXY log line so the dashboard
    # can link each request row to its report
    * def valReports = []
    * def recordReport =
      """
      function(action, subject, profile, issues) {
        var id = 'r' + (valReports.length + 1);
        valReports.push({ id: id, action: action, subject: subject, profile: profile, errors: issues.length, issues: issues });
        karate.write(JSON.stringify(valReports, null, 2), reportsFile);
        return id;
      }
      """
    # compact issue list for the X-ZW-Validation-Report response header
    # (capped + truncated to stay within header size limits; URI-encoded so
    # diagnostics text can never break the header)
    * def headerReport =
      """
      function(issues) {
        var compact = [];
        for (var i = 0; i < issues.length && i < 5; i++) {
          var m = issues[i].message || '';
          compact.push({ severity: issues[i].severity, location: issues[i].location,
                         message: m.length > 200 ? m.substring(0, 200) + '…' : m });
        }
        return encodeURIComponent(JSON.stringify(compact));
      }
      """
    * def seenPatients = {}
    * def recordPatients =
      """
      function(body) {
        var entries = (body && body.resourceType == 'Bundle') ? (body.entry || []) : [{ resource: body }];
        for (var i = 0; i < entries.length; i++) {
          var r = entries[i].resource;
          if (r && r.resourceType == 'Patient' && r.identifier) {
            for (var j = 0; j < r.identifier.length; j++) {
              var ident = r.identifier[j];
              if (ident.system && ident.value) seenPatients[ident.system + '|' + ident.value] = true;
            }
          }
        }
        karate.write(Object.keys(seenPatients).join('\n'), patientsFile);
      }
      """

  # ── Lab submits the signed report document ──
  Scenario: methodIs('post') && pathMatches('/Bundle')
    * def body = request
    * eval recordPatients(body)
    Given url target
    And path 'Bundle', '$validate'
    And param profile = profiles.Bundle
    And request body
    When method post
    * def issues = extractIssues(response)
    * def verdict = issues.length
    * def reportId = recordReport('push', 'report document', profiles.Bundle, issues)
    * karate.log('ZWPROXY|push|report document|' + verdict + ' errors|' + reportId)
    Given url target
    And path 'Bundle'
    And request body
    When method post
    * def responseHeaders = { 'Access-Control-Expose-Headers': 'X-ZW-Validation, X-ZW-Validation-Report', 'X-ZW-Validation': '#(verdict + " errors vs " + profiles.Bundle)', 'X-ZW-Validation-Report': '#(headerReport(issues))' }

  # ── Lab submits a DiagnosticReport ──
  Scenario: methodIs('post') && pathMatches('/DiagnosticReport')
    * def body = request
    Given url target
    And path 'DiagnosticReport', '$validate'
    And param profile = profiles.DiagnosticReport
    And request body
    When method post
    * def issues = extractIssues(response)
    * def verdict = issues.length
    * def reportId = recordReport('push', 'DiagnosticReport', profiles.DiagnosticReport, issues)
    * karate.log('ZWPROXY|push|DiagnosticReport|' + verdict + ' errors|' + reportId)
    Given url target
    And path 'DiagnosticReport'
    And request body
    When method post
    * def responseHeaders = { 'Access-Control-Expose-Headers': 'X-ZW-Validation, X-ZW-Validation-Report', 'X-ZW-Validation': '#(verdict + " errors vs " + profiles.DiagnosticReport)', 'X-ZW-Validation-Report': '#(headerReport(issues))' }

  # ── Lab pulls orders: must be patient-scoped, then forwarded ──
  Scenario: methodIs('get') && pathMatches('/ServiceRequest') && (requestParams.subject != null || requestParams.patient != null || requestParams['patient.identifier'] != null)
    * karate.log('ZWPROXY|pull|ServiceRequest|ok')
    Given url target
    And path 'ServiceRequest'
    And params requestParams
    When method get

  Scenario: methodIs('get') && pathMatches('/ServiceRequest')
    * def issues = [{ severity: 'error', location: 'query parameters', message: 'order query must be scoped to a patient (subject or patient parameter)' }]
    * def reportId = recordReport('pull', 'ServiceRequest', null, issues)
    * karate.log('ZWPROXY|pull|ServiceRequest|REJECTED unscoped|' + reportId)
    * def responseStatus = 400
    * def response = { resourceType: 'OperationOutcome', issue: [{ severity: 'error', code: 'required', diagnostics: 'order query must be scoped to a patient (subject or patient parameter)' }] }

  # ── capability pings (GET /metadata) are infrastructure noise: forward
  #    them silently so they never clutter the feed or the session report ──
  Scenario: methodIs('get') && pathMatches('/metadata')
    Given url target + '/metadata'
    And params requestParams
    When method get

  # ── any other GET (Task work lists etc.): forward transparently ──
  Scenario: methodIs('get')
    * karate.log('ZWPROXY|pull|' + requestUri + '|forwarded')
    Given url target + '/' + requestUri
    And params requestParams
    When method get

  # ── any other PUT (e.g. Task claims): forward transparently ──
  Scenario: methodIs('put')
    * def body = request
    * eval recordPatients(body)
    * karate.log('ZWPROXY|push|PUT ' + requestUri + '|forwarded')
    Given url target + '/' + requestUri
    And request body
    When method put

  # ── any other POST: forward transparently ──
  Scenario: methodIs('post')
    * def body = request
    * eval recordPatients(body)
    * karate.log('ZWPROXY|push|POST ' + requestUri + '|forwarded')
    Given url target + '/' + requestUri
    And request body
    When method post

  Scenario:
    * karate.proceed(target)
