# Radar Live Post-Install Skim
[![Lint and Format](https://github.com/khaledm/radar-postinstall-skim/workflows/Lint%20and%20Format/badge.svg)](https://github.com/khaledm/radar-postinstall-skim/actions)
[![PowerShell 7.5+](https://img.shields.io/badge/PowerShell-7.5%2B-blue)](https://github.com/PowerShell/PowerShell)
This project validates Radar Live environments (DEV/UAT/PRD) for operational readiness after installation or patching. All checks are modular, DRY, and PowerShell 7.5+ compliant per the [Constitution](specs/main/constitution.md).
## Table of Contents
- [Features](#features)
- [Quick Start](#quick-start)
  - [For Operations: Running the Skim](#for-operations-running-the-skim)
  - [For Developers: Testing the Code](#for-developers-testing-the-code)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Contributing](#contributing)
## Features
### Environment Readiness Validation (US1)
- **IIS/AppPool**: Windows features, sites, gMSA identity validation
- **SQL Server**: DNS resolution, port connectivity, live connection tests
- **Network**: DNS, port, routing, firewall rule validation
- **Event Log**: Lookback scanning with error thresholds
### Artifact Storage & Drift Detection (US2)
- **Historical artifacts**: Test execution and environment baseline storage
- **ISO 8601 timestamps**: Organized by environment and timestamp
- **Post-change validation**: Re-runnable tests after patching/changes
- **Baseline comparison**: Config files, AppPool identity, versions
- **Scheduled scans**: Cron/interval schedule support
- **Drift reporting**: Before/after values with criticality rules
### Security & Compliance
- **Least privilege**: Read-only operations, no admin rights required
- **Secrets redaction**: Entropy + regex pattern detection
- **5-minute budget**: Total runtime enforcement with per-check limits
- **PASS/FAIL/WARN semantics**: Consistent status reporting
## Quick Start
### For Operations: Running the Skim
**To validate an environment (DEV/UAT/PRD):**
```powershell
# Clone repository
git clone https://github.com/khaledm/radar-postinstall-skim.git
cd radar-postinstall-skim
# Run the skim for DEV environment
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV
# Run for UAT with custom manifest
.\src\Invoke-PostInstallSkim.ps1 -Environment UAT -ManifestPath .\specs\main\desired-state-manifest.uat.json
# Run for PRD (scheduled scan)
.\src\Invoke-PostInstallSkim.ps1 -Environment PRD -Scheduled
```
**Exit codes:**
- `0` = Environment is Ready for Use (all checks PASS or acceptable WARNs)
- `1` = Environment is NOT Ready for Use (FAILs detected or WARN threshold exceeded)
📖 **See [docs/USAGE.md](docs/USAGE.md) for complete operational guide**
### For Developers: Testing the Code
**To run unit tests during development:**
```powershell
# Install Pester 5.0+
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser
# Run all unit tests
Invoke-Pester -Path ./tests/unit -Output Detailed
# Run specific test suite
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1 -Output Detailed
```
📖 **See [docs/TESTING.md](docs/TESTING.md) for complete testing guide**
## Usage Examples
### Example 1: Validate Environment Readiness
```powershell
# Load manifest
$manifest = Get-Content .specify/manifest.json | ConvertFrom-Json
# Run all US1 checks
Import-Module ./src/Checks/IIS.psm1
Import-Module ./src/Checks/SQL.psm1
Import-Module ./src/Checks/Network.psm1
Import-Module ./src/Checks/EventLog.psm1
Import-Module ./src/Core/ResultAggregator.psm1
$results = @()
# IIS checks
$results += Test-IISAppPoolGMSA -Manifest $manifest
# SQL checks
$results += Test-SQLConnectivity -Manifest $manifest
# Network checks
$results += Test-NetworkChecks -Manifest $manifest
# EventLog checks
$results += Test-EventLogScan -Manifest $manifest
# Aggregate results
$overallStatus = Get-AggregatedStatus -Results $results
# Display summary
Write-Host "`nOverall Status: $overallStatus" -ForegroundColor $(
    switch ($overallStatus) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
    }
)
$results | Format-Table CheckName, Status, Message -AutoSize
```
### Example 2: Save and Review Artifacts
```powershell
# Save current scan as artifact
Import-Module ./src/ArtifactStore.psm1
$report = @{
    OverallStatus = 'PASS'
    ReadyForUse = $true
    Summary = @{
        TotalChecks = 10
        PassCount = 10
        FailCount = 0
        WarnCount = 0
    }
    CheckResults = $results
}
$artifactResult = Save-SkimArtifact -Report $report -Environment 'PROD'
Write-Host "Artifact saved: $($artifactResult.ArtifactPath)"
# Review artifacts
.\src\CLI\ReviewArtifacts.ps1 -Environment PROD -StartDate (Get-Date).AddDays(-30)
# Export to CSV
.\src\CLI\ReviewArtifacts.ps1 -Environment PROD -ExportPath artifacts-prod.csv
```
### Example 3: Drift Detection
```powershell
# Create baseline snapshot
Import-Module ./src/Baselines/Snapshot.psm1
$baseline = New-BaselineSnapshot -Manifest $manifest
Save-BaselineSnapshot -Snapshot $baseline -Path .specify/baselines/
# Later, compare current state to baseline
$comparison = Compare-BaselineSnapshot -Baseline $baseline -Manifest $manifest
if ($comparison.Status -eq 'FAIL') {
    Write-Host "Drift detected!" -ForegroundColor Red
    $comparison.Results | Where-Object { $_.Status -ne 'PASS' } |
        Format-Table CheckName, Status, Message -AutoSize
}
```
### Example 4: Component Health Checks
```powershell
# Test component health endpoints
Import-Module ./src/Checks/Health.psm1
$healthResult = Test-ComponentHealthChecks -Manifest $manifest
foreach ($check in $healthResult.Results) {
    $color = switch ($check.Status) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
    }
    Write-Host "$($check.ComponentName): $($check.Status)" -ForegroundColor $color
}
```
### Example 5: Generate Component Acceptance Harness
```powershell
# Auto-generate acceptance test script for component
Import-Module ./src/Harness/ComponentAcceptance.psm1
$harness = New-ComponentAcceptanceHarness -Manifest $manifest -ComponentName 'WebAPI'
# Run generated harness
& $harness.Harnesses[0].HarnessPath -Environment PROD
```
## Testing
### Run All Tests
```powershell
# Install Pester
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force
# Run all unit tests
Invoke-Pester -Path ./tests/unit -Output Detailed
```
### Run Specific Test Suite
```powershell
# Environment readiness tests
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1
# Artifact storage tests
Invoke-Pester -Path ./tests/unit/Artifact.Tests.ps1
# Post-change validation tests
Invoke-Pester -Path ./tests/unit/Drift.Tests.ps1
```
### Linting
```powershell
# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Force
# Run linting
Invoke-ScriptAnalyzer -Path . -Recurse
```
**📖 For detailed testing guidance, see [docs/TESTING.md](docs/TESTING.md)**
## Architecture
### Directory Structure
```
radar-postinstall-skim/
├── src/
│   ├── Core/                   # Core infrastructure modules
│   │   ├── RuntimeGuard.psm1   # 5-minute budget enforcement
│   │   ├── RetryPolicy.psm1    # Graceful degradation
│   │   └── ResultAggregator.psm1  # PASS/FAIL/WARN aggregation
│   ├── Checks/                 # Validation modules
│   │   ├── IIS.psm1           # IIS/AppPool/gMSA checks
│   │   ├── SQL.psm1           # SQL connectivity
│   │   ├── Network.psm1       # Network validation
│   │   ├── EventLog.psm1      # Event log scanning
│   │   ├── Health.psm1        # Health endpoint checks
│   │   ├── ConfigFile.psm1    # Config validation
│   │   ├── Version.psm1       # Version checks
│   │   ├── DependencyOrder.psm1  # Topological sorting
│   │   └── DriftSchedule.psm1 # Drift scan scheduling
│   ├── Baselines/             # Baseline management
│   │   └── Snapshot.psm1      # Snapshot creation/comparison
│   ├── Reporting/             # Reporting modules
│   │   └── WarnAcks.psm1      # WARN acknowledgments
│   ├── Harness/               # Test harness generation
│   │   └── ComponentAcceptance.psm1
│   ├── CLI/                   # Command-line tools
│   │   └── ReviewArtifacts.ps1
│   └── ArtifactManagement.psm1 # Artifact storage
├── tests/
│   └── unit/                  # Pester unit tests (no integration)
├── specs/
│   └── main/                  # Design specifications
│       ├── constitution.md    # Governing principles
│       ├── spec.md           # Feature specifications
│       ├── plan.md           # Implementation plan
│       └── tasks.md          # Task breakdown
└── .github/
    └── workflows/            # CI/CD pipelines
```
### Key Modules
| Module | Purpose | Constitutional Reference |
|--------|---------|-------------------------|
| `RuntimeGuard` | Enforces 5-minute total + 30s per-check budget | Section X |
| `ResultAggregator` | FAIL > WARN > PASS precedence | Section V |
| `ArtifactManagement` | Artifact storage with ISO 8601 timestamps | Section VIII |
| `LeastPrivilege` | Read-only validation | Section IX |
| `SecretRedaction` | Connection string redaction | Section IX |
| `ManifestValidation` | JSON schema validation | Section IV |
## Documentation
### Operations
- **[Usage Guide](docs/USAGE.md)** - **How to run the skim on environments (DEV/UAT/PRD)**
- **[Constitution](.specify/memory/constitution.md)** - Governance and requirements
### Development
- **[Testing Guide](docs/TESTING.md)** - **How to run unit tests**
- **[Specification](specs/main/spec.md)** - Feature requirements and user stories
- **[Implementation Plan](specs/main/plan.md)** - Technical architecture
- **[Task Breakdown](specs/main/tasks.md)** - Development roadmap (61 tasks, 100% complete)
### Checklists
- `specs/main/checklists/ux.md` - User experience requirements
- `specs/main/checklists/test.md` - Testing requirements
- `specs/main/checklists/security.md` - Security requirements
## Contributing
### Development Workflow
1. Read [Constitution](specs/main/constitution.md) for requirements
2. Review [Tasks](specs/main/tasks.md) for implementation order
3. Follow [Testing Guide](docs/TESTING.md) for validation
4. Run linting before commits: `Invoke-ScriptAnalyzer -Path . -Recurse`
5. Run all tests: `Invoke-Pester -Path ./tests/unit`
### Code Standards
- **PowerShell 7.5+** only
- **No integration tests** (per constitution)
- **PASS/FAIL/WARN semantics** for all checks
- **5-minute total runtime budget**
- **Least privilege** (read-only operations)
- **Secrets redaction** in all outputs
### Pull Request Process
1. Ensure all tests pass
2. Verify PSScriptAnalyzer has no errors
3. Update documentation if needed
4. Add usage examples for new features
5. Reference task number in commit message (e.g., "T301: Implement artifact retention")
## License
Copyright © 2025 WTW. All rights reserved.
## Support
For questions or issues:
1. **Operations:** Check [docs/USAGE.md](docs/USAGE.md) for running the skim
2. **Development:** Check [docs/TESTING.md](docs/TESTING.md) for testing guidance
3. Review [specs/main/spec.md](specs/main/spec.md) for feature details
4. Consult [.specify/memory/constitution.md](.specify/memory/constitution.md) for requirements
5. Open an issue in the GitHub repository
---
**Version**: 1.0.0
**Last Updated**: November 30, 2025
**PowerShell**: 7.5+
**Status**: ✅ Phases 1-5 Complete (39/61 tasks)