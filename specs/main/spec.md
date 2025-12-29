# Feature Specification: Radar Live Post-Install Skim

> **Note**: This specification aligns with `.specify/memory/constitution.md` v1.6.0. Non-functional requirements are defined in Section IV (NFRs). Success criteria and test structure requirements are defined in Section V (Test Suite Success & Environment Readiness). Tolerances and thresholds are defined in Section X. All implementation must comply with constitutional constraints including idempotency, PowerShell 7.5+, Pester 5.0+, read-only operations, and timeout enforcement.

## Clarifications

### Session 2025-12-07
- Q: When running validation tests against real environments (DEV/UAT/PRD), which authentication approach should be used? → A: Service account runs from centralized automation server
- Q: When the validation script needs credentials to access SQL databases or other protected resources in real environments, where should these credentials be retrieved from? → A: Use logged-in user credentials
- Q: When the automation server needs to execute validation checks against target environment servers (DEV/UAT/PRD), which network access pattern will be used? → A: Direct network access (no remoting, run locally on each target server)
- Q: Before running the validation script for the first time on a target server, what setup steps must be completed? → A: Install PowerShell 7.5+, Pester 5.0+, verify read permissions to resources
- Q: Based on your experience, what is the most common validation failure you expect when running these checks in real environments? → A: All of the above (services not running, IIS mismatches, SQL connectivity, health endpoint timeouts)

### Session 2025-11-28
- Q: What does GMSInUse represent and how should it relate to AppPool and SQL login identities? → A: GMSInUse must match all AppPool and SQL login identities for the environment.
### Session 2025-12-01
- Q: Are additional unit tests (meta-tests) required to test the validation code itself? → A: No. The Pester validation tests ARE the product per Constitution Section III (Tests are the Product). No additional meta-tests or unit test stubs required.
- Q: How is drift detection implemented in a Pester test-based approach? → A: Drift detection = re-running same Pester tests against same manifest after patches/changes. Tests validate current state vs desired state (manifest). Test failures indicate environment configuration problems. No historical comparison or stored baselines required - tests are stateless and idempotent per Constitution Section III.
- Q: Do health endpoints use HTTP or HTTPS? → A: Both HTTP and HTTPS must be supported with optional certificate validation. Health URLs in manifest specify protocol (http:// or https://). HTTPS endpoints validate certificates by default; manifest may specify certificateValidation=false for dev/test environments with self-signed certificates.
- Q: Which Pester output format should orchestration consume? → A: NUnit3 XML format. Orchestration must invoke Pester with `-Output PassThru` to get result object AND `-OutputFormat NUnit3` with `-OutputPath` for structured XML artifact. NUnit3 provides rich metadata and best CI/CD integration.
- Q: What retry strategy should be used for transient failures? → A: Retry up to 2 times with exponential backoff (initial 1s, then 2s). Health endpoints and SQL connections automatically retry on transient failures. Total timeout per check includes retry attempts (e.g., 2s base + 1s + 2s retries = 5s max for health checks). Orchestration logs all retry attempts with timestamps.
- Q: What storage mechanism should be used for artifact storage? → A: Local file system with structured directory hierarchy. Artifacts stored at path specified in manifest (historyStoragePath) with subdirectories: `artifacts/test-execution/{environment}/{ISO8601-timestamp}/` and `artifacts/environment-baseline/{environment}/{ISO8601-timestamp}/`.
- Q: What's the difference between "storage" and "retention"? → A: **Storage = framework responsibility** (create artifacts, write to disk with proper structure when storeHistory=true). **Retention/cleanup = organizational responsibility** (decide when to delete old artifacts based on compliance requirements like SOC2 90-day retention, or storage capacity constraints). Framework enforces storage creation, organizations implement cleanup policies.
- Q: Which secret patterns must be redacted from logs and reports? → A: Connection strings only (SQL connection strings, LDAP connection strings). Redaction applies to: `Server=`, `Data Source=`, `User ID=`, `Password=`, `Uid=`, `Pwd=`, `Integrated Security=`, and full connection string values. Placeholder: `***REDACTED***`.

**Feature Branch**: `main`
**Created**: 2025-11-28
**Status**: Draft
**Input**: Constitution and implementation plan


## Data Model


The following fields are defined in the desired state manifest and must be validated by the post-install skim. **Each field below now includes explicit, testable acceptance criteria to ensure full traceability and validation.**


- **EnvironmentName**: Target environment for validation (DEV/UAT/PRD).
	- *Acceptance*: Pester tests must validate that the environment name matches one of the allowed values (DEV/UAT/PRD). Orchestration must include environment name in all report artifacts.
- **GMSInUse**: The gMSA identity string. All AppPool identities and SQL logins for this environment must match this value.
	- *Acceptance*: Pester tests must check all AppPool and SQL login identities for exact match to GMSInUse; any mismatch causes test failure (orchestration interprets as FAIL status).
- **Components**: List of all Radar Live components and their expected state, including:
	- displayName: Human-readable name for the component
		- *Acceptance*: Orchestration must include each component displayName in reports.
	- expectedServiceName: Windows service name to check for presence/running
		- *Acceptance*: Pester tests must verify service exists and is running; missing or stopped service causes test failure (orchestration interprets as FAIL).
	- expectedInstallPath: Path where the component must be installed
		- *Acceptance*: Pester tests must verify path exists and is accessible; missing path causes test failure (orchestration interprets as FAIL).
	- expectedHealthUrl: Health endpoint to check for liveness (HTTP or HTTPS per Session 2025-12-01 clarification)
		- *Acceptance*: Pester tests must perform HTTP/HTTPS GET to endpoint (protocol from URL) and validate response code against healthSuccessCodes list. HTTPS endpoints validate certificates by default; manifest may specify certificateValidation=false per component to allow self-signed certificates in dev/test. Certificate validation failures (when enabled) cause test failure (orchestration interprets as FAIL).
	- certificateValidation: Whether to validate HTTPS certificates (optional, default=true for HTTPS URLs)
		- *Acceptance*: Pester tests must validate HTTPS certificates by default. When certificateValidation=false, self-signed or invalid certificates are allowed (for dev/test only). HTTP URLs ignore this field.
	- expectedAppPool: IIS AppPool name for the component
		- *Acceptance*: Pester tests must verify AppPool exists and is assigned correct gMSA identity.
	- runtimeDependencies: Other components this one depends on (for dependency chain checks)
		- *Acceptance (A1 - Clarified)*: Pester tests must validate all listed dependencies in topological order. A dependency is **healthy** when: (1) service is running AND (2) health endpoint returns success code AND (3) gMSA identity is correct. All three conditions must pass. Circular dependencies detected during manifest parsing cause validation failure.
- **IIS**: IIS configuration requirements, including:
	- requiredWindowsFeatures: Windows features required for IIS hosting
		- *Acceptance*: Pester tests must verify all required features are installed/enabled; missing features cause test failure (orchestration interprets as FAIL).
	- expectedSites: IIS sites that must exist
		- *Acceptance*: Pester tests must verify all sites exist and are running.
	- expectedAppPools: List of AppPool configurations with expected gMSA identities
		- *Acceptance*: Pester tests must verify each AppPool exists with correct gMSA identity.
- **SQL**: SQL Server requirements, including:
	- sqlServers: SQL Server host(s) and DBs to check
		- *Acceptance*: Pester tests must attempt connection to each host/DB; connection failure causes test failure (orchestration interprets as FAIL).
	- connectionTest: Indicates a live DB connection test is required
		- *Acceptance*: Pester tests must perform live connection test if true; connection failure causes test failure (orchestration interprets as FAIL).
	- dnsResolutionTimeoutSeconds: DNS resolution timeout for SQL host
		- *Acceptance*: Pester tests must fail if DNS resolution exceeds configured timeout (per Constitution Section X).
	- portConnectionTimeoutSeconds: Port open timeout for SQL host
		- *Acceptance*: Pester tests must fail if port is not open within configured timeout (per Constitution Section X).
	- sqlMaxRetries: Maximum retry attempts for transient SQL connection failures (fixed=2 per Session 2025-12-01 clarification)
		- *Acceptance*: Pester tests must retry SQL connection attempts up to 2 times with exponential backoff (1s, 2s delays). Transient errors (timeouts, connection resets) trigger retry; authentication failures do not.
	- sqlRetryDelayMs: Initial retry delay in milliseconds for SQL connections (fixed=1000, exponential backoff: 1s, 2s per Session 2025-12-01 clarification)
		- *Acceptance*: Pester tests must wait 1s for first retry, 2s for second retry (exponential backoff). Orchestration must log all retry attempts with timestamps, specific SQL error codes, and connection strings (with secrets redacted).
- **Network**: Network requirements, including:
	- dnsResolution: DNS must resolve for all hosts
		- *Acceptance*: Pester tests must verify DNS resolution for all hosts; resolution failure causes test failure (orchestration interprets as FAIL).
	- portOpen: Ports that must be open (SQL, HTTP)
		- *Acceptance*: Pester tests must verify all listed ports are open; closed port causes test failure (orchestration interprets as FAIL).
	- routingChecks: Validate outbound routing to SQL
		- *Acceptance*: Pester tests must verify outbound routing to SQL hosts; routing failure causes test failure (orchestration interprets as FAIL).
	- routingCheckDescription: What the routing check must validate
		- *Acceptance (U1 - Clarified)*: Pester tests must validate routing per manifest description. Deviation from expected routing for critical paths (SQL connectivity) causes test failure (orchestration interprets as FAIL). Deviation for optional paths causes test failure but orchestration may interpret as WARN if marked non-critical in manifest.
- **EventLog**: Event log scan requirements, including:
	- lookbackHours: How far back to scan event logs
		- *Acceptance*: Pester tests must scan logs for the configured lookback period.
	- filterSources: Event log sources to filter on
		- *Acceptance*: Pester tests must filter logs by specified sources.
	- severityLevels: Which event severities to flag
		- *Acceptance (A2 - Clarified)*: Pester tests must scan for all severities specified in manifest. If manifest omits a severity level (e.g., only specifies Error but Warning events exist), orchestration produces WARN annotation. If specified severity events are found, test reports them; orchestration interprets based on criticality.
- **VersionChecks**: Version requirements, including:
	- dotnetHostingBundle: Minimum .NET Hosting Bundle version
		- *Acceptance*: Pester tests must verify installed version meets or exceeds minimum; version below minimum causes test failure (orchestration interprets as FAIL).
	- powershellMinimumVersion: Minimum PowerShell version
		- *Acceptance*: Pester tests must verify current PowerShell version meets or exceeds minimum (7.5+ per Constitution Section IV); version below minimum causes test failure (orchestration interprets as FAIL).
	- wtwManagementModule: Required PowerShell module and version
		- *Acceptance*: Pester tests must verify module presence and version; missing or below minimum causes test failure (orchestration interprets as FAIL).
- **ConfigFileChecks**: Config file validation requirements, including:
	- filePaths: Config files to validate
		- *Acceptance*: Pester tests must verify each file exists and is readable.
	- expectedJsonOrXmlSchema: Validate config files against schema
		- *Acceptance*: Pester tests must validate each file against provided schema; schema mismatch causes test failure (orchestration interprets as FAIL).
- **HealthAndTiming**: Health check and timing requirements, including:
	- healthTimeoutSeconds: Timeout for HTTP/HTTPS health endpoint checks (both protocols supported per Session 2025-12-01 clarification)
		- *Acceptance*: Pester tests must fail if endpoint does not respond within configured timeout (default <2s per Constitution Section X). HTTPS certificate validation failures (when enabled) are immediate test failures.
	- healthMaxRetries: Maximum retry attempts for transient health endpoint failures (fixed=2 per Session 2025-12-01 clarification)
		- *Acceptance*: Pester tests must retry health endpoint checks up to 2 times with exponential backoff (1s, 2s delays). Total time including retries must not exceed 5 seconds for default 2s timeout.
	- healthRetryDelayMs: Initial retry delay in milliseconds (fixed=1000, exponential backoff: 1s, 2s per Session 2025-12-01 clarification)
		- *Acceptance*: Pester tests must wait 1s for first retry, 2s for second retry (exponential backoff). Orchestration must log all retry attempts with timestamps and specific error messages.
	- healthSuccessCodes: HTTP codes considered healthy (e.g. default `[200,204]` if unspecified)
		- *Acceptance*: Pester tests must validate each health endpoint response against manifest-provided list; only listed codes pass the test. Unlisted codes cause test failure. Orchestration may interpret repeated transient failures as WARN after retry exhaustion. Missing list defaults to `[200,204]` with warning annotation in orchestration report.
	- maxTotalSkimDurationSeconds: Max allowed total runtime
		- *Acceptance*: Orchestration must abort if total runtime exceeds configured value (default 300s per Constitution Section X) and persist partial results tagged `PARTIAL`.

- **ResilienceAndDegradation**: Timeout enforcement and graceful degradation behavior per Constitution Section IX.
	- timeoutEnforcement: All operations with external dependencies (network, SQL, health endpoints) must enforce timeouts per Section X thresholds. Operations exceeding timeout must fail fast.
		- *Acceptance*: Orchestration must enforce timeouts per manifest configuration (defaults from Section X). Timeout violations produce test failure with clear indication of exceeded budget.
	- partialResultPersistence: Ability to persist partial output when aborting due to runtime budget exhaustion or early termination.
		- *Acceptance*: Orchestration must write partial result artifact tagged `PARTIAL` including all completed check outputs, timestamps, and list of skipped checks with reason codes.
	- gracefulDegradation: Test suite execution continues even when individual tests fail (per Constitution Section IX). Orchestration layer interprets results and applies degradation rules.
		- *Acceptance*: Pester test execution must continue for all tests regardless of individual failures (natural Pester behavior). Orchestration applies criticality rules from manifest (`critical=true|false`) - critical test failures set ReadyForUse=false, non-critical failures may produce WARN status in orchestration report.
- **Reporting**: Reporting and artifact storage requirements per Constitution Section VIII, including:
	- outputFormat: Supported output formats
		- *Acceptance*: Orchestration must produce output in all listed formats (JSON, Markdown, Table).
	- pesterOutputFormat: Pester result format for artifact storage (NUnit3 per Session 2025-12-01 clarification)
		- *Acceptance*: Orchestration must invoke Pester with `-Output PassThru` (for in-memory object) AND `-OutputFormat NUnit3` with `-OutputPath` (for structured XML artifact). Both outputs required - PassThru for immediate evaluation, NUnit3 XML for artifact storage and CI/CD integration.
	- storeHistory: Whether to store historical artifacts
		- *Acceptance*: When `storeHistory=true`, orchestration **MUST store artifacts** immediately after each validation run (framework-enforced behavior). Storage includes both Test Execution Artifacts (Pester results, timestamps, failure messages) and Environment Baseline Artifacts (desired state manifests, aggregated reports). **Storage = creation and write to disk**. Retention/cleanup of stored artifacts is an **organizational decision** outside framework scope - the framework creates artifacts but does not manage their lifecycle after creation.
	- historyStoragePath: Where to store artifacts (local file system per Session 2025-12-01 clarification)
		- *Acceptance*: Orchestration must store artifacts at configured local file system path with structured subdirectories: `artifacts/test-execution/{environment}/{ISO8601-timestamp}/` and `artifacts/environment-baseline/{environment}/{ISO8601-timestamp}/`. Missing or inaccessible path causes artifact persistence failure (validation run may continue but artifacts not stored). **Developer note**: Framework responsibility = write artifacts to disk with proper structure. Organizational responsibility = decide when/how to clean up old artifacts based on compliance needs (SOC2, HIPAA, storage capacity, etc.).
	- failOnCritical: Block on critical FAILs
		- *Acceptance*: Orchestration must set ReadyForUse=false and exit with code 1 if any critical test failure occurs (per Constitution Section V).
	- warnThreshold: Max WARNs allowed before blocking
		- *Acceptance*: Orchestration must set ReadyForUse=false if WARN count exceeds threshold (default 3 per Constitution Section X if unspecified; default usage recorded in report).
	- warnAcknowledgments: Tracking and governance of WARN review/approval.
		- *Acceptance (U2 - Clarified)*: Each WARN must be acknowledged by an **authorized operator** (defined as: operator with deployment approval role per organizational RBAC policy, documented in deployment runbook). Acknowledgment requires operator ID, timestamp, and reason. Unacknowledged WARNs at or above threshold block ReadyForUse. Acknowledgment records stored with artifacts per organizational requirements.
		- *Compliance Note*: While the framework delegates retention periods to organizations, WARN acknowledgments often have **regulatory significance** (audit trails for deployment approvals). Organizations subject to SOC2, HIPAA, or similar frameworks should retain acknowledgment records per their compliance requirements (typically 90+ days for SOC2, 6+ years for HIPAA). Framework provides storage mechanism; organizational policy defines retention period.
- **SecretsAndSecurity**: Security requirements, including:
	- noSecretsInLogs: Ensure no secrets are written to logs (connection strings per Session 2025-12-01 clarification)
		- *Acceptance*: Orchestration must scan output for connection string secrets (SQL, LDAP) and redact using placeholder. Patterns to redact: `Server=`, `Data Source=`, `User ID=`, `Password=`, `Uid=`, `Pwd=`, `Integrated Security=`, and full connection string values. Any unredacted secret in final artifacts causes constitutional violation (orchestration FAIL).
	- logPlaceholderForSecrets: Placeholder for any secret value (default=`***REDACTED***` per Session 2025-12-01 clarification)
		- *Acceptance*: Orchestration must use configured placeholder (default `***REDACTED***`) for any connection string secret in logs/reports. Placeholder must be clearly distinguishable from actual values.
	- leastPrivilege: All checks and modules must run with minimal required permissions
		- *Acceptance*: Orchestration must validate runtime context against disallowed roles/cmdlets defined in `docs/security/least-privilege.md`. Execution with excessive privileges causes orchestration FAIL. Validation enforced via code review checklist and automated scan.
- **AcceptanceTestSpec**: Minimal acceptance test for a component, including health, identity, and DB connection checks.
	- *Acceptance*: Test suite must provide Pester test coverage for each component covering: (1) health endpoint validation, (2) gMSA identity verification, (3) DB connection test.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Environment Readiness Validation (Priority: P1)

As an operator, I want to execute the validation test suite and receive a clear orchestration report (PASS/WARN/FAIL with ReadyForUse determination) so that I can confidently declare the environment ready for use.

**Why this priority**: This is the core value proposition—ensuring environments are safe to use per Constitution Section V.

**Independent Test**: Can be fully tested by executing validation test suite after install and reviewing orchestration report.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** validation test suite is executed, **Then** all Pester tests pass or fail, AND orchestration produces report with ReadyForUse determination.
2. **Given** any critical test failure (gMSA mismatch, SQL unreachable, missing component), **When** orchestration evaluates results, **Then** ReadyForUse=false AND exit code=1 (per Constitution Section V).
3. **Given** WARN count = 3 and threshold = 3, **When** orchestration evaluates results, **Then** ReadyForUse=true. **Given** WARN count = 4 and threshold = 3, **Then** ReadyForUse=false (per Constitution Section X).
	4. **Given** all AppPool identities and SQL logins, **When** Pester tests validate against GMSInUse, **Then** any mismatch causes test failure (orchestration interprets as FAIL).
5. **Given** a patched environment, **When** validation test suite is executed, **Then** any misconfigurations are detected via test failures with actionable error messages.

---

### User Story 2 - Post-Change Validation and Re-Scan (Priority: P2)

As an operator, I want the validation test suite to be re-runnable after patching or on a schedule so that environment configuration remains correct and compliant.

**Scope Clarification**: This user story combines two capabilities:
1. **Primary**: Post-change drift detection (re-run validation after patches/changes to detect configuration problems)
2. **Secondary**: Artifact storage for traceability (store validation results with ISO 8601 timestamps for audit trails)

Both capabilities share the same mechanism (re-runnable validation) but serve different purposes: drift detection ensures operational safety, artifact storage enables compliance auditing.

**Why this priority**: Ensures ongoing compliance and operational safety per Constitution Section VII (Drift Policy). Historical artifacts enable traceability and compliance auditing per Constitution Section VIII (Artifact Storage).

**Independent Test**: Can be tested by scheduling or manually triggering validation execution after environment changes.

**Acceptance Scenarios**:

1. **Given** environment after patches/changes, **When** validation test suite is executed, **Then** Pester tests validate current state against manifest (desired state).
2. **Given** any test failures, **When** orchestration evaluates results, **Then** test failure messages indicate specific configuration problems (version mismatch, schema violation, missing component, identity mismatch, service stopped).
3. **Given** non-critical test failures (per manifest `critical=false`), **When** orchestration evaluates results, **Then** orchestration may produce WARN status allowing ReadyForUse=true if within WARN threshold (default 3 per Constitution Section X).
4. **Given** CI/CD pipeline integration, **When** validation runs automatically via pipeline trigger (daily/weekly schedule), **Then** environment configuration correctness is continuously verified and drift is automatically detected without manual intervention.

> **Note**: Drift detection is implemented via scheduled CI/CD pipeline execution (see Phase 6 tasks T2301-T2302 for Azure DevOps templates). The framework provides idempotent, stateless validation (T1901-T1902); organizations configure pipeline schedules based on operational needs (PRD daily, UAT weekly, DEV on-demand per Constitution Section VII).

---

## Implementation Notes

All implementation must comply with `.specify/memory/constitution.md` v1.6.0:
- **Section III (Guiding Principles)**: Tests are the Product, DRY, Declarative, Deterministic, Idempotent
- **Section IV (NFRs)**: Idempotent, JSON output, PowerShell 7.5+, Pester 5.0+
- **Section V (Success Criteria)**: Test Suite Success (Pester domain) vs Environment Readiness (Orchestration domain)
- **Section VIII (Artifact Storage)**: ISO 8601 timestamps, environment tagging, Test Execution vs Environment Baseline categories
- **Section IX (Safety & Operations)**: Graceful degradation, read-only operations, timeout enforcement
- **Section X (Thresholds)**: Health endpoints <2s, port checks 5s, total runtime 300s, WARN threshold 3

### Developer Guidance: Storage vs Retention

**What the framework MUST do (mandatory)**:
- When `storeHistory=true`, create artifact directories with ISO 8601 timestamps
- Write all artifacts to disk immediately after validation completes
- Fail validation if `historyStoragePath` is inaccessible (cannot write artifacts)
- Structure artifacts per Constitution Section VIII (test-execution/ and environment-baseline/ subdirectories)

**What the framework DOES NOT do (organizational responsibility)**:
- Delete or cleanup old artifacts (no retention policy enforcement)
- Monitor disk space or apply storage quotas
- Archive artifacts to long-term storage
- Implement compliance-specific retention periods (SOC2 90-day, HIPAA 7-year, etc.)

**Why this separation?**:
- **Storage = framework concern**: Ensures traceability and auditability by creating artifacts consistently
- **Retention = organizational concern**: Different compliance frameworks (SOC2, HIPAA, GDPR) require different retention periods; storage capacity varies by organization; operational teams best positioned to implement lifecycle management

**Implementation pattern**:
```powershell
if ($manifest.Reporting.storeHistory) {
    # Framework responsibility: CREATE and WRITE artifacts
    Save-TestExecutionArtifacts -Path $historyStoragePath -Environment $env -Timestamp $timestamp
    Save-EnvironmentBaselineArtifacts -Path $historyStoragePath -Environment $env -Timestamp $timestamp
    # Organization responsibility: Decide when to DELETE artifacts (not framework-enforced)
}
```

For detailed least privilege criteria, see `docs/security/least-privilege.md`.
