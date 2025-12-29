# Tasks: Radar Live Post-Install Skim

**Feature**: Radar Live Post-Install Skim
**Date**: 2025-12-01
**Input**: Design documents from `specs/main/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Organization**: Tasks organized by user story to enable independent implementation and testing.

**Format**: `- [ ] [TaskID] [P?] [Story?] Description with file path`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (US1, US2, US3)
- **File paths**: Absolute paths from repository root

## Phase 1: Setup (Project Initialization)

**Purpose**: Create project structure, install dependencies, configure tooling

**Story**: None (foundational setup)

**Tasks**:

- [X] T001 Create project directory structure (modules/, tests/, manifests/)
- [X] T002 Install Pester 5.0+ module with NUnit3 XML support
- [X] T003 Verify PowerShell 7.5+ runtime environment
- [X] T004 [P] Create module manifests (ManifestValidation.psd1, PesterInvocation.psd1, ResultAggregation.psd1, ArtifactManagement.psd1, SecretRedaction.psd1)
- [X] T005 [P] Create placeholder test files (Component.Tests.ps1, IIS.Tests.ps1, SQL.Tests.ps1, Network.Tests.ps1, EventLog.Tests.ps1, VersionChecks.Tests.ps1, ConfigFileChecks.Tests.ps1)
- [X] T006 Create example manifest templates in manifests/desired-state-manifest.dev.json

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core modules required by all user stories

**Story**: None (cross-cutting concerns)

**Independent Test Criteria**: Modules can be unit-tested independently before integration

**Tasks**:

### Module: ManifestValidation

- [X] T101 [P] Implement Import-DesiredStateManifest function in modules/ManifestValidation/ManifestValidation.psm1 (loads JSON manifest)
- [X] T102 [P] Implement Test-ManifestSchema function in modules/ManifestValidation/ManifestValidation.psm1 (validates against contracts/manifest-schema.json using Test-Json)
- [X] T103 [P] Implement Test-DependencyDAG function in modules/ManifestValidation/ManifestValidation.psm1 (validates runtimeDependencies form acyclic graph)
- [X] T104 [P] Implement Get-GMSAConsistency function in modules/ManifestValidation/ManifestValidation.psm1 (validates GMSInUse matches all AppPool/SQL identities)

### Module: SecretRedaction

- [X] T201 [P] Implement Invoke-SecretRedaction function in modules/SecretRedaction/SecretRedaction.psm1 (redacts connection strings using regex patterns: Server=, Password=, User ID=, etc.)
- [X] T202 [P] Implement Test-ContainsSecret function in modules/SecretRedaction/SecretRedaction.psm1 (validates no unredacted secrets in output)

### Module: ArtifactManagement

- [X] T301 [P] Implement New-ArtifactDirectory function in modules/ArtifactManagement/ArtifactManagement.psm1 (creates test-execution/ and environment-baseline/ subdirectories)
- [X] T302 [P] Implement Save-TestExecutionArtifacts function in modules/ArtifactManagement/ArtifactManagement.psm1 (stores Pester NUnit3 XML, orchestration-report.json, orchestration-report.md)
- [X] T303 [P] Implement Save-EnvironmentBaselineArtifacts function in modules/ArtifactManagement/ArtifactManagement.psm1 (stores manifest-snapshot.json)
- [X] ~~T304 [DEPRECATED] Implement Remove-ExpiredArtifacts function~~ (removed in Constitution v1.6.0 - retention is organizational responsibility, not framework-enforced)

### Module: PesterInvocation

- [X] T401 [P] Implement Invoke-PesterWithRetry function in modules/PesterInvocation/PesterInvocation.psm1 (executes Pester with -Output PassThru and -OutputFormat NUnit3)
- [X] T402 [P] Implement Invoke-HealthCheckWithRetry function in modules/PesterInvocation/PesterInvocation.psm1 (HTTP/HTTPS GET with 2 retries, exponential backoff 1s/2s, optional certificate validation)
- [X] T403 [P] Implement Test-SqlConnectionWithRetry function in modules/PesterInvocation/PesterInvocation.psm1 (SQL connection test with 2 retries, exponential backoff 1s/2s, transient error detection)

### Module: ResultAggregation

- [X] T501 [P] Implement Test-IsCriticalTest function in modules/ResultAggregation/ResultAggregation.psm1 (pattern matching: *gMSA*identity*, *SQL*unreachable*, *service*not*running*, *component*missing*, *dependency*chain*, *Windows*feature*missing*)
- [X] T502 [P] Implement Get-CriticalityClassification function in modules/ResultAggregation/ResultAggregation.psm1 (maps Pester test results to PASS/FAIL/WARN based on criticality patterns)
- [X] T503 [P] Implement Get-ReadyForUse function in modules/ResultAggregation/ResultAggregation.psm1 (calculates ReadyForUse = (FailCount == 0) AND (WarnCount <= WarnThreshold))
- [X] T504 [P] Implement New-OrchestrationReport function in modules/ResultAggregation/ResultAggregation.psm1 (generates JSON and Markdown reports with component health status)

---

## Phase 3: User Story 1 - Environment Readiness Validation (P1)

**Goal**: Execute validation test suite and receive clear orchestration report (PASS/WARN/FAIL with ReadyForUse determination)

**Priority**: P1 (core value proposition)

**Independent Test Criteria**:
- Fresh install → Execute validation → All Pester tests pass/fail → Orchestration produces ReadyForUse report
- Critical test failure (gMSA mismatch, SQL unreachable) → ReadyForUse=false, exit code=1
- WARN count <= threshold → ReadyForUse=true
- WARN count > threshold → ReadyForUse=false
- All AppPool/SQL identities → Match GMSInUse or test fails

**Tasks**:

### Pester Test Suite: Component Health

- [X] T601 [US1] Implement Component service validation in tests/Component.Tests.ps1 (validates expectedServiceName exists and is running)
- [X] T602 [US1] Implement Component installation path validation in tests/Component.Tests.ps1 (validates expectedInstallPath exists and is accessible)
- [X] T603 [US1] Implement Component health endpoint validation in tests/Component.Tests.ps1 (HTTP/HTTPS GET to expectedHealthUrl with certificateValidation support, validates response against healthSuccessCodes)
- [X] T604 [US1] Implement Component AppPool validation in tests/Component.Tests.ps1 (validates expectedAppPool exists and uses GMSInUse identity)
- [X] T605 [US1] Implement Component dependency chain validation in tests/Component.Tests.ps1 (validates runtimeDependencies in topological order, dependency healthy = service running AND health endpoint success AND gMSA identity correct)

### Pester Test Suite: IIS Configuration

- [X] T701 [P] [US1] Implement Windows feature validation in tests/IIS.Tests.ps1 (validates requiredWindowsFeatures are installed/enabled using Get-WindowsFeature)
- [X] T702 [P] [US1] Implement IIS site validation in tests/IIS.Tests.ps1 (validates expectedSites exist and are running using Get-IISSite)
- [X] T703 [P] [US1] Implement AppPool validation in tests/IIS.Tests.ps1 (validates expectedAppPools exist with correct gMSA identity using Get-IISAppPool)

### Pester Test Suite: SQL Connectivity

- [X] T801 [P] [US1] Implement SQL DNS resolution validation in tests/SQL.Tests.ps1 (validates sqlServers hosts resolve via Resolve-DnsName with dnsResolutionTimeoutSeconds)
- [X] T802 [P] [US1] Implement SQL port connectivity validation in tests/SQL.Tests.ps1 (validates SQL port 1433 is open using Test-NetConnection with portConnectionTimeoutSeconds)
- [X] T803 [P] [US1] Implement SQL connection validation in tests/SQL.Tests.ps1 (validates connectionTest performs live SQL connection with Test-SqlConnectionWithRetry, validates databases are accessible)

### Pester Test Suite: Network

- [X] T901 [P] [US1] Implement DNS resolution validation in tests/Network.Tests.ps1 (validates dnsResolution hosts resolve via Resolve-DnsName)
- [X] T902 [P] [US1] Implement Port connectivity validation in tests/Network.Tests.ps1 (validates portOpen entries using Test-NetConnection)
- [X] T903 [P] [US1] Implement Routing checks validation in tests/Network.Tests.ps1 (validates routingChecks destinations are reachable, marks critical based on manifest)

### Pester Test Suite: Event Logs

- [X] T1001 [P] [US1] Implement Event log scan in tests/EventLog.Tests.ps1 (scans logs for lookbackHours period, filters by filterSources and severityLevels)
- [X] T1002 [P] [US1] Implement Event severity classification in tests/EventLog.Tests.ps1 (classifies events as critical/non-critical based on criticality patterns)

### Pester Test Suite: Version Checks

- [X] T1101 [P] [US1] Implement .NET Hosting Bundle version validation in tests/VersionChecks.Tests.ps1 (validates dotnetHostingBundle meets minimum version)
- [X] T1102 [P] [US1] Implement PowerShell version validation in tests/VersionChecks.Tests.ps1 (validates powershellMinimumVersion >= 7.5)
- [X] T1103 [P] [US1] Implement PowerShell module version validation in tests/VersionChecks.Tests.ps1 (validates wtwManagementModule presence and minimum version)

### Pester Test Suite: Config File Checks

- [X] T1201 [P] [US1] Implement Config file existence validation in tests/ConfigFileChecks.Tests.ps1 (validates filePaths exist and are readable)
- [X] T1202 [P] [US1] Implement Config file schema validation in tests/ConfigFileChecks.Tests.ps1 (validates expectedJsonOrXmlSchema using Test-Json or XML validation)

### Orchestrator Integration

- [X] T1301 [US1] Implement manifest loading and validation in Invoke-PostInstallSkim.ps1 (calls Import-DesiredStateManifest, Test-ManifestSchema, Test-DependencyDAG, Get-GMSAConsistency)
- [X] T1302 [US1] Implement Pester test discovery in Invoke-PostInstallSkim.ps1 (discovers all *.Tests.ps1 files in tests/ directory)
- [X] T1303 [US1] Implement Pester execution with timeout in Invoke-PostInstallSkim.ps1 (calls Invoke-PesterWithRetry with maxTotalSkimDurationSeconds timeout, handles partial result persistence)
- [X] T1304 [US1] Implement result aggregation in Invoke-PostInstallSkim.ps1 (calls Get-CriticalityClassification for each test result, aggregates PASS/FAIL/WARN counts)
- [X] T1305 [US1] Implement ReadyForUse calculation in Invoke-PostInstallSkim.ps1 (calls Get-ReadyForUse with FailCount, WarnCount, WarnThreshold)
- [X] T1306 [US1] Implement orchestration report generation in Invoke-PostInstallSkim.ps1 (calls New-OrchestrationReport with component health status, outputs JSON/Markdown/Table formats)
- [X] T1307 [US1] Implement secret redaction in Invoke-PostInstallSkim.ps1 (calls Invoke-SecretRedaction on all output, validates no unredacted secrets)
- [X] T1308 [US1] Implement exit code logic in Invoke-PostInstallSkim.ps1 (exit 0 if ReadyForUse=true, exit 1 if ReadyForUse=false)

### Integration Testing

- [X] T1401 [US1] Create integration test manifest in manifests/desired-state-manifest.dev.json (full DEV environment configuration with all entities)
- [X] T1402 [US1] Execute full validation test suite against DEV manifest (validates end-to-end orchestration flow)
- [X] T1403 [US1] Validate orchestration report accuracy (verify PASS/FAIL/WARN classifications match test results)
- [X] T1404 [US1] Validate ReadyForUse determination (test critical failure → ReadyForUse=false, WARN threshold → ReadyForUse logic)
- [X] T1405 [US1] Validate exit codes (ReadyForUse=true → exit 0, ReadyForUse=false → exit 1)

---

## Phase 4: User Story 2 - Artifact Storage (P2)

**Goal**: Store validation artifacts for traceability and compliance auditing

**Priority**: P2 (enables historical review and audit trails)

**Independent Test Criteria**:
- Execute validation → Artifacts stored → Verify all required files present
- Artifacts include Test Execution (Pester results, timestamps, failure messages) and Environment Baseline (manifests, aggregated reports)
- Artifacts organized by environment (DEV/UAT/PRD) and ISO 8601 timestamp

**Tasks**:

### Artifact Storage Implementation

- [X] T1501 [US2] Implement artifact storage call in Invoke-PostInstallSkim.ps1 (calls Save-TestExecutionArtifacts and Save-EnvironmentBaselineArtifacts after orchestration report generation)
- [X] T1502 [US2] Validate artifact directory structure in Invoke-PostInstallSkim.ps1 (creates historyStoragePath/test-execution/{environment}/{timestamp}/ and historyStoragePath/environment-baseline/{environment}/{timestamp}/)
- [X] T1503 [US2] Implement Pester NUnit3 XML storage in Invoke-PostInstallSkim.ps1 (stores pester-results.xml in test-execution/ directory)
- [X] T1504 [US2] Implement orchestration report storage in Invoke-PostInstallSkim.ps1 (stores orchestration-report.json and orchestration-report.md in test-execution/ directory)
- [X] T1505 [US2] Implement manifest snapshot storage in Invoke-PostInstallSkim.ps1 (stores manifest-snapshot.json in environment-baseline/ directory)

---

## Phase 5: User Story 2 - Post-Change Validation and Re-Scan (P2)

**Goal**: Re-runnable validation test suite for ongoing compliance after patching/changes

**Priority**: P2 (ensures ongoing compliance and historical traceability)

**Independent Test Criteria**:
- Environment after patches → Execute validation → Pester tests validate current state vs manifest
- Test failures → Specific configuration problem messages (version mismatch, schema violation, missing component, identity mismatch, service stopped)
- Non-critical test failures → WARN status → ReadyForUse=true if within WARN threshold
- CI/CD pipeline integration → Orchestrator invoked by pipeline → Automated validation on schedule or trigger

**Tasks**:

### Idempotency and Re-Runnability

- [X] T1901 [US2] Validate test idempotency (execute validation twice against same environment, verify identical results)
- [X] T1902 [US2] Validate stateless operation (no state persisted between runs, each run validates current state independently)

### Configuration Problem Reporting

- [X] T2001 [US2] Enhance error messages in Component.Tests.ps1 (specific messages: "Service 'X' not running", "Health endpoint 'Y' returned 503", "AppPool 'Z' identity mismatch: expected 'A', actual 'B'")
- [X] T2002 [US2] Enhance error messages in IIS.Tests.ps1 (specific messages: "Windows feature 'X' not installed", "IIS site 'Y' not found")
- [X] T2003 [US2] Enhance error messages in SQL.Tests.ps1 (specific messages: "SQL host 'X' DNS resolution failed", "SQL port 1433 on 'Y' not open", "SQL database 'Z' connection failed: [error code]")
- [X] T2004 [US2] Enhance error messages in VersionChecks.Tests.ps1 (specific messages: ".NET Hosting Bundle version 'X' below minimum 'Y'", "PowerShell version 'X' below minimum 7.5")
- [X] T2005 [US2] Enhance error messages in ConfigFileChecks.Tests.ps1 (specific messages: "Config file 'X' schema validation failed: [details]")

### Integration Testing

- [ ] T2101 [US2] Execute CI/CD validation test (trigger orchestrator from pipeline context, verify execution and artifact storage, validate enhanced error messages from T2001-T2005 appear in orchestration reports with actionable guidance)
- [ ] T2102 [US2] Validate WARN threshold behavior (introduce non-critical failures → execute validation → verify WARN status → verify ReadyForUse=true if within threshold)

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, CI/CD integration, compliance verification

**Story**: None (final refinements)

**Tasks**:

### Documentation

- [X] T2201 [P] Complete quickstart.md Prerequisites section (PowerShell 7.5+, Pester 5.0+ installation instructions)
- [X] T2202 [P] Complete quickstart.md Installation section (clone repository, unblock files)
- [X] T2203 [P] Complete quickstart.md Configuration section (manifest creation examples, schema validation)
- [X] T2204 [P] Complete quickstart.md Execution section (basic usage, common parameters)
- [X] T2205 [P] Complete quickstart.md Interpreting Results section (ReadyForUse determination, test classifications, criticality patterns, orchestration report examples)
- [X] T2206 [P] Complete quickstart.md Troubleshooting section (common issues, manifest validation, health endpoint timeout, SQL connection failures, WARN threshold)
- [X] T2207 [P] Complete quickstart.md Artifact Management section (artifact structure, retention policy, cleanup)
- [X] T2208 [P] Complete quickstart.md Best Practices section (DEV/UAT/PRD configuration differences, pre-deployment checklist)
- [X] T2209 [P] Complete quickstart.md Integration Examples section (Azure DevOps pipeline examples, parameter configuration, schedule recommendations)

### CI/CD Integration

- [ ] T2301 [P] Create Azure DevOps pipeline template in .azure-pipelines/validation-pipeline.yml (PowerShell task to run Invoke-PostInstallSkim.ps1, publish Pester NUnit3 XML results)
- [ ] T2302 [P] Document CI/CD integration in quickstart.md (Azure DevOps pipeline examples and best practices)

### Compliance Verification

- [ ] T2401 Validate constitutional compliance (Section III: Tests are the Product, stateless, idempotent)
- [ ] T2402 Validate constitutional compliance (Section IV: PowerShell 7.5+, Pester 5.0+, JSON output)
- [ ] T2403 Validate constitutional compliance (Section V: Test Suite Success vs Environment Readiness separation)
- [ ] T2404 Validate constitutional compliance (Section VII: Stateless drift detection, no historical comparison)
- [ ] T2405 Validate constitutional compliance (Section VIII: ISO 8601 timestamps, environment tagging, Test Execution vs Environment Baseline categories)
- [ ] T2406 Validate constitutional compliance (Section IX: Graceful degradation, read-only operations, timeout enforcement)
- [ ] T2407 Validate constitutional compliance (Section X: Health <2s, port 5s, runtime 300s, WARN threshold 3)

### Final Integration Testing

- [ ] T2501 Execute full validation against DEV manifest (validates all components, IIS, SQL, network, event logs, versions, config files)
- [ ] T2502 Execute full validation against UAT manifest (validates production-like configuration with moderate thresholds)
- [ ] T2503 Execute full validation against PRD manifest (validates production configuration with strict thresholds)
- [ ] T2504 Validate secret redaction (verify no connection strings in artifacts)
- [ ] T2505 Validate artifact storage (verify artifacts created with correct structure, timestamps, and content completeness - combines validation from removed T1701-T1703)
- [ ] T2506 Validate orchestration report accuracy (verify all test results correctly classified as PASS/FAIL/WARN)
- [ ] T2507 Validate ReadyForUse determination (test all edge cases: 0 failures, critical failure, WARN at threshold, WARN above threshold)

---

## Dependencies

**User Story Completion Order**:
```
Phase 1: Setup
    ↓
Phase 2: Foundational (blocks all user stories)
    ↓
Phase 3: US1 (P1 - Environment Readiness Validation)
    ↓
Phase 4: US2 (P2 - Artifact Retention) [depends on US1 orchestrator]
    ↓
Phase 5: US3 (P3 - Post-Change Validation) [depends on US1 orchestrator]
    ↓
Phase 6: Polish & Cross-Cutting Concerns
```

**Blocking Dependencies**:
- US1 requires: Phase 2 (all foundational modules)
- US2 requires: US1 (orchestrator must be functional to generate artifacts)
- US3 requires: US1 (orchestrator must be functional for CI/CD integration)

**Parallel Opportunities**:
- Phase 2: All module implementations can run in parallel (T101-T104, T201-T202, T301-T304, T401-T403, T501-T504)
- Phase 3 US1: Pester test suites can run in parallel (T601-T605, T701-T703, T801-T803, T901-T903, T1001-T1002, T1101-T1103, T1201-T1202)
- Phase 6: All documentation tasks can run in parallel (T2201-T2209)

---

## Parallel Execution Examples

**Phase 2 (Foundational Modules)**:
```
Parallel Track 1: ManifestValidation module (T101-T104)
Parallel Track 2: SecretRedaction module (T201-T202)
Parallel Track 3: ArtifactManagement module (T301-T304)
Parallel Track 4: PesterInvocation module (T401-T403)
Parallel Track 5: ResultAggregation module (T501-T504)
```

**Phase 3 US1 (Pester Test Suites)**:
```
Parallel Track 1: Component tests (T601-T605)
Parallel Track 2: IIS tests (T701-T703)
Parallel Track 3: SQL tests (T801-T803)
Parallel Track 4: Network tests (T901-T903)
Parallel Track 5: EventLog tests (T1001-T1002)
Parallel Track 6: VersionChecks tests (T1101-T1103)
Parallel Track 7: ConfigFileChecks tests (T1201-T1202)

Sequential after parallel: Orchestrator integration (T1301-T1308)
```

---

## Implementation Strategy

**MVP Scope** (Minimum Viable Product):
- **Phase 1**: Setup ✅ (required)
- **Phase 2**: Foundational ✅ (required)
- **Phase 3**: US1 ✅ (core value proposition - environment readiness validation)

**MVP Delivers**:
- Manifest-driven validation test suite
- Pester tests for all validation categories
- Orchestration with ReadyForUse determination
- Basic artifact storage (no retention cleanup yet)
- Exit codes (0=ready, 1=not ready)

**Post-MVP Increments**:
1. **Increment 1** (Phase 4 - US2): Artifact storage ✅ (complete)
2. **Increment 2** (Phase 5 - US2): Post-change validation and idempotency testing
3. **Increment 3** (Phase 6): Documentation, CI/CD integration, compliance verification

**Delivery Sequence**:
```
Sprint 1: Phase 1 + Phase 2 (foundational infrastructure)
Sprint 2: Phase 3 US1 Pester tests (T601-T1202)
Sprint 3: Phase 3 US1 Orchestrator (T1301-T1308) + Integration testing (T1401-T1405)
Sprint 4: Phase 4 US2 (artifact retention)
Sprint 5: Phase 5 US2 (idempotency and error reporting)
Sprint 6: Phase 6 (polish & compliance)
```

---

## Task Count Summary

- **Phase 1 (Setup)**: 6 tasks
- **Phase 2 (Foundational)**: 18 tasks (4 ManifestValidation + 2 SecretRedaction + 4 ArtifactManagement [1 deprecated: T304] + 3 PesterInvocation + 5 ResultAggregation)
- **Phase 3 (US1)**: 47 tasks (5 Component + 3 IIS + 3 SQL + 3 Network + 2 EventLog + 3 VersionChecks + 2 ConfigFileChecks + 8 Orchestrator + 5 Integration)
- **Phase 4 (US2)**: 5 tasks (5 Artifact Storage - all complete ✅)
- **Phase 5 (US2)**: 8 tasks (2 Idempotency + 5 Error Reporting + 2 Integration - drift detection via CI/CD scheduled validation)
- **Phase 6 (Polish)**: 22 tasks (9 Documentation + 2 CI/CD + 7 Compliance + 7 Final Testing)

**Total**: 106 tasks (1 deprecated, 105 active, 11 removed as redundant or CI/CD-delegated)

**Parallel Opportunities**: 42 tasks marked [P] can run concurrently

---

## Format Validation

✅ **All tasks follow strict checklist format**:
- Checkbox: `- [ ]` (markdown checkbox) ✅
- Task ID: Sequential T001-T2507 ✅
- [P] marker: 42 tasks marked parallelizable ✅
- [Story] label: US1/US2/US3 labels on user story phases ✅
- File paths: Exact file paths included in descriptions ✅

✅ **Task organization by user story** enables independent implementation and testing
✅ **Dependencies** clearly documented (US2 depends on US1, US3 depends on US1)
✅ **MVP scope** identified (Phases 1-3 = US1 core readiness validation)
