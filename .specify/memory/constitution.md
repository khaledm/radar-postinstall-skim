
<!--
Sync Impact Report
Version change: 1.0.0 → 1.1.0 → 1.2.0 → 1.3.0 → 1.3.1 → 1.4.0 → 1.4.1 → 1.5.0 → 1.6.0
Modified principles:
  - v1.1.0: Enhanced Purpose, Guiding Principles, Success Criteria with user-provided requirements
  - v1.2.0: Redefined Success Criteria to be Pester test-outcome governed (MINOR bump - material expansion)
  - v1.3.0: Removed Section VII (Governance) as bureaucratic overhead (MINOR bump - section removal)
  - v1.3.1: Removed Section VII (Alerting & CI Policy) as redundant with Section V (PATCH bump - removed duplicate content)
  - v1.4.0: Separated Pester test success from orchestration-level environment readiness (MINOR bump - material clarification)
  - v1.4.1: Consolidated duplicates, removed contradictions, clarified terminology (PATCH bump - cleanup)
  - v1.5.0: Aligned Sections VII-IX and Amendment Process with Pester test-based approach (MINOR bump - material clarifications)
  - v1.6.0: Removed artifact retention requirements from Section VIII (MINOR bump - removed constitutional mandate for 90-day retention)
Added sections:
  - v1.1.0: Expanded Guiding Principles (tests as product, DRY, declarative, deterministic), Non-Goals
  - v1.2.0: Pester Test Structure Requirements within Success Criteria
  - v1.4.0: Test Suite Success vs Environment Readiness subsections in Section V
Removed sections:
  - v1.3.0: Section VII (Governance) - redundant with git workflow, overly bureaucratic for project scale
  - v1.3.1: Section VII (Alerting & CI Policy) - redundant with Section V exit code semantics, not applicable to Pester-based validation
Templates requiring updates:
  - plan-template.md (✅ already aligned with constitution check)
  - spec-template.md (✅ already references constitution NFRs)
  - tasks-template.md (✅ already aligned with principle-driven categorization)
  - All command files (✅ no agent-specific references found)
Follow-up TODOs: None - all placeholders resolved
Rationale for v1.5.0: Comprehensive alignment of Sections VII-IX and Amendment Process with Pester test-based infrastructure validation approach. Section VII: Removed implementation details (flags), clarified test suite execution vs orchestration, updated 2025-12-01 to remove historical comparison/baseline language. Section VIII: Distinguished test artifacts from orchestration artifacts, removed validation logic from retention policy, updated 2025-12-01 to remove drift comparison snapshots. Section IX: Aligned safety language with test execution model (Pester handles exceptions naturally), removed implementation-specific retry details. Amendment Process: Removed vague compliance review schedule.
Rationale for v1.6.0: Removed artifact retention requirements (90-day minimum) from Section VIII. Retention and cleanup policies are organizational decisions, not constitutional requirements. Section VIII renamed to "Artifact Storage" and now focuses solely on artifact types and storage requirements (timestamping, environment tagging). Retention lifecycle management is delegated to operational teams per organizational needs.
-->

# Radar Live Post-Install Skim Constitution

## Core Principles

### I. Purpose
The Radar Live Post-Install Skim exists to validate that Radar Live components (Management Server, Calculation Service, Calculation Server, Settings Manager, Schedule Manager) are installed correctly, configured properly, and operational immediately after installation. It provides a unified, repeatable, DevOps-grade Pester test suite for environment readiness that validates:

- **Component Installation**: Verify all Radar Live components are present and correctly configured
- **Configuration Correctness**: Ensure IIS, SQL, Windows Features, gMSA identity mappings, versioning, and component inter-dependencies match desired state
- **Operational Readiness**: Confirm all services are running, health endpoints respond, and the environment is ready for use
- **Drift Detection**: Identify configuration drift from established baselines across DEV, UAT, and PRD environments

This framework follows PowerShell 7.5+ standards and Microsoft's strongly-encouraged-development-guidelines, treating infrastructure validation as a first-class product ("infrastructure as tests").

### II. Scope
- **Environments**: Windows Server 2022+ (DEV, UAT, PRD) with dedicated gMSA per environment
- **Components**: Management Server, Calculation Service, Calculation Server, Settings Manager, Schedule Manager
- **Check Categories**:
	- **Configuration Drift Detection**: IIS sites/AppPools, Windows Features, folder structure, config files, version mismatches
	- **Service Account Governance**: gMSA identity verification, AppPool identity correctness, SQL login identity validation
	- **SQL Connectivity Validation**: DNS resolution, port reachability (1433), login checks, connection health
	- **Component Health Validation**: Health endpoint responses, timeout enforcement (<2s)
	- **Event Log Scanning**: Radar-specific logs, recent errors/warnings (24h lookback window)
	- **Dependency Version Validation**: .NET Hosting Bundle, PowerShell version (7.5+), IIS features
	- **Component Dependency Chain**: Topological validation (Settings Manager → Schedule Manager → Calculation Server)
	- **Consistent Environment Mappings**: Verify EnvironmentName (DEV/UAT/PRD) consistency across all artifacts

### III. Guiding Principles
- **Tests are the Product**: Infrastructure validation is implemented as Pester tests, not scripts. Every validation is a test case with clear assertions.
- **DRY (Don't Repeat Yourself)**: Code structure MUST eliminate duplication through modules, shared functions, and reusable mock patterns.
- **Declarative Desired-State Model**: All environment configuration is defined in JSON manifests per environment (desired-state-manifest.{dev|uat|prd}.json).
- **All Validations as Pester Tests**: Every check MUST be implemented as a Pester test with `Describe`, `Context`, and `It` blocks.
- **Actionable Failures**: Test failures MUST be human-readable, contain specific remediation guidance, and be CI/CD-friendly.
- **Deterministic and Idempotent**: Every test MUST produce the same result when run multiple times against the same state and MUST NOT alter system state.
- **No Secrets Logged**: Secrets, credentials, and sensitive data MUST NOT be persisted in logs, artifacts, or test output.

### IV. Non-Functional Requirements
- All checks MUST be idempotent and safe to re-run without side effects.
- All output MUST be machine-readable (JSON) and pipeline-ready for CI/CD integration.
- PowerShell version MUST be 7.5 or higher.
- Pester version MUST be 5.0 or higher.

### V. Success Criteria / Acceptance

#### Test Suite Success (Pester Domain)
Since infrastructure validation is implemented as Pester tests, **test suite success** is governed solely by Pester test outcomes:

- **All Pester tests PASS**: Every `It` block in the test suite must execute successfully. A single test failure means the test suite has failed.
- **Zero test failures**: `Invoke-Pester` MUST exit with code `0` (all tests passed) or code `1` (one or more tests failed).
- **No skipped critical tests**: Tests MUST NOT be skipped due to missing dependencies, configuration errors, or prerequisite failures.
- **Assertions succeed**: Every `Should` statement in every `It` block must evaluate to true.

**Pester Test Structure Requirements:**
- Each check category (IIS, SQL, Network, EventLog, Health, Version, Drift) MUST be implemented as separate Pester test files
- Each test file MUST use `Describe`, `Context`, and `It` blocks for organization
- Each `It` block MUST contain explicit assertions using Pester's `Should` operators (`Should -Be`, `Should -BeTrue`, `Should -Not -BeNullOrEmpty`, etc.)
- Test failures MUST include actionable error messages with specific remediation guidance
- All tests MUST be deterministic and idempotent (same input → same output, no state changes)

#### Environment Readiness (Orchestration Domain)
An environment is declared **"Ready for Use"** based on orchestration script logic:

- **Test execution**: The orchestration script executes validation check functions (which may run Pester tests or perform direct validation)
- **Result aggregation**: Check results are collected with Status values (PASS/WARN/FAIL)
- **Readiness determination**: A `ReadyForUse` boolean is calculated based on:
  - **Zero FAIL results**: All critical checks (gMSA identity, SQL connectivity, component presence, dependency chain) returned PASS or WARN
  - **WARN threshold**: Number of WARN results ≤ configured threshold (default: 3)
  - **Dependency validation**: Components with dependencies validated in topological order (Settings Manager → Schedule Manager → Calculation Server)
- **Exit code semantics**:
  - Exit code `0` = Environment ready (all critical checks passed, WARNs within threshold)
  - Exit code `1` = Environment not ready (critical check failed OR WARN threshold exceeded)

**Critical Failure Escalation**: Any critical check failure (gMSA mismatch, SQL unreachable, missing components) MUST:
- Set `ReadyForUse=false`
- Exit with code `1`
- Log full context
- Block deployment, go-live, or environment promotion

**Warning Review**: WARNs MUST be reviewed and acknowledged by an authorized operator before proceeding with deployment.

### VI. Non-Goals
This framework explicitly does NOT include:
- **Active Remediation**: No automated fixes or changes to system state. All operations are read-only.
- **High-Frequency Monitoring**: This is not a monitoring system. Scans are run post-installation, post-patching, and via CI/CD pipeline triggers (not continuously).
- **DSC-Style Configuration Enforcement**: No enforcement of desired state. The framework only validates and reports deviations.
- **Performance or Load Testing**: No stress testing, load simulation, or performance benchmarking. Only health endpoint response time validation (<2s threshold).

### VII. Drift Policy
The validation test suite MUST be executed in the following scenarios:
- **Post-installation validation**: Execute immediately after initial environment setup to verify configuration correctness
- **Post-change validation**: Execute after any patch, configuration change, or component upgrade to detect configuration problems
- **Scheduled validation**: Execute on a regular cadence via CI/CD pipeline triggers to verify ongoing configuration correctness
- **Pre-promotion validation**: Execute before environment promotion (DEV→UAT, UAT→PRD) to ensure readiness

Drift detection approach:
- Tests validate current state against desired state manifest (stateless, idempotent per Section III)
- Test failures indicate configuration problems (version mismatch, schema violation, identity mismatch, service stopped, etc.)
- Test failure messages provide actionable information about specific deviations
- No historical comparison or stored baselines required - tests re-run with same manifest produce consistent results
- Orchestration interprets test results and applies criticality rules (PASS/WARN/FAIL status, ReadyForUse determination)

### VIII. Artifact Storage
**Test Execution Artifacts** (Pester domain):
- Pester test results with pass/fail outcomes for each test case
- Test execution timestamps and duration metrics
- Test failure messages with remediation guidance

**Environment Baseline Artifacts** (Orchestration domain):
- Desired state manifests defining expected configuration (JSON format)
- Aggregated validation reports with ReadyForUse determination and status rollup

**Storage Requirements**:
- Artifact storage location and naming conventions are implementation details (not constitutionally mandated)
- Artifacts MUST be timestamped (ISO 8601 format) and tagged with environment identifier (DEV/UAT/PRD)
- Artifact retention and cleanup policies are organizational decisions outside constitutional scope

### IX. Safety & Operations
- **Graceful Degradation**: Test suite execution MUST continue even when individual tests fail. Pester naturally handles test failures without halting execution—this behavior MUST be preserved. Orchestration layer MUST handle exceptions gracefully and produce partial results.
- **Idempotency**: All validation operations MUST be idempotent. Executing the same test suite multiple times against unchanged infrastructure MUST produce identical test outcomes. No validation operation may alter system state.
- **Read-Only Operations**: All validation tests MUST be read-only. Tests MUST NOT modify IIS configuration, SQL databases, registry, filesystem, or any other system state (artifact storage excepted).
- **Timeout Enforcement**: All operations with external dependencies (network calls, SQL queries, health endpoints) MUST enforce timeouts per Section X thresholds. Operations exceeding timeout budgets MUST fail fast rather than hang indefinitely.

### X. Tolerances & Thresholds
- **Health endpoint response time**: < 2 seconds per endpoint (configurable per environment)
- **Port check timeout**: 5 seconds per port (configurable per environment)
- **Event log lookback window**: 24 hours (configurable per environment)
- **Total runtime budget**: 300 seconds (5 minutes) - MUST NOT be exceeded
- **Per-check runtime budget**: 30 seconds - checks exceeding this threshold produce FAIL status
- **WARN threshold**: Maximum 3 WARN results allowed before environment is declared NOT Ready for Use (configurable per environment, default: 3)
- **SQL connection timeout**: 15 seconds per connection attempt (standard SQL timeout)
- All thresholds MUST be configurable per environment via manifest fields to accommodate different infrastructure capabilities.

## Implementation Constraints
- **Operating System**: Windows Server 2022 or higher
- **PowerShell**: Version 7.5 or higher (REQUIRED)
- **Testing Framework**: Pester 5.0 or higher (REQUIRED)
- **Application Stack**: IIS-hosted Radar Live components (Management Server, Calculation Service, Calculation Server, Settings Manager, Schedule Manager)
- **Identity Management**: gMSA (Group Managed Service Accounts) as AppPool identities - one gMSA per environment (GMSInUse in manifest)
- **SQL Server**: Named or default instance, TCP port 1433, Windows Authentication using gMSA
- **Manifest Format**: JSON with strict schema validation
- **Testing Approach**: Infrastructure validation implemented as Pester tests (Tests are the Product per Section III). Validation tests naturally interact with real infrastructure (IIS, SQL, services). No additional meta-tests or mocked unit tests required.
- **No Performance/Load Testing**: Only health endpoint response time validation (<2s threshold)

## Amendment & Review Process
Version number and amendment dates MUST be updated with each change according to semantic versioning rules:
- **MAJOR**: Backward-incompatible changes, principle removals affecting implementation
- **MINOR**: New principles/sections added or material expansions/clarifications
- **PATCH**: Wording improvements, typo fixes, non-semantic refinements

Amendment Sync Impact Report MUST be included as HTML comment at top of document:
- Version change (old → new)
- Modified principles (with rationale)
- Added/removed sections
- Template consistency validation status
- Follow-up TODOs if any

Review triggers: Constitutional review SHOULD occur after major incidents, principle violations, or when implementation patterns consistently conflict with stated principles.

## Governance Metadata
```json
{
	"version": "1.6.0",
	"author": "Radar Live Post-Install Skim Team",
	"created": "2025-11-28",
	"ratified": "2025-11-30",
	"last_amended": "2025-12-07",
	"repository": "radar-postinstall-skim/.specify/memory/constitution.md",
	"amendment_history": [
		{
			"version": "1.0.0",
			"date": "2025-11-28",
			"changes": "Initial constitution with core principles, scope, NFRs, governance"
		},
		{
			"version": "1.1.0",
			"date": "2025-11-30",
			"changes": "Enhanced Purpose, added Guiding Principles section, added Non-Goals section"
		},
		{
			"version": "1.2.0",
			"date": "2025-11-30",
			"changes": "Redefined Success Criteria to be Pester test-outcome governed. Added Pester Test Structure Requirements. Aligned with 'Tests are the Product' principle."
		},
		{
			"version": "1.3.0",
			"date": "2025-11-30",
			"changes": "Removed Section VII (Governance) as bureaucratic overhead. Git workflow provides sufficient governance. Preserved semantic versioning rules in Amendment & Review Process."
		},
		{
			"version": "1.3.1",
			"date": "2025-11-30",
			"changes": "Removed Section VII (Alerting & CI Policy) as redundant with Section V exit code semantics. Pester handles exit codes natively. Fixed typos in section headers (Policycy, Retentionn)."
		},
		{
			"version": "1.4.0",
			"date": "2025-11-30",
			"changes": "Separated Section V into Test Suite Success (Pester domain) vs Environment Readiness (orchestration domain). Clarified that Pester tests simply pass/fail, while orchestration script interprets results to determine ReadyForUse. Removed conflation of 'critical tests', 'WARN status', and 'dependency order' from Pester success criteria."
		},
		{
			"version": "1.4.1",
			"date": "2025-11-30",
			"changes": "Comprehensive cleanup: Removed PASS/WARN/FAIL contradiction from Section III (conflicts with Pester-only approach). Removed implementation details (module names like ResultAggregator). Removed duplicate Critical Failure Escalation from Section IX (already in Section V). Enhanced threshold descriptions in Section X with rationale. Clarified terminology throughout."
		},
		{
			"version": "1.5.0",
			"date": "2025-11-30",
			"changes": "Aligned Sections VII-IX and Amendment Process with Pester test-based approach. Section VII: Clarified test suite execution vs orchestration, removed implementation details (flags). Section VIII: Distinguished test artifacts from orchestration artifacts, removed validation logic from retention policy. Section IX: Aligned safety language with test execution model (Pester handles exceptions naturally), removed implementation-specific retry details, added timeout enforcement requirement. Amendment Process: Removed vague compliance review schedule, clarified review triggers."
		},
		{
			"version": "1.5.0",
			"date": "2025-12-01",
			"changes": "Section VII: Updated drift detection approach to remove historical comparison, baseline establishment language. Section VIII: Removed 'Configuration snapshots for drift comparison' from Environment Baseline Artifacts. Aligned with stateless, idempotent paradigm per Section III."
		},
		{
			"version": "1.6.0",
			"date": "2025-12-07",
			"changes": "Section VIII: Removed artifact retention requirements (90-day minimum retention period). Retention and cleanup policies are organizational decisions outside constitutional scope. Section renamed from 'Data Retention' to 'Artifact Storage'. Retention lifecycle management delegated to operational teams."
		}
	]
}
```

**Version**: 1.6.0 | **Ratified**: 2025-11-30 | **Last Amended**: 2025-12-07
