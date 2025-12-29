# Quickstart Guide: Radar Live Post-Install Skim

**Target Audience**: Operations teams validating Radar Live environment readiness
**Last Updated**: 2025-12-01
**Version**: 1.0.0

---

## Overview

The Radar Live Post-Install Skim is a **stateless validation tool** that checks if your environment meets the desired state defined in a manifest file. It runs Pester-based tests and reports whether your environment is **ReadyForUse** (ready for production traffic).

**Key Concepts**:
- **Manifest**: JSON file describing desired state (services, health endpoints, SQL connections, etc.)
- **Pester Tests**: PowerShell-based validation checks executed against your environment
- **ReadyForUse**: Boolean determination (true = ready, false = not ready) based on test results
- **Stateless**: No historical comparison, each run validates current state independently

---

## Prerequisites

### Required Software

1. **PowerShell 7.5 or later**
   ```powershell
   # Check your PowerShell version
   $PSVersionTable.PSVersion
   # Expected output: Major=7, Minor=5 (or higher)

   # If < 7.5, download and install from:
   # https://github.com/PowerShell/PowerShell/releases

   # Windows Installation (MSI):
   # 1. Download PowerShell-7.5.x-win-x64.msi
   # 2. Run installer with default options
   # 3. Restart terminal and verify: pwsh --version
   ```

2. **Pester 5.0 or later**
   ```powershell
   # Check Pester version
   Get-Module -Name Pester -ListAvailable
   # Expected: Version 5.x.x

   # If Pester not installed or < 5.0:
   Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck

   # If Pester 4.x is pre-installed (common on Windows Server):
   # Uninstall old version first (run as Administrator):
   Get-Module Pester -ListAvailable | Where-Object {$_.Version -lt '5.0'} | Uninstall-Module -Force

   # Then install Pester 5.x:
   Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck

   # Verify installation:
   Import-Module Pester
   (Get-Module Pester).Version  # Should show 5.x.x
   ```

3. **Optional: Visual Studio Code** (for manifest editing)
   - Download from: https://code.visualstudio.com/
   - Install PowerShell extension for syntax highlighting
   - Install JSON extension for schema validation

### Required Permissions

- **Read-only** access to:
  - Windows Services
  - IIS configuration (if validating IIS components)
  - Event Logs
  - File system paths (component installation directories)
  - Network connectivity (DNS, ports)
- **SQL Server**: Read-only connection (if validating SQL connectivity)
- **No administrative rights required** for core validation (unless validating admin-only resources)

---

## Installation

### Option 1: Clone Repository (Recommended for Development)

```powershell
# Clone the repository
git clone <repository-url> C:\Tools\RadarPostInstallSkim
cd C:\Tools\RadarPostInstallSkim

# Unblock PowerShell scripts (Windows security)
Get-ChildItem -Path . -Recurse -Filter *.ps1 | Unblock-File
Get-ChildItem -Path . -Recurse -Filter *.psm1 | Unblock-File
Get-ChildItem -Path . -Recurse -Filter *.psd1 | Unblock-File

# Verify installation
Test-Path .\Invoke-PostInstallSkim.ps1  # Should return True
Test-Path .\modules  # Should return True
Test-Path .\tests  # Should return True

# Verify module imports (test module loading)
Import-Module .\modules\ManifestValidation\ManifestValidation.psd1 -Force
Get-Command -Module ManifestValidation  # Should list module functions
```

### Option 2: Download Release Package

1. Download latest release from `<release-url>`
2. Extract to `C:\Tools\RadarPostInstallSkim`
3. **CRITICAL: Unblock all files** (Windows marks downloaded files as unsafe):
   ```powershell
   # Unblock ALL files recursively (required for modules to load)
   Get-ChildItem -Path C:\Tools\RadarPostInstallSkim -Recurse | Unblock-File

   # Verify unblocked (no output = success):
   Get-ChildItem -Path C:\Tools\RadarPostInstallSkim -Recurse -File |
       Get-Item -Stream Zone.Identifier -ErrorAction SilentlyContinue
   ```

### Option 3: Direct Server Deployment (No Git)

```powershell
# Copy files to target server via network share or USB
Copy-Item -Path \\fileserver\Deployments\RadarPostInstallSkim `
          -Destination C:\Tools\RadarPostInstallSkim -Recurse

# Unblock files
cd C:\Tools\RadarPostInstallSkim
Get-ChildItem -Recurse | Unblock-File

# Set execution policy (if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

### Verification Steps

```powershell
# Test orchestrator loads without errors
cd C:\Tools\RadarPostInstallSkim
.\Invoke-PostInstallSkim.ps1 -?
# Should display help message with parameters

# Test module imports
Import-Module .\modules\ManifestValidation\ManifestValidation.psd1
Import-Module .\modules\ResultAggregation\ResultAggregation.psd1
Get-Command -Module ManifestValidation, ResultAggregation
# Should list available functions

# Test Pester test discovery
Get-ChildItem .\tests\*.Tests.ps1
# Should list all test files (Component.Tests.ps1, IIS.Tests.ps1, SQL.Tests.ps1, etc.)
```

---

## Configuration

### Step 1: Create Your Manifest

Create a JSON manifest file describing your desired environment state. Use the schema at `specs/main/contracts/manifest-schema.json` for validation.

**Minimal Example** (`desired-state-manifest.dev.json`):

```json
{
  "EnvironmentName": "DEV",
  "GMSInUse": "DOMAIN\\gmsa-radar-dev$",
  "Components": [
    {
      "displayName": "Management Server",
      "expectedServiceName": "RadarLive.ManagementServer",
      "expectedInstallPath": "C:\\Program Files\\Radar Live\\ManagementServer",
      "expectedHealthUrl": "https://localhost:5001/health",
      "certificateValidation": false,
      "expectedAppPool": "RadarLiveAppPool"
    }
  ],
  "IIS": {
    "requiredWindowsFeatures": ["Web-Server", "Web-Asp-Net45"],
    "expectedSites": ["Default Web Site"],
    "expectedAppPools": [
      {"name": "RadarLiveAppPool", "identity": "DOMAIN\\gmsa-radar-dev$"}
    ]
  },
  "SQL": {
    "sqlServers": [
      {"host": "sql-dev.domain.com", "databases": ["RadarLive_DEV"]}
    ],
    "connectionTest": true
  },
  "Network": {
    "dnsResolution": ["sql-dev.domain.com", "api.external.com"],
    "portOpen": [
      {"host": "sql-dev.domain.com", "port": 1433}
    ]
  },
  "HealthAndTiming": {
    "healthTimeoutSeconds": 2,
    "maxTotalSkimDurationSeconds": 300
  },
  "Reporting": {
    "outputFormat": ["JSON", "Markdown"],
    "storeHistory": true,
    "historyStoragePath": "C:\\RadarLive\\ValidationArtifacts"
  },
  "SecretsAndSecurity": {
    "noSecretsInLogs": true
  }
}
```

### Step 2: Validate Your Manifest

```powershell
# Validate manifest against schema
Test-Json -Json (Get-Content .\desired-state-manifest.dev.json -Raw) `
          -SchemaFile .\specs\main\contracts\manifest-schema.json
# Should return True if valid

# Common validation errors:
# 1. JSON syntax error (missing comma, unclosed bracket)
# 2. Required field missing (EnvironmentName, GMSInUse, Components)
# 3. Type mismatch (string instead of integer for healthTimeoutSeconds)
# 4. Invalid enum value (EnvironmentName not DEV/UAT/PRD)

# Test manifest loads correctly
$manifest = Get-Content .\desired-state-manifest.dev.json -Raw | ConvertFrom-Json
$manifest.EnvironmentName  # Should display: DEV
$manifest.Components.Count  # Should display number of components

# Validate gMSA format
if ($manifest.GMSInUse -notmatch '^.+\\.+\$$') {
    Write-Warning "GMSInUse format invalid. Expected: DOMAIN\\account\$, Got: $($manifest.GMSInUse)"
}

# Check for circular dependencies
Import-Module .\modules\ManifestValidation\ManifestValidation.psd1
$result = Test-DependencyDAG -Manifest $manifest
if (-not $result.IsValid) {
    Write-Error "Circular dependency detected: $($result.CyclePath -join ' -> ')"
}
```

### Step 3: Environment-Specific Manifests

Create one manifest per environment:
- `desired-state-manifest.dev.json` (DEV environment)
- `desired-state-manifest.uat.json` (UAT environment)
- `desired-state-manifest.prd.json` (PRD environment)

**Key differences**:
- `certificateValidation`: `false` for DEV/UAT (self-signed certs), `true` for PRD
- Component counts: Fewer in DEV, more in PRD (distributed architecture)
- SQL hosts: `sql-dev`, `sql-uat`, `sql-prd`
- Timeout thresholds: More lenient in DEV, stricter in PRD

---

## Execution

### Basic Usage

```powershell
# Run validation for DEV environment
.\Invoke-PostInstallSkim.ps1 -ManifestPath .\desired-state-manifest.dev.json

# Run validation for UAT environment
.\Invoke-PostInstallSkim.ps1 -ManifestPath .\desired-state-manifest.uat.json
```

### Common Parameters

```powershell
# Basic execution (uses manifest settings for artifact storage)
.\Invoke-PostInstallSkim.ps1 -ManifestPath .\desired-state-manifest.dev.json

# Return results object for programmatic access
$results = .\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.dev.json `
    -PassThru

Write-Host "ReadyForUse: $($results.ReadyForUse)"
Write-Host "Pass: $($results.PassCount), Fail: $($results.FailCount), Warn: $($results.WarnCount)"

# Verbose output for debugging
.\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.dev.json `
    -Verbose

# Run specific test file only (debugging)
Invoke-Pester -Path .\tests\Component.Tests.ps1 `
    -Output Detailed

# Dry-run: Validate manifest without executing tests
Import-Module .\modules\ManifestValidation\ManifestValidation.psd1
$manifest = Get-Content .\desired-state-manifest.dev.json -Raw | ConvertFrom-Json
Test-ManifestSchema -Manifest $manifest -SchemaPath .\specs\main\contracts\manifest-schema.json
```

### Advanced Execution Scenarios

```powershell
# Scenario 1: Pre-deployment validation (run on source environment)
$preDeployResults = .\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.uat.json `
    -PassThru

if (-not $preDeployResults.ReadyForUse) {
    Write-Error "Pre-deployment validation failed. Blocking deployment."
    exit 1
}

# Scenario 2: Post-deployment validation with comparison
# (Run after deployment to target environment)
$postDeployResults = .\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.uat.json `
    -PassThru

if ($postDeployResults.ReadyForUse) {
    Write-Host "Deployment successful. Environment ready." -ForegroundColor Green
} else {
    Write-Host "Deployment validation failed. Review errors:" -ForegroundColor Red
    $postDeployResults.TestResults | Where-Object {$_.Result -eq 'Failed'} |
        Format-Table Name, FailureMessage -AutoSize
}

# Scenario 3: Scheduled drift detection
# (Runs daily via Task Scheduler or CI/CD)
$driftResults = .\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.prd.json `
    -PassThru

if (-not $driftResults.ReadyForUse) {
    # Send alert (email, Teams, PagerDuty)
    $alertMessage = @"
Drift detected in PRD environment!
ReadyForUse: $($driftResults.ReadyForUse)
Failed Tests: $($driftResults.FailCount)
Warnings: $($driftResults.WarnCount)

Artifact Path: $($driftResults.ArtifactPath)
"@
    Send-MailMessage -To ops-team@domain.com `
        -Subject "[ALERT] PRD Drift Detected" `
        -Body $alertMessage `
        -SmtpServer smtp.domain.com
}
```

### Expected Output

**Console Output** (real-time):
```
[2025-12-01 10:30:00] Starting Post-Install Skim for DEV environment
[2025-12-01 10:30:01] Validating manifest schema... OK
[2025-12-01 10:30:02] Executing Pester tests...
  Describing Component: Management Server
    [+] Windows service 'RadarLive.ManagementServer' is running 123ms
    [+] Health endpoint returns 200 OK 456ms
    [+] Installation path exists 45ms
  Describing IIS Configuration
    [+] Windows feature 'Web-Server' is installed 89ms
    [+] AppPool 'RadarLiveAppPool' uses gMSA identity 67ms
  Describing SQL Connectivity
    [+] SQL host 'sql-dev.domain.com' is reachable 234ms
    [+] Database 'RadarLive_DEV' is accessible 567ms
[2025-12-01 10:30:15] Tests complete: 0 failed, 0 warnings
[2025-12-01 10:30:15] ReadyForUse: TRUE
[2025-12-01 10:30:16] Artifacts stored: C:\RadarLive\ValidationArtifacts\test-execution\DEV\20251201_103016
```

**Artifact Files** (stored in `historyStoragePath`):
```
C:\RadarLive\ValidationArtifacts\
├── test-execution\
│   └── DEV\
│       └── 20251201_103016\
│           ├── pester-results.xml       # NUnit3 XML output
│           ├── orchestration-report.json # Aggregated results
│           └── orchestration-report.md   # Human-readable report
└── environment-baseline\
    └── DEV\
        └── 20251201_103016\
            └── manifest-snapshot.json    # Manifest used for this run
```

---

## Interpreting Results

### ReadyForUse Determination

The orchestrator calculates **ReadyForUse** using this formula:

```
ReadyForUse = (FailCount == 0) AND (WarnCount <= WarnThreshold)
```

**Default WarnThreshold**: 3 warnings

**Exit Codes**:
- `0`: ReadyForUse = `true` (environment is ready)
- `1`: ReadyForUse = `false` (environment is NOT ready)

### Test Result Classifications

#### ✅ PASS (Non-Critical Test Passed)
- **Example**: Event log contains only informational messages
- **Action**: None required
- **Impact on ReadyForUse**: None

#### ❌ FAIL (Critical Test Failed)
- **Example**: SQL Server unreachable, Windows service not running
- **Action**: **BLOCK deployment**, investigate failure
- **Impact on ReadyForUse**: Sets `ReadyForUse = false`

#### ⚠️ WARN (Non-Critical Test Failed)
- **Example**: Event log contains 2 warnings in last 24 hours
- **Action**: Review warnings, acknowledge if expected
- **Impact on ReadyForUse**: Sets `ReadyForUse = false` if `WarnCount > WarnThreshold`

### Criticality Patterns

**Automatically classified as CRITICAL (causes FAIL)**:
- `*gMSA*identity*` - gMSA misconfiguration (AppPool/SQL login mismatch)
- `*SQL*unreachable*` - SQL connectivity failure (DNS, port, connection)
- `*service*not*running*` - Windows service down
- `*component*missing*` - Installation path not found
- `*dependency*chain*` - Dependency resolution failure
- `*Windows*feature*missing*` - Required IIS feature absent

**Automatically classified as NON-CRITICAL (causes WARN)**:
- `*event*log*warning*` - Event log warnings (informational)
- `*config*file*schema*` - Config file schema validation (non-blocking)

**Real-World Classification Examples**:

| Test Name | Result | Criticality | Impact |
|-----------|--------|-------------|--------|
| Component 'RadarCalc' service running | Failed | CRITICAL | ReadyForUse=false |
| Component 'RadarCalc' health endpoint | Failed | CRITICAL | ReadyForUse=false |
| AppPool 'RadarPool' gMSA identity | Failed | CRITICAL | ReadyForUse=false |
| SQL connection to 'RadarDB' | Failed | CRITICAL | ReadyForUse=false |
| Event log warnings (3 found) | Failed | NON-CRITICAL | WARN (threshold=3) |
| Config schema validation | Failed | NON-CRITICAL | WARN |

**Decision Tree: Understanding Your Results**

```
ReadyForUse = false?
├─ FailCount > 0?
│  ├─ YES → Critical test failed
│  │        Action: Review FAIL results, fix issue, re-run
│  │        Example: SQL unreachable, service stopped, gMSA mismatch
│  └─ NO → Check WarnCount
│           WarnCount > threshold (default 3)?
│           ├─ YES → Too many warnings
│           │        Action: Review WARN results, fix or acknowledge
│           │        Example: 5 event log warnings, 2 config issues
│           └─ NO → (This shouldn't happen, check orchestrator logs)
└─ ReadyForUse = true
   Action: Environment validated successfully
   Next: Proceed with deployment or operations
```

### Reading the Orchestration Report

**JSON Report** (`orchestration-report.json`):
```json
{
  "timestamp": "2025-12-01T10:30:16Z",
  "environmentName": "DEV",
  "readyForUse": true,
  "exitCode": 0,
  "summary": {
    "totalTests": 12,
    "passedTests": 12,
    "failedTests": 0,
    "skippedTests": 0,
    "failCount": 0,
    "warnCount": 0,
    "passCount": 12
  },
  "componentHealth": [
    {
      "displayName": "Management Server",
      "status": "Healthy",
      "tests": [
        {"name": "Service Running", "result": "PASS"},
        {"name": "Health Endpoint", "result": "PASS"}
      ]
    }
  ]
}
```

**Markdown Report** (`orchestration-report.md`):
```markdown
# Post-Install Skim Report: DEV

**Timestamp**: 2025-12-01 10:30:16
**ReadyForUse**: ✅ TRUE
**Exit Code**: 0

## Summary
- Total Tests: 12
- Passed: 12
- Failed: 0
- Warnings: 0

## Component Health
### Management Server: ✅ Healthy
- Service Running: ✅ PASS
- Health Endpoint: ✅ PASS
```

---

## Troubleshooting

### Common Issues

#### Issue: "Manifest validation failed"
**Cause**: JSON syntax error or schema violation
**Solution**:
```powershell
# Validate JSON syntax
Get-Content .\desired-state-manifest.dev.json | ConvertFrom-Json

# Check against schema
Test-Json -Json (Get-Content .\desired-state-manifest.dev.json -Raw) `
  -SchemaFile .\specs\main\contracts\manifest-schema.json
```

#### Issue: "Health endpoint timeout"
**Cause**: Service slow to respond, certificate validation failure, or endpoint unreachable

**Troubleshooting Tree**:
```
Health endpoint timeout?
├─ Is service running?
│  ├─ NO → Start service: Start-Service -Name RadarLive.ManagementServer
│  └─ YES → Continue
├─ Test endpoint manually
│  Command: Invoke-WebRequest -Uri https://localhost:5001/health
│  ├─ SUCCESS → Increase healthTimeoutSeconds in manifest (service is slow but functional)
│  ├─ CERTIFICATE ERROR → Set certificateValidation: false in manifest (DEV/UAT only)
│  │                       For PRD: Fix certificate (renew, install CA, check expiration)
│  └─ CONNECTION REFUSED → Check port binding
│                           Command: netstat -ano | findstr :5001
│                           Expected: LISTENING on 0.0.0.0:5001 or 127.0.0.1:5001
└─ Check application logs
   Location: Event Viewer → Application logs
   Filter: Source = RadarLive.ManagementServer
   Look for: Startup errors, initialization failures, database connection issues
```

**Common Solutions**:
```powershell
# Solution 1: Service not running
Get-Service -Name RadarLive.ManagementServer | Start-Service
Start-Sleep -Seconds 5  # Wait for startup
.\Invoke-PostInstallSkim.ps1 -ManifestPath .\desired-state-manifest.dev.json

# Solution 2: Certificate validation (DEV/UAT self-signed certs)
# Edit manifest: Set "certificateValidation": false for the component
# Then re-run validation

# Solution 3: Increase timeout (legitimate slow startup)
# Edit manifest: Set "healthTimeoutSeconds": 5 (increase from default 2)

# Solution 4: Test endpoint directly
$response = Invoke-WebRequest -Uri https://localhost:5001/health `
    -SkipCertificateCheck -TimeoutSec 10
$response.StatusCode  # Should be 200 or 204
```

#### Issue: "SQL connection failed"
**Cause**: Network, credentials, SQL Server availability, or gMSA permissions

**Troubleshooting Tree** (4-step validation):
```
SQL connection failed?
├─ Step 1: DNS Resolution
│  Command: Resolve-DnsName sql-dev.domain.com
│  ├─ FAILED → Check DNS server, verify hostname spelling, check hosts file
│  └─ SUCCESS → Continue to Step 2
├─ Step 2: Port Connectivity
│  Command: Test-NetConnection -ComputerName sql-dev.domain.com -Port 1433
│  ├─ FAILED → Check firewall rules (server + network), verify SQL Server TCP/IP enabled
│  └─ SUCCESS → Continue to Step 3
├─ Step 3: SQL Server Service
│  Command: Get-Service -Name MSSQLSERVER -ComputerName sql-dev
│  ├─ STOPPED → Start SQL Server service on target server
│  └─ RUNNING → Continue to Step 4
└─ Step 4: gMSA Permissions
   Test: Connect using gMSA credentials
   ├─ LOGIN FAILED → Grant gMSA login rights on SQL Server
   │                  SQL: CREATE LOGIN [DOMAIN\gMSA$] FROM WINDOWS;
   └─ DATABASE ACCESS DENIED → Grant database permissions
                                SQL: USE RadarLive_DEV; CREATE USER [DOMAIN\gMSA$] FOR LOGIN [DOMAIN\gMSA$];
                                     ALTER ROLE db_datareader ADD MEMBER [DOMAIN\gMSA$];
```

**Detailed Solutions**:
```powershell
# Solution 1: DNS Resolution Failed
Resolve-DnsName sql-dev.domain.com
# If fails:
# - Check DNS server: ipconfig /all | findstr "DNS"
# - Test alternate DNS: nslookup sql-dev.domain.com 8.8.8.8
# - Verify hostname spelling in manifest
# - Check hosts file: C:\Windows\System32\drivers\etc\hosts

# Solution 2: Port Connectivity Failed
Test-NetConnection -ComputerName sql-dev.domain.com -Port 1433 -InformationLevel Detailed
# If TcpTestSucceeded = False:
# Check Windows Firewall:
Get-NetFirewallRule -DisplayName "*SQL*" | Format-Table Name, Enabled, Direction
# Check SQL Server TCP/IP enabled:
# SQL Configuration Manager → SQL Server Network Configuration → Protocols → TCP/IP = Enabled

# Solution 3: gMSA Login Rights
# Connect to SQL Server as admin, run:
CREATE LOGIN [DOMAIN\gmsa-radar-dev$] FROM WINDOWS;
GRANT CONNECT SQL TO [DOMAIN\gmsa-radar-dev$];

# Solution 4: Database Permissions
USE RadarLive_DEV;
CREATE USER [DOMAIN\gmsa-radar-dev$] FOR LOGIN [DOMAIN\gmsa-radar-dev$];
ALTER ROLE db_datareader ADD MEMBER [DOMAIN\gmsa-radar-dev$];
ALTER ROLE db_datawriter ADD MEMBER [DOMAIN\gmsa-radar-dev$];  -- If write access needed

# Solution 5: Test connection manually (from validation server)
$connectionString = "Server=sql-dev.domain.com;Database=RadarLive_DEV;Integrated Security=True;"
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
try {
    $connection.Open()
    Write-Host "Connection successful!" -ForegroundColor Green
    $connection.Close()
} catch {
    Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
}
```

#### Issue: "ReadyForUse false due to warnings"
**Cause**: `WarnCount > WarnThreshold` (default 3)

**Decision Tree**:
```
WarnCount > WarnThreshold?
├─ Are warnings expected/acceptable?
│  ├─ YES → Increase warnThreshold in manifest
│  │        Example: Event log warnings during deployment window
│  │        Action: Set "warnThreshold": 5 in manifest
│  └─ NO → Fix underlying issues
│           Examples:
│           - Config file schema validation → Fix JSON/XML syntax
│           - Event log errors → Investigate application errors
└─ Review warning details
   Command: See below
```

**Solution**:
```powershell
# Step 1: Review warning details
$artifactPath = "C:\RadarLive\ValidationArtifacts\test-execution\DEV\20251201_103016"
$report = Get-Content "$artifactPath\orchestration-report.json" | ConvertFrom-Json

# Show all WARN results
$report.TestResults | Where-Object { $_.Criticality -eq 'WARN' } |
    Format-Table Name, FailureMessage -AutoSize

# Step 2: Decide action based on warning content
# Option A: Increase threshold (warnings are acceptable)
# Edit manifest:
"Reporting": {
  "warnThreshold": 5  // Increase from default 3
}

# Option B: Fix issues (warnings indicate problems)
# Example: Config file schema validation
# - Open config file: C:\Program Files\Radar Live\ManagementServer\appsettings.json
# - Validate against schema
# - Fix missing fields or type mismatches
# - Re-run validation

# Option C: Suppress specific warnings (known false positives)
# Note: Not currently supported - feature request for future version
```

#### Issue: "Manifest validation failed: Circular dependency detected"
**Cause**: Component dependency chain creates a loop (A depends on B depends on A)

**Solution**:
```powershell
# Visualize dependency graph
Import-Module .\modules\ManifestValidation\ManifestValidation.psd1
$manifest = Get-Content .\desired-state-manifest.dev.json -Raw | ConvertFrom-Json
$result = Test-DependencyDAG -Manifest $manifest

if (-not $result.IsValid) {
    Write-Host "Circular dependency detected:"
    Write-Host ($result.CyclePath -join ' -> ')
    # Example output: SettingsManager -> ScheduleManager -> SettingsManager
}

# Fix: Remove circular dependency from manifest
# Edit desired-state-manifest.dev.json:
# Component 'ScheduleManager' should NOT list 'SettingsManager' in runtimeDependencies
# if 'SettingsManager' already lists 'ScheduleManager'

# Valid dependency order (topological):
# SettingsManager (no dependencies) → ScheduleManager (depends on SettingsManager) → CalcServer (depends on ScheduleManager)
```

#### Issue: "Module import failed: Cannot find path"
**Cause**: PowerShell files blocked by Windows security or incorrect module path

**Solution**:
```powershell
# Check if files are blocked
Get-ChildItem -Path .\modules -Recurse -File | Get-Item -Stream Zone.Identifier -ErrorAction SilentlyContinue
# If any output: Files are blocked

# Unblock all files
Get-ChildItem -Path . -Recurse | Unblock-File

# Verify module loads
Import-Module .\modules\ManifestValidation\ManifestValidation.psd1 -Force -Verbose
Get-Command -Module ManifestValidation

# Check PowerShell execution policy
Get-ExecutionPolicy -List
# If Restricted: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Artifact Management

### Artifact Structure

```
{historyStoragePath}\
├── test-execution\       # Test run results
│   └── {EnvironmentName}\
│       └── {yyyyMMdd_HHmmss}\
│           ├── pester-results.xml
│           ├── orchestration-report.json
│           └── orchestration-report.md
└── environment-baseline\ # Environment snapshots
    └── {EnvironmentName}\
        └── {yyyyMMdd_HHmmss}\
            └── manifest-snapshot.json
```

### Artifact Retention

Artifact retention and cleanup policies are organizational decisions outside the framework's scope. Organizations should implement their own retention policies based on compliance requirements, storage capacity, and auditing needs.

**Decision Tree: Choosing Your Retention Policy**

```
Are you subject to compliance frameworks (SOC2, HIPAA, GDPR, PCI-DSS)?
├─ YES → Implement compliance-driven retention (see Compliance Scenarios below)
└─ NO  → Are you constrained by storage capacity?
    ├─ YES → Implement capacity-driven retention (30-60 days rolling window)
    └─ NO  → Implement operational retention (90+ days for incident investigation)
```

**Compliance Scenarios**

1. **SOC2 Type II** (Change Management Controls):
   - **Requirement**: Audit trail of deployment validations for 12+ months
   - **Retention**: 90-day minimum (active), 365-day archival (cold storage)
   - **Rationale**: Auditors review quarterly reports showing pre-deployment validation

2. **HIPAA** (Electronic Health Records):
   - **Requirement**: System configuration audit trails for 6+ years
   - **Retention**: 2,190+ days (6 years)
   - **Rationale**: HHS audits require historical evidence of environment security

3. **GDPR** (Data Processing Security):
   - **Requirement**: Technical measures documentation for data breach investigations
   - **Retention**: 90-day minimum (incident investigation window)
   - **Rationale**: Article 32 requires demonstrable security validation

4. **No Compliance Framework** (Operational Only):
   - **Requirement**: Root cause analysis for production incidents
   - **Retention**: 30-90 days (typical incident investigation window)
   - **Rationale**: Compare current vs historical state during outage postmortems

**Implementation Patterns**

**Pattern 1: PowerShell Scheduled Task (Simple File Cleanup)**
```powershell
# Remove-ExpiredArtifacts.ps1
param(
    [int]$RetentionDays = 90,
    [string]$HistoryPath = "C:\ProgramData\RadarSkim\History"
)

$cutoffDate = (Get-Date).AddDays(-$RetentionDays)
$subdirs = @("test-execution", "environment-baseline")

foreach ($subdir in $subdirs) {
    $path = Join-Path $HistoryPath $subdir
    Get-ChildItem -Path $path -Directory -Recurse |
        Where-Object { $_.CreationTime -lt $cutoffDate } |
        Remove-Item -Recurse -Force -WhatIf  # Remove -WhatIf when ready
}
```

**Pattern 2: File System Quotas (Windows Server)**
```powershell
# Set 10GB quota on history storage path
fsutil quota modify C:\ /user:DOMAIN\RadarSkimService /limit:10GB /threshold:9GB
```

**Pattern 3: Centralized Log Aggregation (Splunk/ELK)**
```powershell
# Forward artifacts to SIEM, then delete local copies after 7 days
Get-ChildItem "$historyPath\test-execution" -Recurse -Filter "*.json" |
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } |
    ForEach-Object {
        # Send to Splunk HEC or Elasticsearch
        Invoke-RestMethod -Uri "https://splunk.example.com:8088/services/collector" `
            -Method Post -Body (Get-Content $_.FullName -Raw)
        # Delete local copy after successful upload
        Remove-Item $_.FullName -Force
    }
```

**Pattern 4: Azure Blob Storage Archival (Long-Term Retention)**
```powershell
# Archive artifacts older than 90 days to Azure Blob (cool tier)
$storageAccount = "radaraudit"
$storageKey = Get-Secret -Name "AzureStorageKey"

Get-ChildItem "$historyPath\test-execution" -Recurse |
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-90) } |
    ForEach-Object {
        # Upload to Azure Blob cool tier
        Set-AzStorageBlobContent -File $_.FullName `
            -Container "radar-artifacts" `
            -Context (New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageKey) `
            -BlobType Block -Tier Cool
        # Delete local copy after upload
        Remove-Item $_.FullName -Force
    }
```

**Monitoring Retention Health**

```powershell
# Check artifact storage consumption
$historyPath = "C:\ProgramData\RadarSkim\History"
$size = (Get-ChildItem $historyPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
Write-Host "Current artifact storage: $size GB"

# Count artifacts by age bracket
$now = Get-Date
@(7, 30, 90, 365) | ForEach-Object {
    $count = (Get-ChildItem "$historyPath\test-execution" -Recurse -Directory |
        Where-Object { $_.CreationTime -gt $now.AddDays(-$_) }).Count
    Write-Host "Last $_ days: $count validation runs"
}
```

---

## Best Practices

### Development Environment (DEV)
```json
{
  "EnvironmentName": "DEV",
  "certificateValidation": false,  // Self-signed certs OK
  "HealthAndTiming": {
    "healthTimeoutSeconds": 5,      // More lenient timeout (debugging)
    "maxTotalSkimDurationSeconds": 600  // 10 minutes (allow slower responses)
  },
  "Reporting": {
    "warnThreshold": 5,             // Allow more warnings
    "storeHistory": true,           // Store artifacts for troubleshooting
    "historyStoragePath": "C:\\RadarLive\\ValidationArtifacts\\DEV"
  },
  "Components": [
    // Typically fewer components (single-server deployment)
    // May include only Management Server + Calc Service
  ]
}
```

### User Acceptance Testing (UAT)
```json
{
  "EnvironmentName": "UAT",
  "certificateValidation": false,  // May use self-signed certs (internal CA)
  "HealthAndTiming": {
    "healthTimeoutSeconds": 3,      // Moderate timeout
    "maxTotalSkimDurationSeconds": 300  // 5 minutes
  },
  "Reporting": {
    "warnThreshold": 3,             // Moderate warning tolerance
    "storeHistory": true,           // Required for compliance testing
    "historyStoragePath": "C:\\RadarLive\\ValidationArtifacts\\UAT"
  },
  "Components": [
    // Production-like architecture (multi-server)
    // All components present for integration testing
  ]
}
```

### Production (PRD)
```json
{
  "EnvironmentName": "PRD",
  "certificateValidation": true,   // Valid certs required (public CA)
  "HealthAndTiming": {
    "healthTimeoutSeconds": 2,      // Strict timeout (performance requirement)
    "maxTotalSkimDurationSeconds": 300  // 5 minutes max
  },
  "Reporting": {
    "warnThreshold": 1,             // Minimal warning tolerance (zero tolerance)
    "storeHistory": true,           // Required for compliance audits
    "historyStoragePath": "C:\\ProgramData\\RadarSkim\\History\\PRD"
  },
  "Components": [
    // Full production architecture (load-balanced, redundant)
    // All components with strict SLAs
  ]
}
```

### Pre-Deployment Checklist

#### Phase 1: Pre-Deployment Validation (Source Environment)
```powershell
# 1. Run validation in source environment
$preResults = .\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.uat.json `
    -PassThru

# 2. Verify ReadyForUse = true
if (-not $preResults.ReadyForUse) {
    Write-Error "Source environment not ready. Blocking deployment."
    Write-Host "Failures:"
    $preResults.TestResults | Where-Object {$_.Result -eq 'Failed'} |
        Format-Table Name, FailureMessage
    exit 1
}

# 3. Review and acknowledge warnings
$warnings = $preResults.TestResults | Where-Object {$_.Criticality -eq 'WARN'}
if ($warnings) {
    Write-Host "Warnings found ($($warnings.Count)):" -ForegroundColor Yellow
    $warnings | Format-Table Name, FailureMessage

    # Document warnings in deployment notes
    $deploymentNotes = @"
Pre-Deployment Validation: PASS
Timestamp: $($preResults.Timestamp)
Artifact Path: $($preResults.ArtifactPath)
Warnings Acknowledged: $($warnings.Count)
"@
    $deploymentNotes | Out-File -FilePath deployment-notes.txt
}

# 4. Store artifact path for audit trail
Write-Host "Artifact stored: $($preResults.ArtifactPath)"
```

#### Phase 2: Post-Deployment Validation (Target Environment)
```powershell
# Wait for deployment to complete (application installed, services started)
Start-Sleep -Seconds 60

# 5. Run validation in target environment
$postResults = .\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.prd.json `
    -PassThru

# 6. Verify deployment success
if (-not $postResults.ReadyForUse) {
    Write-Error "Post-deployment validation FAILED. Environment NOT ready."
    Write-Host "Failed Tests:"
    $postResults.TestResults | Where-Object {$_.Result -eq 'Failed'} |
        Format-Table Name, FailureMessage

    # Rollback decision
    Write-Host "Recommend rollback to previous version." -ForegroundColor Red
    exit 1
}

# 7. Compare pre/post results (optional)
$comparison = @"
Deployment Validation Comparison
================================
Pre-Deployment (UAT):
  Pass: $($preResults.PassCount)
  Fail: $($preResults.FailCount)
  Warn: $($preResults.WarnCount)

Post-Deployment (PRD):
  Pass: $($postResults.PassCount)
  Fail: $($postResults.FailCount)
  Warn: $($postResults.WarnCount)

Deployment Status: SUCCESS
"@

Write-Host $comparison -ForegroundColor Green
$comparison | Out-File -FilePath deployment-validation-report.txt
```

### Operational Best Practices

#### 1. Scheduled Drift Detection
```powershell
# Create scheduled task (runs daily at 2 AM)
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-File C:\Tools\RadarPostInstallSkim\Invoke-PostInstallSkim.ps1 -ManifestPath C:\Configs\desired-state-manifest.prd.json"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable
Register-ScheduledTask -TaskName "RadarDriftDetection-PRD" `
    -Action $action -Trigger $trigger -Settings $settings `
    -User "DOMAIN\gMSA-Automation$" -Description "Daily PRD validation"
```

#### 2. Incident Response Workflow
```powershell
# During incident investigation
$incidentResults = .\Invoke-PostInstallSkim.ps1 `
    -ManifestPath .\desired-state-manifest.prd.json `
    -PassThru

# Compare with last known good state
$lastGood = Get-ChildItem "C:\ProgramData\RadarSkim\History\PRD\test-execution" |
    Sort-Object CreationTime -Descending |
    Select-Object -Skip 1 -First 1

$lastGoodReport = Get-Content "$($lastGood.FullName)\orchestration-report.json" | ConvertFrom-Json

# Identify what changed
$currentFailures = $incidentResults.TestResults | Where-Object {$_.Result -eq 'Failed'}
$previousFailures = $lastGoodReport.TestResults | Where-Object {$_.Result -eq 'Failed'}

$newFailures = $currentFailures | Where-Object {$_.Name -notin $previousFailures.Name}

if ($newFailures) {
    Write-Host "New failures since last validation:" -ForegroundColor Red
    $newFailures | Format-Table Name, FailureMessage
}
```

#### 3. Compliance Audit Trail
```powershell
# Generate compliance report (last 90 days)
$artifactRoot = "C:\ProgramData\RadarSkim\History\PRD\test-execution"
$artifacts = Get-ChildItem $artifactRoot -Directory |
    Where-Object {$_.CreationTime -gt (Get-Date).AddDays(-90)} |
    Sort-Object CreationTime

$complianceReport = foreach ($artifact in $artifacts) {
    $report = Get-Content "$($artifact.FullName)\orchestration-report.json" | ConvertFrom-Json
    [PSCustomObject]@{
        Timestamp = $report.timestamp
        ReadyForUse = $report.readyForUse
        FailCount = $report.summary.failedTests
        WarnCount = $report.summary.warnCount
        Duration = $report.duration
    }
}

$complianceReport | Format-Table -AutoSize
$complianceReport | Export-Csv -Path "PRD-Compliance-90Day.csv" -NoTypeInformation
```

---

## Integration Examples

### Azure DevOps Pipeline (Deployment Validation)

**Use Case**: Validate environment after deployment, block release on failure

```yaml
# azure-pipelines-deployment.yml
trigger:
  branches:
    include:
    - main
    - release/*

pool:
  vmImage: 'windows-latest'

variables:
  EnvironmentName: 'UAT'

stages:
- stage: Deploy
  jobs:
  - job: DeployApplication
    steps:
    - task: PowerShell@2
      displayName: 'Deploy Application'
      inputs:
        targetType: 'inline'
        script: |
          Write-Host "Deploying Radar Live to $(EnvironmentName)"

- stage: Validate
  dependsOn: Deploy
  jobs:
  - job: ValidateEnvironment
    steps:
    - checkout: self

    - task: PowerShell@2
      displayName: 'Execute Post-Install Skim'
      inputs:
        targetType: 'filePath'
        filePath: '$(System.DefaultWorkingDirectory)/Invoke-PostInstallSkim.ps1'
        arguments: '-ManifestPath "$(System.DefaultWorkingDirectory)/manifests/desired-state-manifest.$(EnvironmentName).json"'
        failOnStderr: true
        pwsh: true

    - task: PublishTestResults@2
      displayName: 'Publish Pester Test Results'
      inputs:
        testResultsFormat: 'NUnit'
        testResultsFiles: '**/pester-results.xml'
        testRunTitle: 'Radar Live Validation - $(EnvironmentName)'
        failTaskOnFailedTests: true
```

### Azure DevOps Pipeline (Scheduled Drift Detection)

**Use Case**: Daily/weekly validation to detect configuration drift

```yaml
# azure-pipelines-drift-detection.yml
schedules:
- cron: "0 2 * * *"  # 2 AM daily
  displayName: 'Daily PRD Drift Detection'
  branches:
    include:
    - main
  always: true

trigger: none

pool:
  name: 'PRD-Agents'

variables:
  EnvironmentName: 'PRD'

jobs:
- job: DriftDetection
  steps:
  - checkout: self

  - task: PowerShell@2
    displayName: 'Run Validation'
    inputs:
      targetType: 'filePath'
      filePath: '$(System.DefaultWorkingDirectory)/Invoke-PostInstallSkim.ps1'
      arguments: '-ManifestPath "manifests/desired-state-manifest.prd.json"'
      pwsh: true
    continueOnError: true

  - task: PublishTestResults@2
    inputs:
      testResultsFormat: 'NUnit'
      testResultsFiles: '**/pester-results.xml'

  - task: PowerShell@2
    displayName: 'Send Alert on Failure'
    condition: failed()
    inputs:
      targetType: 'inline'
      script: |
        $subject = "[ALERT] PRD Drift Detected"
        $body = "Configuration drift detected. Review pipeline: $(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"
        Send-MailMessage -To "ops-team@domain.com" -From "azdo@domain.com" -Subject $subject -Body $body -SmtpServer "smtp.domain.com"
```

### Recommended Schedule by Environment

| Environment | Schedule | Frequency | Rationale |
|-------------|----------|-----------|-----------|
| **PRD** | `0 2 * * *` | Daily (2 AM) | Detect drift from patches, Windows Updates |
| **UAT** | `0 2 * * 1` | Weekly (Monday 2 AM) | Pre-deployment validation |
| **DEV** | On-demand | Post-deployment only | Manual trigger after deployments |

**Cron Schedule Examples**:
```yaml
# Daily at 2 AM:    "0 2 * * *"
# Weekly Monday:    "0 6 * * 1"
# Twice daily:      "0 8,20 * * *"
# Business hours:   "0 9 * * 1-5"
```

### Self-Hosted Agent Setup

```powershell
# Install PowerShell 7.5+
Invoke-WebRequest -Uri https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.msi -OutFile PS75.msi
Start-Process msiexec.exe -ArgumentList "/i PS75.msi /quiet" -Wait

# Install Pester 5.0+
pwsh -Command "Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck"

# Configure agent as service (using gMSA)
cd C:\Agents\Agent01
.\config.cmd --unattended --url https://dev.azure.com/{org} --auth pat --token {PAT} --pool PRD-Agents --runAsService --windowsLogonAccount "DOMAIN\gMSA-Agent$"
```

---

## Additional Resources

- **Constitution**: `.specify/memory/constitution.md` (design principles)
- **Research Documentation**: `specs/main/research.md` (architectural decisions)
- **Data Model**: `specs/main/data-model.md` (entity definitions)
- **JSON Schema**: `specs/main/contracts/manifest-schema.json` (manifest validation)
- **Feature Spec**: `specs/main/spec.md` (detailed requirements)

---

## Support

**Issue Reporting**: `<issue-tracker-url>`
**Documentation**: `<docs-url>`
**Contact**: ops-team@domain.com
