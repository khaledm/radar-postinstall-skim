# Phase 0: Research & Architecture

**Feature**: Radar Live Post-Install Skim
**Date**: 2025-12-01
**Status**: Complete
**Constitution Version**: 1.5.0

## Executive Summary

This document consolidates research findings and architectural decisions for the Radar Live Post-Install Skim validation framework. All decisions align with Constitution v1.5.0 and incorporate clarifications from spec.md Session 2025-12-01.

**Key Architectural Decisions:**
1. **Manifest Schema**: JSON-based desired-state manifests with strict schema validation
2. **Pester Integration**: NUnit3 XML output format with PassThru for immediate evaluation
3. **Retry Strategy**: Fixed 2 retries with exponential backoff (1s, 2s delays)
4. **Artifact Storage**: Local file system with structured directory hierarchy
5. **Security**: Connection string redaction using regex pattern matching

---

## 1. Manifest Schema Design

### 1.1 Decision

**Format**: JSON desired-state manifests per environment (desired-state-manifest.{dev|uat|prd}.json)

**Rationale**:
- JSON is machine-readable, widely supported, and integrates natively with PowerShell 7.5+
- Per-environment manifests enable environment-specific configurations while maintaining schema consistency
- Strict schema validation ensures manifest correctness before test execution

### 1.2 Schema Structure

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Radar Live Post-Install Skim Desired State Manifest",
  "type": "object",
  "required": ["EnvironmentName", "GMSInUse", "Components", "IIS", "SQL", "Network", "HealthAndTiming"],
  "properties": {
    "EnvironmentName": {
      "type": "string",
      "enum": ["DEV", "UAT", "PRD"],
      "description": "Target environment for validation"
    },
    "GMSInUse": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9\\-\\_\\$]+$",
      "description": "Group Managed Service Account identity (e.g., DOMAIN\\gmsa-radar-dev$)"
    },
    "Components": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["displayName", "expectedServiceName", "expectedInstallPath", "expectedHealthUrl"],
        "properties": {
          "displayName": {
            "type": "string",
            "description": "Human-readable component name (e.g., 'Management Server')"
          },
          "expectedServiceName": {
            "type": "string",
            "description": "Windows service name to validate"
          },
          "expectedInstallPath": {
            "type": "string",
            "description": "Installation directory path (e.g., 'C:\\\\Program Files\\\\Radar Live\\\\ManagementServer')"
          },
          "expectedHealthUrl": {
            "type": "string",
            "pattern": "^https?://",
            "description": "Health endpoint URL (HTTP or HTTPS)"
          },
          "certificateValidation": {
            "type": "boolean",
            "default": true,
            "description": "Whether to validate HTTPS certificates (default: true). Set to false for dev/test with self-signed certs."
          },
          "expectedAppPool": {
            "type": "string",
            "description": "IIS AppPool name for the component"
          },
          "runtimeDependencies": {
            "type": "array",
            "items": {"type": "string"},
            "description": "List of component displayNames this component depends on"
          }
        }
      }
    },
    "IIS": {
      "type": "object",
      "required": ["requiredWindowsFeatures", "expectedSites", "expectedAppPools"],
      "properties": {
        "requiredWindowsFeatures": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Windows features required for IIS (e.g., ['Web-Server', 'Web-Asp-Net45'])"
        },
        "expectedSites": {
          "type": "array",
          "items": {"type": "string"},
          "description": "IIS site names that must exist"
        },
        "expectedAppPools": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["name", "identity"],
            "properties": {
              "name": {"type": "string"},
              "identity": {"type": "string", "description": "Expected gMSA identity"}
            }
          }
        }
      }
    },
    "SQL": {
      "type": "object",
      "required": ["sqlServers", "connectionTest"],
      "properties": {
        "sqlServers": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["host", "databases"],
            "properties": {
              "host": {"type": "string", "description": "SQL Server hostname or FQDN"},
              "databases": {"type": "array", "items": {"type": "string"}}
            }
          }
        },
        "connectionTest": {
          "type": "boolean",
          "description": "Whether to perform live SQL connection test"
        },
        "dnsResolutionTimeoutSeconds": {
          "type": "number",
          "default": 5,
          "description": "DNS resolution timeout (default: 5s)"
        },
        "portConnectionTimeoutSeconds": {
          "type": "number",
          "default": 5,
          "description": "Port connectivity timeout (default: 5s)"
        },
        "sqlMaxRetries": {
          "type": "number",
          "default": 2,
          "description": "Maximum retry attempts for transient SQL failures (fixed: 2)"
        },
        "sqlRetryDelayMs": {
          "type": "number",
          "default": 1000,
          "description": "Initial retry delay in milliseconds (fixed: 1000ms, exponential backoff)"
        }
      }
    },
    "Network": {
      "type": "object",
      "required": ["dnsResolution", "portOpen"],
      "properties": {
        "dnsResolution": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Hostnames that must resolve via DNS"
        },
        "portOpen": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["host", "port"],
            "properties": {
              "host": {"type": "string"},
              "port": {"type": "number"}
            }
          }
        },
        "routingChecks": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["destination", "description"],
            "properties": {
              "destination": {"type": "string"},
              "description": {"type": "string"},
              "critical": {"type": "boolean", "default": true}
            }
          }
        }
      }
    },
    "EventLog": {
      "type": "object",
      "properties": {
        "lookbackHours": {"type": "number", "default": 24},
        "filterSources": {"type": "array", "items": {"type": "string"}},
        "severityLevels": {"type": "array", "items": {"type": "string", "enum": ["Error", "Warning", "Information"]}}
      }
    },
    "VersionChecks": {
      "type": "object",
      "properties": {
        "dotnetHostingBundle": {"type": "string", "description": "Minimum .NET Hosting Bundle version (e.g., '8.0.0')"},
        "powershellMinimumVersion": {"type": "string", "default": "7.5.0"},
        "wtwManagementModule": {
          "type": "object",
          "properties": {
            "name": {"type": "string"},
            "minimumVersion": {"type": "string"}
          }
        }
      }
    },
    "ConfigFileChecks": {
      "type": "object",
      "properties": {
        "filePaths": {"type": "array", "items": {"type": "string"}},
        "expectedJsonOrXmlSchema": {"type": "object", "description": "Schema definition for config file validation"}
      }
    },
    "HealthAndTiming": {
      "type": "object",
      "required": ["healthTimeoutSeconds"],
      "properties": {
        "healthTimeoutSeconds": {"type": "number", "default": 2},
        "healthMaxRetries": {"type": "number", "default": 2, "description": "Fixed: 2 retries"},
        "healthRetryDelayMs": {"type": "number", "default": 1000, "description": "Fixed: 1000ms with exponential backoff"},
        "healthSuccessCodes": {
          "type": "array",
          "items": {"type": "number"},
          "default": [200, 204],
          "description": "HTTP status codes considered healthy"
        },
        "maxTotalSkimDurationSeconds": {"type": "number", "default": 300}
      }
    },
    "ResilienceAndDegradation": {
      "type": "object",
      "properties": {
        "timeoutEnforcement": {"type": "boolean", "default": true},
        "partialResultPersistence": {"type": "boolean", "default": true},
        "gracefulDegradation": {"type": "boolean", "default": true}
      }
    },
    "Reporting": {
      "type": "object",
      "required": ["outputFormat", "storeHistory", "historyStoragePath"],
      "properties": {
        "outputFormat": {
          "type": "array",
          "items": {"type": "string", "enum": ["JSON", "Markdown", "Table"]},
          "default": ["JSON", "Markdown"]
        },
        "pesterOutputFormat": {"type": "string", "default": "NUnit3", "description": "Fixed: NUnit3 XML format"},
        "storeHistory": {"type": "boolean", "default": true},
        "historyStoragePath": {"type": "string", "description": "Local file system path for artifact storage"},
        "failOnCritical": {"type": "boolean", "default": true},
        "warnThreshold": {"type": "number", "default": 3},
        "warnAcknowledgments": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["warnId", "operatorId", "timestamp", "reason"],
            "properties": {
              "warnId": {"type": "string"},
              "operatorId": {"type": "string"},
              "timestamp": {"type": "string", "format": "date-time"},
              "reason": {"type": "string"}
            }
          }
        }
      }
    },
    "SecretsAndSecurity": {
      "type": "object",
      "properties": {
        "noSecretsInLogs": {"type": "boolean", "default": true},
        "logPlaceholderForSecrets": {"type": "string", "default": "***REDACTED***"},
        "leastPrivilege": {"type": "boolean", "default": true}
      }
    }
  }
}
```

### 1.3 Validation Strategy

**ManifestValidator Module** (`src/Core/ManifestValidator.psm1`):
- Load manifest JSON and validate against schema using `Test-Json -Schema`
- Validate cross-field constraints:
  - GMSInUse matches all AppPool identities
  - Component runtimeDependencies reference valid component displayNames
  - Circular dependency detection using topological sort
- Return validation result with actionable error messages

**Example Validation**:
```powershell
$manifest = Get-Content -Path "manifests/desired-state-manifest.dev.json" | ConvertFrom-Json
$schemaPath = "schemas/manifest-schema.json"
$isValid = Test-Json -Json ($manifest | ConvertTo-Json -Depth 10) -SchemaFile $schemaPath

if (-not $isValid) {
    throw "Manifest validation failed. See error messages above."
}
```

### 1.4 Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| YAML manifests | Human-readable, less verbose | No native PowerShell support, requires external module | **Rejected** - JSON is PowerShell-native |
| XML manifests | Strong schema support (XSD) | Verbose, less modern | **Rejected** - JSON more concise |
| PowerShell DSC | Mature, built-in | Stateful, configuration enforcement (violates Constitution Section VI) | **Rejected** - This is validation, not enforcement |

---

## 2. Pester Integration Patterns

### 2.1 Decision

**Pester Invocation**: Use `-Output PassThru` for immediate evaluation AND `-OutputFormat NUnit3` with `-OutputPath` for artifact storage

**Retry Logic**: Implement exponential backoff retry pattern within Pester tests for transient failures

**Rationale**:
- NUnit3 XML provides rich metadata (test hierarchy, timing, error messages) with best CI/CD integration
- PassThru returns PowerShell object for immediate orchestration processing
- Retry logic in tests ensures resilience against transient network/SQL issues while maintaining test determinism

### 2.2 Pester Invocation Pattern

**Orchestration Script** (`Invoke-PostInstallSkim.ps1`):
```powershell
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = "src/Pester"
$pesterConfig.Run.PassThru = $true
$pesterConfig.Output.Verbosity = "Detailed"
$pesterConfig.TestResult.Enabled = $true
$pesterConfig.TestResult.OutputFormat = "NUnit3"
$pesterConfig.TestResult.OutputPath = "artifacts/test-execution/$env/$timestamp/pester-results.xml"

$pesterResult = Invoke-Pester -Configuration $pesterConfig

# Immediate evaluation using PassThru object
$totalTests = $pesterResult.TotalCount
$passedTests = $pesterResult.PassedCount
$failedTests = $pesterResult.FailedCount
$testsPassed = ($failedTests -eq 0)

# Parse NUnit3 XML for detailed artifact retention
[xml]$nunitXml = Get-Content -Path $pesterConfig.TestResult.OutputPath
```

### 2.3 NUnit3 XML Parsing

**ResultAggregator Module** (`src/Core/ResultAggregator.psm1`):
```powershell
function ConvertFrom-NUnit3Xml {
    param([xml]$NUnitXml)

    $testResults = @()
    foreach ($testCase in $NUnitXml.SelectNodes("//test-case")) {
        $testResults += [PSCustomObject]@{
            Name = $testCase.name
            FullName = $testCase.fullname
            Result = $testCase.result  # Passed, Failed, Skipped
            Duration = [TimeSpan]::FromSeconds($testCase.time)
            FailureMessage = $testCase.failure.message
            StackTrace = $testCase.failure.'stack-trace'
            Categories = @($testCase.SelectNodes("properties/property[@name='Category']/@value") | ForEach-Object { $_.Value })
        }
    }

    return $testResults
}
```

### 2.4 Retry Logic Implementation

**Pattern**: Exponential backoff with fixed 2 retries (1s, 2s delays)

**Health Endpoint Retry Example** (`src/Pester/Health.Tests.ps1`):
```powershell
Describe "Component Health Endpoints" {
    BeforeAll {
        $manifest = Get-Content -Path $env:MANIFEST_PATH | ConvertFrom-Json
        $healthConfig = $manifest.HealthAndTiming

        function Invoke-HealthCheckWithRetry {
            param(
                [string]$Url,
                [int]$TimeoutSeconds,
                [bool]$ValidateCertificate = $true,
                [int[]]$SuccessCodes = @(200, 204)
            )

            $maxRetries = 2
            $retryDelayMs = 1000
            $attempt = 0

            while ($attempt -le $maxRetries) {
                try {
                    $params = @{
                        Uri = $Url
                        TimeoutSec = $TimeoutSeconds
                        UseBasicParsing = $true
                        SkipCertificateCheck = (-not $ValidateCertificate)
                    }

                    $response = Invoke-WebRequest @params -ErrorAction Stop

                    if ($response.StatusCode -in $SuccessCodes) {
                        return @{
                            Success = $true
                            StatusCode = $response.StatusCode
                            Attempt = $attempt
                        }
                    } else {
                        throw "Unexpected status code: $($response.StatusCode)"
                    }
                } catch {
                    $attempt++
                    if ($attempt -le $maxRetries) {
                        $delay = $retryDelayMs * [Math]::Pow(2, $attempt - 1)
                        Write-Host "Attempt $attempt failed: $($_.Exception.Message). Retrying in ${delay}ms..."
                        Start-Sleep -Milliseconds $delay
                    } else {
                        return @{
                            Success = $false
                            ErrorMessage = $_.Exception.Message
                            Attempt = $attempt
                        }
                    }
                }
            }
        }
    }

    Context "When validating component health endpoints" {
        It "Health endpoint <displayName> at <expectedHealthUrl> should return success code" -ForEach $manifest.Components {
            $result = Invoke-HealthCheckWithRetry -Url $expectedHealthUrl -TimeoutSeconds $healthConfig.healthTimeoutSeconds -ValidateCertificate $certificateValidation -SuccessCodes $healthConfig.healthSuccessCodes

            $result.Success | Should -BeTrue -Because "Health endpoint must return one of: $($healthConfig.healthSuccessCodes -join ', ')"
        }
    }
}
```

**SQL Connection Retry Example** (`src/Pester/SQL.Tests.ps1`):
```powershell
function Test-SqlConnectionWithRetry {
    param(
        [string]$ServerInstance,
        [string]$Database,
        [int]$MaxRetries = 2,
        [int]$RetryDelayMs = 1000
    )

    $attempt = 0
    while ($attempt -le $MaxRetries) {
        try {
            $connectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=True;Connection Timeout=15"
            $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
            $connection.Open()
            $connection.Close()

            return @{
                Success = $true
                Attempt = $attempt
            }
        } catch {
            $errorCode = $_.Exception.InnerException.Number
            # Retry on transient errors (timeout, connection reset), not auth failures
            $transientErrors = @(-2, 64, 233, 10053, 10054)  # Timeout, network errors

            if ($errorCode -in $transientErrors) {
                $attempt++
                if ($attempt -le $MaxRetries) {
                    $delay = $RetryDelayMs * [Math]::Pow(2, $attempt - 1)
                    Write-Host "SQL connection attempt $attempt failed (error $errorCode): $($_.Exception.Message). Retrying in ${delay}ms..."
                    Start-Sleep -Milliseconds $delay
                } else {
                    return @{
                        Success = $false
                        ErrorMessage = $_.Exception.Message
                        ErrorCode = $errorCode
                        Attempt = $attempt
                    }
                }
            } else {
                # Authentication or non-transient error - don't retry
                return @{
                    Success = $false
                    ErrorMessage = $_.Exception.Message
                    ErrorCode = $errorCode
                    Attempt = $attempt
                    NonTransient = $true
                }
            }
        }
    }
}
```

### 2.5 Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| NUnitXml (legacy) | Simple, well-known | Less metadata, legacy format | **Rejected** - NUnit3 is modern standard |
| JUnitXml | Wide tool support | Less PowerShell-native | **Rejected** - NUnit3 better Pester integration |
| Custom JSON | Full control | Reinventing wheel, no CI/CD integration | **Rejected** - NUnit3 standard format |
| No retry logic | Simpler tests | Fragile against transient failures | **Rejected** - Resilience required per Constitution Section IX |
| Configurable retry | More flexible | Increased complexity | **Rejected** - Fixed 2 retries sufficient per Session 2025-12-01 |

---

## 3. Artifact Storage Strategy

### 3.1 Decision

**Storage Mechanism**: Local file system with structured directory hierarchy
**Directory Structure**:
```
{historyStoragePath}/
├── test-execution/
│   ├── DEV/
│   │   ├── 2025-12-01T14-30-00Z/
│   │   │   ├── pester-results.xml (NUnit3 format)
│   │   │   ├── orchestration-report.json
│   │   │   ├── orchestration-report.md
│   │   │   └── orchestration-report.txt (table format)
│   │   └── 2025-12-01T08-15-00Z/
│   ├── UAT/
│   └── PRD/
└── environment-baseline/
    ├── DEV/
    │   ├── 2025-12-01T14-30-00Z/
    │   │   ├── desired-state-manifest.dev.json (copy)
    │   │   └── aggregated-report.json
    │   └── 2025-12-01T08-15-00Z/
    ├── UAT/
    └── PRD/
```

**Rationale**:
- Local file system is simplest, no external dependencies, works offline
- Structured hierarchy enables easy filtering by environment and timestamp
- ISO 8601 timestamp format ensures chronological sorting
- Separation of test-execution vs environment-baseline artifacts aligns with Constitution Section VIII

### 3.2 Artifact Storage Implementation

**ArtifactStore Module** (`src/Core/ArtifactStore.psm1`):
```powershell
function New-ArtifactDirectory {
    param(
        [string]$BasePath,
        [ValidateSet('DEV','UAT','PRD')]
        [string]$Environment,
        [ValidateSet('test-execution','environment-baseline')]
        [string]$Category
    )

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ssZ"
    $artifactPath = Join-Path $BasePath $Category $Environment $timestamp

    if (-not (Test-Path $artifactPath)) {
        New-Item -ItemType Directory -Path $artifactPath -Force | Out-Null
    }

    return @{
        Path = $artifactPath
        Environment = $Environment
        Timestamp = $timestamp
        Category = $Category
    }
}

function Save-TestExecutionArtifacts {
    param(
        [string]$ArtifactPath,
        [string]$PesterXmlPath,
        [PSCustomObject]$OrchestrationReport
    )

    # Copy Pester NUnit3 XML
    Copy-Item -Path $PesterXmlPath -Destination (Join-Path $ArtifactPath "pester-results.xml")

    # Save orchestration reports in multiple formats
    $OrchestrationReport | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $ArtifactPath "orchestration-report.json") -Encoding UTF8

    # Generate Markdown report
    $mdContent = ConvertTo-MarkdownReport -Report $OrchestrationReport
    $mdContent | Out-File -FilePath (Join-Path $ArtifactPath "orchestration-report.md") -Encoding UTF8

    # Generate table report
    $tableContent = ConvertTo-TableReport -Report $OrchestrationReport
    $tableContent | Out-File -FilePath (Join-Path $ArtifactPath "orchestration-report.txt") -Encoding UTF8
}

function Save-EnvironmentBaselineArtifacts {
    param(
        [string]$ArtifactPath,
        [string]$ManifestPath,
        [PSCustomObject]$AggregatedReport
    )

    # Copy desired-state manifest
    Copy-Item -Path $ManifestPath -Destination (Join-Path $ArtifactPath (Split-Path $ManifestPath -Leaf))

    # Save aggregated report with ReadyForUse determination
    $AggregatedReport | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $ArtifactPath "aggregated-report.json") -Encoding UTF8
}
```

### 3.3 Artifact Lifecycle Management

Artifact retention and cleanup policies are organizational decisions outside the framework's scope. Organizations should implement their own retention policies based on:
- Compliance requirements (audit retention periods)
- Storage capacity constraints
- Incident investigation windows
- Performance baseline tracking needs

**Recommended Approaches:**
- File system quotas or scheduled cleanup scripts per organizational policy
- Integration with centralized log aggregation/SIEM systems
- Archival to long-term storage for compliance auditing
- Data lifecycle management per organizational governance

### 3.4 Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| Azure Blobs | Centralized, scalable, no local disk usage | Requires Azure connectivity, more complex, costs | **Rejected** - Local file system simpler per Session 2025-12-01 |
| Network file share (SMB) | Centralized | Requires network/permissions, single point of failure | **Rejected** - Local file system more reliable |
| SQL database | Queryable, relational | Overkill, dependency on SQL, performance overhead | **Rejected** - File system sufficient for read-heavy workload |
| Flat directory structure | Simple | Hard to filter by environment/date, scalability issues | **Rejected** - Structured hierarchy better |

---

## 4. Orchestration Algorithm

### 4.1 Decision

**Orchestration Flow**:
1. Load and validate manifest
2. Execute Pester test suite with NUnit3 output
3. Parse Pester results (PassThru object + NUnit3 XML)
4. Aggregate results with criticality rules
5. Calculate ReadyForUse determination
6. Generate multi-format reports (JSON, Markdown, Table)
7. Store artifacts (test-execution + environment-baseline)
8. Exit with appropriate code (0 = ready, 1 = not ready)

**ReadyForUse Calculation**:
```
ReadyForUse = (FailCount == 0) AND (WarnCount <= WarnThreshold)
```

**Rationale**:
- Clear separation of Pester domain (test pass/fail) and orchestration domain (ReadyForUse determination)
- Criticality rules applied during result aggregation, not during test execution
- WARN status allows non-critical failures within threshold
- Multi-format reporting supports different audiences (operators, auditors, CI/CD)

### 4.2 Orchestration Implementation

**Invoke-PostInstallSkim.ps1**:
```powershell
#!/usr/bin/env pwsh
#Requires -Version 7.5

param(
    [Parameter(Mandatory)]
    [ValidateSet('DEV','UAT','PRD')]
    [string]$Environment,

    [string]$ManifestPath = "manifests/desired-state-manifest.$($Environment.ToLower()).json",

    [string]$ArtifactBasePath = "artifacts"
)

# Step 1: Load and validate manifest
Import-Module "./src/Core/ManifestValidator.psm1"
$manifest = Get-Content -Path $ManifestPath | ConvertFrom-Json
$validationResult = Test-Manifest -Manifest $manifest
if (-not $validationResult.IsValid) {
    Write-Error "Manifest validation failed: $($validationResult.Errors -join ', ')"
    exit 1
}

# Step 2: Execute Pester test suite
$timestamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ssZ"
$pesterOutputPath = "artifacts/test-execution/$Environment/$timestamp/pester-results.xml"
New-Item -ItemType Directory -Path (Split-Path $pesterOutputPath) -Force | Out-Null

$env:MANIFEST_PATH = $ManifestPath  # Pass manifest path to tests

$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = "src/Pester"
$pesterConfig.Run.PassThru = $true
$pesterConfig.Output.Verbosity = "Detailed"
$pesterConfig.TestResult.Enabled = $true
$pesterConfig.TestResult.OutputFormat = "NUnit3"
$pesterConfig.TestResult.OutputPath = $pesterOutputPath

$pesterResult = Invoke-Pester -Configuration $pesterConfig

# Step 3 & 4: Parse and aggregate results
Import-Module "./src/Core/ResultAggregator.psm1"
$testResults = ConvertFrom-NUnit3Xml -NUnitXmlPath $pesterOutputPath

$aggregatedResults = @{
    Environment = $Environment
    Timestamp = $timestamp
    ManifestPath = $ManifestPath
    TotalTests = $pesterResult.TotalCount
    PassedTests = $pesterResult.PassedCount
    FailedTests = $pesterResult.FailedCount
    SkippedTests = $pesterResult.SkippedCount
    Duration = $pesterResult.Duration
    Results = @()
}

# Apply criticality rules from manifest
foreach ($testResult in $testResults) {
    $status = if ($testResult.Result -eq "Passed") { "PASS" }
              elseif ($testResult.Result -eq "Failed") {
                  # Check if test is critical based on manifest rules
                  $isCritical = Test-IsCriticalTest -TestName $testResult.Name -Manifest $manifest
                  if ($isCritical) { "FAIL" } else { "WARN" }
              }
              else { "SKIP" }

    $aggregatedResults.Results += [PSCustomObject]@{
        TestName = $testResult.Name
        Category = $testResult.Categories[0]
        Status = $status
        Duration = $testResult.Duration
        ErrorMessage = $testResult.FailureMessage
    }
}

# Step 5: Calculate ReadyForUse
$failCount = ($aggregatedResults.Results | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = ($aggregatedResults.Results | Where-Object { $_.Status -eq "WARN" }).Count
$warnThreshold = $manifest.Reporting.warnThreshold

$readyForUse = ($failCount -eq 0) -and ($warnCount -le $warnThreshold)

$aggregatedResults.FailCount = $failCount
$aggregatedResults.WarnCount = $warnCount
$aggregatedResults.WarnThreshold = $warnThreshold
$aggregatedResults.ReadyForUse = $readyForUse

# Step 6: Generate reports
Import-Module "./src/Reporting/JsonFormatter.psm1"
Import-Module "./src/Reporting/MarkdownFormatter.psm1"
Import-Module "./src/Reporting/TableFormatter.psm1"

$jsonReport = $aggregatedResults | ConvertTo-Json -Depth 10
$jsonReport | Out-File -FilePath "artifacts/test-execution/$Environment/$timestamp/orchestration-report.json" -Encoding UTF8

$mdReport = ConvertTo-MarkdownReport -AggregatedResults $aggregatedResults
$mdReport | Out-File -FilePath "artifacts/test-execution/$Environment/$timestamp/orchestration-report.md" -Encoding UTF8

$tableReport = ConvertTo-TableReport -AggregatedResults $aggregatedResults
$tableReport | Out-File -FilePath "artifacts/test-execution/$Environment/$timestamp/orchestration-report.txt" -Encoding UTF8
Write-Host $tableReport

# Step 7: Store environment baseline artifacts
Import-Module "./src/Core/ArtifactStore.psm1"
$baselineDir = New-ArtifactDirectory -BasePath $ArtifactBasePath -Environment $Environment -Category "environment-baseline"
Save-EnvironmentBaselineArtifacts -ArtifactPath $baselineDir.Path -ManifestPath $ManifestPath -AggregatedReport $aggregatedResults

# Step 8: Exit with appropriate code
$exitCode = if ($readyForUse) { 0 } else { 1 }
Write-Host "`nEnvironment $Environment ReadyForUse: $readyForUse (Exit Code: $exitCode)"
exit $exitCode
```

### 4.3 Criticality Rule Evaluation

**ResultAggregator Helper**:
```powershell
function Test-IsCriticalTest {
    param(
        [string]$TestName,
        [PSCustomObject]$Manifest
    )

    # Critical test patterns (per Constitution Section V)
    $criticalPatterns = @(
        '*gMSA*identity*mismatch*',
        '*SQL*unreachable*',
        '*SQL*connection*failed*',
        '*service*not*running*',
        '*component*missing*',
        '*dependency*chain*broken*',
        '*Windows*feature*missing*'
    )

    foreach ($pattern in $criticalPatterns) {
        if ($TestName -like $pattern) {
            return $true
        }
    }

    # Non-critical patterns
    $nonCriticalPatterns = @(
        '*event*log*warning*',
        '*config*file*schema*mismatch*'  # Unless marked critical in manifest
    )

    foreach ($pattern in $nonCriticalPatterns) {
        if ($TestName -like $pattern) {
            return $false
        }
    }

    # Default: assume critical unless proven otherwise
    return $true
}
```

### 4.4 Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| All tests critical | Simpler | Too rigid, false positives block deployments | **Rejected** - WARN status needed for operational flexibility |
| Manual criticality tagging | Fine-grained control | High maintenance, error-prone | **Rejected** - Pattern-based rules sufficient |
| No orchestration layer | Simpler | No ReadyForUse determination, raw Pester output only | **Rejected** - Orchestration needed per Constitution Section V |
| External orchestration tool | Feature-rich | Additional dependency, complexity | **Rejected** - PowerShell orchestration sufficient |

---

## 5. Security Patterns (Connection String Redaction)

### 5.1 Decision

**Redaction Target**: Connection strings only (SQL, LDAP)
**Redaction Patterns**:
- `Server=`, `Data Source=`, `User ID=`, `Password=`, `Uid=`, `Pwd=`, `Integrated Security=`
- Full connection string values containing these patterns

**Redaction Placeholder**: `***REDACTED***`

**Rationale**:
- Connection strings are most common secret in Windows/IIS/.NET environments
- SQL and LDAP connection strings appear in logs, error messages, and test output
- Regex-based pattern matching is efficient and comprehensive
- Simple approach per Session 2025-12-01 clarification (connection strings only, not tokens/certificates)

### 5.2 Redaction Implementation

**SecretsRedaction Module** (`src/Security/SecretsRedaction.psm1`):
```powershell
function Invoke-SecretRedaction {
    param(
        [string]$Content,
        [string]$Placeholder = "***REDACTED***"
    )

    # SQL Connection String Patterns
    $sqlPatterns = @(
        # Full connection strings
        'Server\s*=\s*[^;]+;[^"'']*',
        'Data\s+Source\s*=\s*[^;]+;[^"'']*',

        # Individual connection string components
        '(Server|Data\s+Source)\s*=\s*[^;]+',
        '(User\s+ID|UID|Username)\s*=\s*[^;]+',
        '(Password|PWD|Pwd)\s*=\s*[^;]+',
        'Integrated\s+Security\s*=\s*(True|SSPI)',
        'Initial\s+Catalog\s*=\s*[^;]+',
        'Database\s*=\s*[^;]+'
    )

    # LDAP Connection String Patterns
    $ldapPatterns = @(
        'LDAP://[^"''\s]+',
        'CN=.+?,DC=.+',
        'distinguishedName["\s]*:["\s]*[^"'']+',
        'userPrincipalName["\s]*:["\s]*[^"'']+'
    )

    $redactedContent = $Content

    # Apply SQL redactions
    foreach ($pattern in $sqlPatterns) {
        $redactedContent = $redactedContent -replace $pattern, $Placeholder
    }

    # Apply LDAP redactions
    foreach ($pattern in $ldapPatterns) {
        $redactedContent = $redactedContent -replace $pattern, $Placeholder
    }

    # Additional safety: Redact any remaining suspicious patterns
    # Match quoted strings containing "password", "secret", "token", "key"
    $suspiciousPatterns = @(
        '["''][^"'']*?(password|secret|token|key)[^"'']*?["'']'
    )

    foreach ($pattern in $suspiciousPatterns) {
        $redactedContent = $redactedContent -replace $pattern, "`"$Placeholder`""
    }

    return $redactedContent
}

function Test-ContainsSecret {
    param([string]$Content)

    $secretPatterns = @(
        'password\s*=',
        'pwd\s*=',
        'secret\s*=',
        'token\s*=',
        'key\s*=',
        'Server\s*=',
        'Data\s+Source\s*='
    )

    foreach ($pattern in $secretPatterns) {
        if ($Content -match $pattern) {
            return $true
        }
    }

    return $false
}
```

### 5.3 Redaction Integration

**Apply redaction in orchestration script before artifact storage**:
```powershell
# Before saving reports
Import-Module "./src/Security/SecretsRedaction.psm1"

$jsonReport = $aggregatedResults | ConvertTo-Json -Depth 10
$redactedJsonReport = Invoke-SecretRedaction -Content $jsonReport

# Verify no secrets remain (constitutional requirement per Section VI)
if (Test-ContainsSecret -Content $redactedJsonReport) {
    Write-Error "Constitutional violation: Secrets detected in report after redaction!"
    exit 1
}

$redactedJsonReport | Out-File -FilePath "artifacts/test-execution/$Environment/$timestamp/orchestration-report.json" -Encoding UTF8
```

**Apply redaction in Pester test output**:
```powershell
# In SQL.Tests.ps1
It "SQL connection to <host>/<database> should succeed" -ForEach $sqlServers {
    try {
        $result = Test-SqlConnectionWithRetry -ServerInstance $host -Database $database
        $result.Success | Should -BeTrue
    } catch {
        # Redact exception message before assertion
        $redactedMessage = Invoke-SecretRedaction -Content $_.Exception.Message
        throw "SQL connection failed: $redactedMessage"
    }
}
```

### 5.4 Regex Pattern Testing

**Unit tests for redaction patterns** (stored in `tests/unit/SecretsRedaction.Tests.ps1` for verification only, not part of product):
```powershell
Describe "SecretsRedaction Module" {
    BeforeAll {
        Import-Module "./src/Security/SecretsRedaction.psm1"
    }

    It "Should redact SQL Server connection string" {
        $input = "Server=sql01.contoso.com;Database=RadarLive;User ID=sa;Password=P@ssw0rd"
        $output = Invoke-SecretRedaction -Content $input
        $output | Should -Be "***REDACTED***"
    }

    It "Should redact LDAP connection string" {
        $input = "LDAP://dc01.contoso.com/CN=Users,DC=contoso,DC=com"
        $output = Invoke-SecretRedaction -Content $input
        $output | Should -Be "***REDACTED***"
    }

    It "Should redact Integrated Security connection string" {
        $input = "Data Source=sql01;Initial Catalog=RadarLive;Integrated Security=SSPI"
        $output = Invoke-SecretRedaction -Content $input
        $output | Should -Be "***REDACTED***"
    }

    It "Should not redact non-secret content" {
        $input = "Component health check passed in 1.5 seconds"
        $output = Invoke-SecretRedaction -Content $input
        $output | Should -Be $input
    }
}
```

### 5.5 Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| Comprehensive pattern list (passwords, tokens, certificates) | More thorough | Over-complicated, maintenance burden | **Rejected** - Connection strings only per Session 2025-12-01 |
| OWASP secrets detection rules | Industry-standard, thorough | Complex, many false positives | **Rejected** - Too complex for current scope |
| Configurable patterns in manifest | Flexible | Requires security expertise from operators | **Rejected** - Fixed patterns sufficient |
| No redaction | Simplest | Constitutional violation (Section III: No Secrets Logged) | **Rejected** - Redaction required |

---

## 6. Implementation Readiness Checklist

### 6.1 Technical Decisions Complete

- [x] Manifest schema design (JSON with strict validation)
- [x] Pester integration pattern (NUnit3 XML + PassThru)
- [x] Retry logic strategy (2 retries, exponential backoff)
- [x] Artifact storage mechanism (local file system with structured directories)
- [x] Orchestration algorithm (result aggregation, ReadyForUse calculation)
- [x] Security patterns (connection string redaction)

### 6.2 Constitutional Compliance

- [x] **Section III**: Tests are the Product - Pester tests implement all validations
- [x] **Section III**: DRY - Modules eliminate duplication
- [x] **Section III**: Declarative - JSON manifests define desired state
- [x] **Section III**: Deterministic & Idempotent - Tests produce same results, no state changes
- [x] **Section III**: No Secrets Logged - Connection string redaction implemented
- [x] **Section IV**: PowerShell 7.5+ - Script requires version 7.5
- [x] **Section IV**: Pester 5.0+ - Pester configuration uses 5.0+ features
- [x] **Section V**: Test Suite Success vs Environment Readiness - Clear separation maintained
- [x] **Section VII**: Drift Policy - Stateless test re-runs, no historical comparison
- [x] **Section VIII**: Artifact Storage - ISO 8601 timestamps, environment tagging
- [x] **Section IX**: Graceful Degradation - Tests continue on failure (Pester natural behavior)
- [x] **Section IX**: Read-Only Operations - No state changes (artifact storage excepted)
- [x] **Section IX**: Timeout Enforcement - Health endpoints <2s, port checks 5s
- [x] **Section X**: Thresholds - All defaults defined (health 2s, port 5s, runtime 300s, WARN 3)

### 6.3 Specification Alignment (Session 2025-12-01 Clarifications)

- [x] Health endpoints: Both HTTP and HTTPS with optional certificate validation
- [x] Pester output format: NUnit3 XML
- [x] Retry strategy: 2 retries with exponential backoff (1s, 2s)
- [x] Artifact storage: Local file system with structured directories
- [x] Secret redaction: Connection strings only (SQL, LDAP)

### 6.4 Phase 0 Completion Criteria

- [x] All architectural unknowns resolved
- [x] All technology choices documented with rationale
- [x] All alternatives evaluated
- [x] All implementation patterns defined with code examples
- [x] Research document (`research.md`) generated
- [x] Ready for Phase 1 (Design & Contracts)

---

## 7. Next Steps

### Phase 1: Design & Contracts
1. **Generate data-model.md**: Extract entities from spec.md (Component, IIS, SQL, Network, etc.) with relationships and state transitions
2. **Generate API contracts**: Create OpenAPI/JSON schema for manifest format (formalize Section 1.2 schema)
3. **Generate quickstart.md**: Step-by-step guide for operators (install Pester, create manifest, run validation, interpret results)
4. **Update agent context**: Run `.specify/scripts/powershell/update-agent-context.ps1 -AgentType copilot` to add new technology references

### Phase 2+: Implementation
1. **T001-T006**: Project structure setup (directories, .editorconfig, PSScriptAnalyzer settings)
2. **T100-T115**: Core modules (ManifestValidator, ResultAggregator, SecretsRedaction, etc.)
3. **T201-T215**: Pester test files (IIS.Tests.ps1, SQL.Tests.ps1, Health.Tests.ps1, etc.) + orchestration script
4. **T301-T304**: Artifact storage modules
5. **T400-T402**: Post-change validation and scheduling
6. **T500-T502**: WARN acknowledgment tracking
7. **T600-T702**: Documentation, CI, consistency checks

---

## Document Metadata

**Version**: 1.0
**Last Updated**: 2025-12-01
**Authors**: Radar Live Post-Install Skim Team
**Status**: Complete
**Next Review**: After Phase 1 completion
