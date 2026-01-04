# Data Model
**Feature**: Radar Live Post-Install Skim
**Date**: 2025-12-01
**Status**: Complete
**Constitution Version**: 1.5.0
## Overview
This document defines the data model for the Radar Live Post-Install Skim validation framework. All entities are derived from the specification (spec.md) and align with Constitution v1.5.0.
**Domain Separation**:
- **Manifest Domain**: Desired state definitions (what should be)
- **Test Domain**: Pester test execution (pass/fail per test case)
- **Orchestration Domain**: Result aggregation and ReadyForUse determination (PASS/WARN/FAIL status)
---
## 1. Core Entities
### 1.1 Environment
**Purpose**: Represents a target deployment environment for validation.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `EnvironmentName` | `enum` | `DEV`, `UAT`, `PRD` | Target environment identifier |
| `GMSInUse` | `string` | Pattern: `^[a-zA-Z0-9\-\_\$]+$` | Group Managed Service Account identity for this environment |
**Relationships**:
- Environment `HAS MANY` Components
- Environment `HAS ONE` IISConfiguration
- Environment `HAS ONE` SQLConfiguration
- Environment `HAS ONE` NetworkConfiguration
**State Transitions**: None (static configuration)
**Validation Rules**:
1. EnvironmentName must be one of: DEV, UAT, PRD
2. GMSInUse must match pattern for valid Windows identity
3. GMSInUse must match all AppPool identities in IISConfiguration
4. GMSInUse must match all SQL login identities in SQLConfiguration
---
### 1.2 Component
**Purpose**: Represents a Radar Live application component (Management Server, Calculation Service, etc.).
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `displayName` | `string` | Required, unique per environment | Human-readable component name |
| `expectedServiceName` | `string` | Required | Windows service name |
| `expectedInstallPath` | `string` | Required, valid file system path | Installation directory |
| `expectedHealthUrl` | `string` | Required, pattern: `^https?://` | Health endpoint URL (HTTP or HTTPS) |
| `certificateValidation` | `boolean` | Optional, default: `true` | Whether to validate HTTPS certificates |
| `expectedAppPool` | `string` | Optional | IIS AppPool name (for IIS-hosted components) |
| `runtimeDependencies` | `array<string>` | Optional | Array of component displayNames this component depends on |
**Relationships**:
- Component `BELONGS TO` Environment
- Component `HAS ONE` WindowsService (via expectedServiceName)
- Component `HAS ONE` HealthEndpoint (via expectedHealthUrl)
- Component `HAS OPTIONAL` AppPool (via expectedAppPool)
- Component `DEPENDS ON MANY` Components (via runtimeDependencies, must be acyclic)
**State Transitions**:
```
[Unchecked] -> [Validating] -> [Healthy] | [Unhealthy]
                  |
                  +-> [DependencyFailed] (if dependency check fails first)
```
**Validation Rules**:
1. displayName must be unique within environment
2. expectedServiceName must reference an installed Windows service
3. expectedInstallPath must exist and be accessible
4. expectedHealthUrl must use http:// or https:// protocol
5. certificateValidation only applicable for HTTPS URLs
6. expectedAppPool must reference valid AppPool in IISConfiguration.expectedAppPools
7. runtimeDependencies must form a directed acyclic graph (DAG)
8. runtimeDependencies must reference valid component displayNames in same environment
**Healthy Criteria** (per spec A1):
- Service is running AND
- Health endpoint returns success code (per healthSuccessCodes) AND
- gMSA identity matches GMSInUse (if AppPool assigned)
---
### 1.3 IISConfiguration
**Purpose**: Defines IIS hosting requirements for the environment.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `requiredWindowsFeatures` | `array<string>` | Required, min 1 item | Windows features that must be installed (e.g., `Web-Server`, `Web-Asp-Net45`) |
| `expectedSites` | `array<string>` | Required, min 1 item | IIS site names that must exist |
| `expectedAppPools` | `array<AppPoolConfig>` | Required, min 1 item | AppPool configurations with expected identities |
**Nested Type: AppPoolConfig**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `name` | `string` | Required | AppPool name |
| `identity` | `string` | Required, must match GMSInUse | Expected gMSA identity |
**Relationships**:
- IISConfiguration `BELONGS TO` Environment
- IISConfiguration `HAS MANY` AppPoolConfigs
**State Transitions**: None (static configuration)
**Validation Rules**:
1. All requiredWindowsFeatures must be installed and enabled
2. All expectedSites must exist in IIS
3. All expectedAppPools.identity must match Environment.GMSInUse
4. AppPool names must be unique within configuration
---
### 1.4 SQLConfiguration
**Purpose**: Defines SQL Server connectivity requirements.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `sqlServers` | `array<SQLServerConfig>` | Required, min 1 item | SQL Server instances and databases |
| `connectionTest` | `boolean` | Required | Whether to perform live connection test |
| `dnsResolutionTimeoutSeconds` | `number` | Optional, default: 5 | DNS resolution timeout |
| `portConnectionTimeoutSeconds` | `number` | Optional, default: 5 | Port connectivity timeout |
| `sqlMaxRetries` | `number` | Fixed: 2 | Maximum retry attempts for transient failures |
| `sqlRetryDelayMs` | `number` | Fixed: 1000 | Initial retry delay (exponential backoff) |
**Nested Type: SQLServerConfig**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `host` | `string` | Required | SQL Server hostname or FQDN |
| `databases` | `array<string>` | Required, min 1 item | Database names to validate |
**Relationships**:
- SQLConfiguration `BELONGS TO` Environment
- SQLConfiguration `HAS MANY` SQLServerConfigs
**State Transitions**: None (static configuration)
**Validation Rules**:
1. All sqlServers.host must resolve via DNS (within dnsResolutionTimeoutSeconds)
2. Port 1433 must be reachable on all hosts (within portConnectionTimeoutSeconds)
3. If connectionTest=true, live connection must succeed for all host/database combinations
4. Connection uses Windows Authentication with Environment.GMSInUse identity
---
### 1.5 NetworkConfiguration
**Purpose**: Defines network connectivity requirements.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `dnsResolution` | `array<string>` | Required | Hostnames that must resolve via DNS |
| `portOpen` | `array<PortCheck>` | Required | Ports that must be open |
| `routingChecks` | `array<RoutingCheck>` | Optional | Routing validation rules |
**Nested Type: PortCheck**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `host` | `string` | Required | Target host |
| `port` | `number` | Required, range: 1-65535 | Target port |
**Nested Type: RoutingCheck**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `destination` | `string` | Required | Target destination (hostname or IP) |
| `description` | `string` | Required | What the routing check validates |
| `critical` | `boolean` | Optional, default: true | Whether routing failure is critical |
**Relationships**:
- NetworkConfiguration `BELONGS TO` Environment
**State Transitions**: None (static configuration)
**Validation Rules**:
1. All dnsResolution hostnames must resolve successfully
2. All portOpen entries must have reachable ports
3. All routingChecks must validate successfully (or produce WARN if critical=false)
---
### 1.6 EventLogConfiguration
**Purpose**: Defines event log scanning requirements.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `lookbackHours` | `number` | Optional, default: 24 | How far back to scan event logs |
| `filterSources` | `array<string>` | Optional | Event log sources to filter on |
| `severityLevels` | `array<enum>` | Optional | Severity levels to flag (`Error`, `Warning`, `Information`) |
**Relationships**:
- EventLogConfiguration `BELONGS TO` Environment
**State Transitions**: None (static configuration)
**Validation Rules**:
1. lookbackHours must be positive number
2. severityLevels must contain valid values: Error, Warning, Information
3. If manifest omits severity levels but events exist, orchestration produces WARN
---
### 1.7 VersionChecks
**Purpose**: Defines version requirements for dependencies.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `dotnetHostingBundle` | `string` | Optional, semantic version format | Minimum .NET Hosting Bundle version |
| `powershellMinimumVersion` | `string` | Default: `7.5.0` | Minimum PowerShell version (constitutional requirement) |
| `wtwManagementModule` | `ModuleVersionCheck` | Optional | Required PowerShell module and version |
**Nested Type: ModuleVersionCheck**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `name` | `string` | Required | Module name |
| `minimumVersion` | `string` | Required, semantic version format | Minimum version |
**Relationships**:
- VersionChecks `BELONGS TO` Environment
**State Transitions**: None (static configuration)
**Validation Rules**:
1. All versions must use semantic versioning (MAJOR.MINOR.PATCH)
2. powershellMinimumVersion must be >= 7.5.0 (constitutional requirement)
3. Installed versions must meet or exceed minimums
---
### 1.8 ConfigFileChecks
**Purpose**: Defines configuration file validation requirements.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `filePaths` | `array<string>` | Optional | Config file paths to validate |
| `expectedJsonOrXmlSchema` | `object` | Optional | Schema definition for validation |
**Relationships**:
- ConfigFileChecks `BELONGS TO` Environment
**State Transitions**: None (static configuration)
**Validation Rules**:
1. All filePaths must exist and be readable
2. If schema provided, files must validate against schema
3. Schema format depends on file type (JSON Schema for .json, XSD for .xml)
---
### 1.9 HealthAndTiming
**Purpose**: Defines health check and timing requirements.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `healthTimeoutSeconds` | `number` | Default: 2 | Timeout for health endpoint checks |
| `healthMaxRetries` | `number` | Fixed: 2 | Maximum retry attempts for transient failures |
| `healthRetryDelayMs` | `number` | Fixed: 1000 | Initial retry delay (exponential backoff: 1s, 2s) |
| `healthSuccessCodes` | `array<number>` | Default: `[200, 204]` | HTTP status codes considered healthy |
| `maxTotalSkimDurationSeconds` | `number` | Default: 300 | Maximum total runtime |
**Relationships**:
- HealthAndTiming `BELONGS TO` Environment
**State Transitions**: None (static configuration)
**Validation Rules**:
1. healthTimeoutSeconds must be < maxTotalSkimDurationSeconds
2. healthSuccessCodes must contain valid HTTP status codes (100-599)
3. Total time for health checks including retries: healthTimeoutSeconds × (healthMaxRetries + 1)
4. Retry delays: 1s (first retry), 2s (second retry) - exponential backoff
---
### 1.10 Reporting
**Purpose**: Defines reporting and artifact storage requirements.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `outputFormat` | `array<enum>` | Default: `["JSON", "Markdown"]` | Output formats (`JSON`, `Markdown`, `Table`) |
| `pesterOutputFormat` | `string` | Fixed: `NUnit3` | Pester result format |
| `storeHistory` | `boolean` | Default: true | Whether to store historical artifacts (framework creates and writes to disk) |
| `historyStoragePath` | `string` | Required if storeHistory=true | Local file system path for artifact storage (framework writes here, organization manages cleanup) |
| `failOnCritical` | `boolean` | Default: true | Whether to fail on critical test failures |
| `warnThreshold` | `number` | Default: 3 | Maximum WARNs before blocking |
| `warnAcknowledgments` | `array<WarnAck>` | Optional | WARN acknowledgment records |
**Nested Type: WarnAck**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `warnId` | `string` | Required | WARN identifier |
| `operatorId` | `string` | Required | Authorized operator ID |
| `timestamp` | `string` | Required, ISO 8601 format | Acknowledgment timestamp |
| `reason` | `string` | Required | Acknowledgment reason |
**Relationships**:
- Reporting `BELONGS TO` Environment
- Reporting `HAS MANY` WarnAcknowledgments
**State Transitions**: None (static configuration)
**Validation Rules**:
1. outputFormat must contain at least one valid format
2. historyStoragePath must be valid file system path if storeHistory=true
3. historyStoragePath must be accessible and writable
4. warnThreshold must be positive number
5. WarnAcknowledgment records stored with artifacts per organizational requirements
6. **Storage vs Retention**: When storeHistory=true, framework MUST create and write artifacts (mandatory). Retention/cleanup of artifacts after creation is organizational responsibility (not framework-enforced)
---
### 1.11 SecretsAndSecurity
**Purpose**: Defines security requirements.
**Attributes**:
| Attribute | Type | Constraints | Description |
|-----------|------|-------------|-------------|
| `noSecretsInLogs` | `boolean` | Default: true | Ensure no secrets in logs (constitutional requirement) |
| `logPlaceholderForSecrets` | `string` | Default: `***REDACTED***` | Placeholder for redacted secrets |
| `leastPrivilege` | `boolean` | Default: true | Enforce least privilege execution |
**Relationships**:
- SecretsAndSecurity `BELONGS TO` Environment
**State Transitions**: None (static configuration)
**Validation Rules**:
1. If noSecretsInLogs=true, all output must be scanned for connection string patterns
2. Connection string patterns: `Server=`, `Data Source=`, `User ID=`, `Password=`, `Uid=`, `Pwd=`, `Integrated Security=`
3. If leastPrivilege=true, runtime context must be validated against disallowed roles
4. Any unredacted secret in artifacts is constitutional violation
---
## 2. Orchestration Entities
### 2.1 TestResult
**Purpose**: Represents the result of a single Pester test execution.
**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| `Name` | `string` | Test name |
| `FullName` | `string` | Fully qualified test name (includes Describe/Context) |
| `Result` | `enum` | `Passed`, `Failed`, `Skipped` |
| `Duration` | `timespan` | Test execution duration |
| `FailureMessage` | `string` | Error message if failed |
| `StackTrace` | `string` | Stack trace if failed |
| `Categories` | `array<string>` | Test categories/tags |
**State Transitions**:
```
[NotRun] -> [Running] -> [Passed] | [Failed] | [Skipped]
```
**Relationships**:
- TestResult `BELONGS TO` TestExecutionRun
- TestResult `RELATES TO` Component (via test name pattern matching)
---
### 2.2 AggregatedResult
**Purpose**: Represents orchestration-level result with criticality evaluation.
**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| `TestName` | `string` | Original test name |
| `Category` | `string` | Test category (IIS, SQL, Network, Health, etc.) |
| `Status` | `enum` | `PASS`, `WARN`, `FAIL` (orchestration interpretation) |
| `Duration` | `timespan` | Test execution duration |
| `ErrorMessage` | `string` | Redacted error message |
**State Transitions**:
```
TestResult.Passed -> AggregatedResult.PASS
TestResult.Failed (critical) -> AggregatedResult.FAIL
TestResult.Failed (non-critical) -> AggregatedResult.WARN
TestResult.Skipped -> AggregatedResult.WARN
```
**Criticality Rules**:
- Critical patterns: `*gMSA*identity*`, `*SQL*unreachable*`, `*service*not*running*`, `*component*missing*`, `*dependency*chain*`, `*Windows*feature*missing*`
- Non-critical patterns: `*event*log*warning*`, `*config*file*schema*` (unless marked critical in manifest)
- Default: Assume critical unless proven otherwise
**Relationships**:
- AggregatedResult `DERIVED FROM` TestResult
- AggregatedResult `BELONGS TO` OrchestrationReport
---
### 2.3 OrchestrationReport
**Purpose**: Final orchestration output with ReadyForUse determination.
**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| `Environment` | `string` | Environment name (DEV/UAT/PRD) |
| `Timestamp` | `string` | ISO 8601 timestamp |
| `ManifestPath` | `string` | Path to manifest used |
| `TotalTests` | `number` | Total test count |
| `PassedTests` | `number` | Passed test count |
| `FailedTests` | `number` | Failed test count (Pester domain) |
| `SkippedTests` | `number` | Skipped test count |
| `FailCount` | `number` | FAIL status count (orchestration domain) |
| `WarnCount` | `number` | WARN status count (orchestration domain) |
| `WarnThreshold` | `number` | Configured WARN threshold |
| `ReadyForUse` | `boolean` | Environment readiness determination |
| `Duration` | `timespan` | Total execution duration |
| `Results` | `array<AggregatedResult>` | Individual test results |
**ReadyForUse Calculation**:
```
ReadyForUse = (FailCount == 0) AND (WarnCount <= WarnThreshold)
```
**Exit Code Mapping**:
- ReadyForUse = true → Exit Code 0
- ReadyForUse = false → Exit Code 1
**Relationships**:
- OrchestrationReport `CONTAINS MANY` AggregatedResults
- OrchestrationReport `BASED ON` Environment manifest
---
## 3. Artifact Entities
### 3.1 TestExecutionArtifact
**Purpose**: Stored artifacts from Pester test execution.
**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| `ArtifactPath` | `string` | File system path |
| `Environment` | `string` | Environment name |
| `Timestamp` | `string` | ISO 8601 timestamp |
| `PesterResultsXml` | `file` | NUnit3 XML file (`pester-results.xml`) |
| `OrchestrationReportJson` | `file` | JSON report (`orchestration-report.json`) |
| `OrchestrationReportMd` | `file` | Markdown report (`orchestration-report.md`) |
| `OrchestrationReportTxt` | `file` | Table report (`orchestration-report.txt`) |
**Directory Structure**:
```
{historyStoragePath}/test-execution/{Environment}/{ISO8601-timestamp}/
```
---
### 3.2 EnvironmentBaselineArtifact
**Purpose**: Stored baseline artifacts for environment.
**Attributes**:
| Attribute | Type | Description |
|-----------|------|-------------|
| `ArtifactPath` | `string` | File system path |
| `Environment` | `string` | Environment name |
| `Timestamp` | `string` | ISO 8601 timestamp |
| `DesiredStateManifest` | `file` | Copy of manifest (`desired-state-manifest.{env}.json`) |
| `AggregatedReportJson` | `file` | Aggregated report with ReadyForUse (`aggregated-report.json`) |
**Directory Structure**:
```
{historyStoragePath}/environment-baseline/{Environment}/{ISO8601-timestamp}/
```
---
## 4. Entity Relationship Diagram
```
┌─────────────────┐
│  Environment    │
│  - Name         │
│  - GMSInUse     │
└────────┬────────┘
         │
         │ HAS MANY
         ├────────────────────────────────┐
         │                                │
         ▼                                ▼
┌─────────────────┐             ┌─────────────────┐
│   Component     │             │ IISConfiguration│
│  - displayName  │             │  - features     │
│  - serviceName  │             │  - sites        │
│  - installPath  │             │  - appPools     │
│  - healthUrl    │             └─────────────────┘
│  - appPool      │
│  - dependencies │
└────────┬────────┘
         │
         │ DEPENDS ON
         └─ ─ ─ ─ ─ ─ ─ ─┐
                          │
         ┌────────────────┘
         ▼
┌─────────────────┐
│   Component     │  (Dependency DAG - must be acyclic)
└─────────────────┘
Test Execution Flow:
┌─────────────────┐
│  Pester Tests   │
│  (Pass/Fail)    │
└────────┬────────┘
         │
         │ PRODUCES
         ▼
┌─────────────────┐
│   TestResult    │
│  - Result       │
│  - Duration     │
│  - Message      │
└────────┬────────┘
         │
         │ AGGREGATED TO
         ▼
┌─────────────────┐
│ AggregatedResult│
│  - Status       │  (PASS/WARN/FAIL)
│  - Criticality  │
└────────┬────────┘
         │
         │ COLLECTED IN
         ▼
┌──────────────────────┐
│ OrchestrationReport  │
│  - ReadyForUse       │
│  - FailCount         │
│  - WarnCount         │
└──────────────────────┘
```
---
## 5. State Transitions
### 5.1 Component Health State Machine
```
              ┌─────────────┐
              │  Unchecked  │
              └──────┬──────┘
                     │
              [Start Validation]
                     │
                     ▼
              ┌─────────────┐
        ┌────►│ Validating  │
        │     └──────┬──────┘
        │            │
        │     ┌──────┴──────────────────┐
        │     │                         │
        │     │                         │
        │     ▼                         ▼
        │ [Dependencies]           [All Checks]
        │     │                         │
        │     ▼                         │
        │ [Any Failed?]                 │
        │     │                         │
        │    YES                        │
        │     │                         │
        │     ▼                         │
        │ ┌──────────────────┐          │
        └─┤ DependencyFailed │          │
          └──────────────────┘          │
                                        ▼
                                 [Checks Complete]
                                        │
                        ┌───────────────┴───────────────┐
                        │                               │
                     [Pass]                          [Fail]
                        │                               │
                        ▼                               ▼
                  ┌─────────┐                    ┌────────────┐
                  │ Healthy │                    │ Unhealthy  │
                  └─────────┘                    └────────────┘
```
### 5.2 Test Result State Machine
```
┌─────────┐
│ NotRun  │
└────┬────┘
     │
     │ [Invoke-Pester]
     ▼
┌─────────┐
│ Running │
└────┬────┘
     │
     └────┬─────────────┬─────────────┐
          │             │             │
      [Pass]        [Fail]       [Skip]
          │             │             │
          ▼             ▼             ▼
    ┌─────────┐   ┌─────────┐   ┌─────────┐
    │ Passed  │   │ Failed  │   │ Skipped │
    └─────────┘   └─────────┘   └─────────┘
          │             │             │
          └─────────────┴─────────────┘
                       │
              [Orchestration Evaluates]
                       │
          ┌────────────┼────────────┐
          │            │            │
       [Pass]      [Critical]  [Non-Critical]
          │            │            │
          ▼            ▼            ▼
      ┌──────┐     ┌──────┐     ┌──────┐
      │ PASS │     │ FAIL │     │ WARN │
      └──────┘     └──────┘     └──────┘
```
---
## 6. Validation Rules Summary
### Cross-Entity Validation Rules
1. **GMSInUse Consistency**:
   - Environment.GMSInUse = IISConfiguration.expectedAppPools[*].identity
   - Environment.GMSInUse = SQLConfiguration connection identity
   - Component.expectedAppPool.identity = Environment.GMSInUse
2. **Dependency Graph Validation**:
   - Component.runtimeDependencies must form DAG (no cycles)
   - All referenced dependencies must exist in same environment
   - Topological sort must produce valid execution order
3. **Timeout Budget Validation**:
   - Sum of all test timeouts < HealthAndTiming.maxTotalSkimDurationSeconds
   - Individual health checks: healthTimeoutSeconds × (healthMaxRetries + 1) ≤ 5s (default)
4. **Artifact Path Validation**:
   - Reporting.historyStoragePath must be writable
   - Artifact directory structure must follow: `{category}/{environment}/{timestamp}/`
   - Timestamps must use ISO 8601 format: `yyyy-MM-ddTHH-mm-ssZ`
5. **Secret Redaction Validation**:
   - All TestResult.FailureMessage must be scanned for connection strings
   - All OrchestrationReport content must be redacted before persistence
   - Test for secrets: If `Test-ContainsSecret` returns true after redaction → constitutional violation
6. **ReadyForUse Determination**:
   - ReadyForUse = (FailCount == 0) AND (WarnCount ≤ warnThreshold)
   - Exit code 0 if ReadyForUse=true, 1 if ReadyForUse=false
   - Critical failures always set ReadyForUse=false regardless of WARN count
---
## Document Metadata
**Version**: 1.0
**Last Updated**: 2025-12-01
**Authors**: Radar Live Post-Install Skim Team
**Status**: Complete
**Next Review**: After Phase 1 completion