# Usage Guide: Running the Post-Install Skim
This guide explains how to run the Radar Live Post-Install Skim on **actual environments** (DEV, UAT, PRD) to validate operational readiness.
---
## Table of Contents
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Basic Usage](#basic-usage)
- [Advanced Scenarios](#advanced-scenarios)
- [Understanding Results](#understanding-results)
- [Artifact Review](#artifact-review)
- [Troubleshooting](#troubleshooting)
- [Scheduled Scans](#scheduled-scans)
---
## Quick Start
### 1. Run Skim for DEV Environment
```powershell
# Navigate to repository root
cd C:\path\to\radar-postinstall-skim
# Run the skim
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV
```
**Expected Output:**
```
=== Radar Live Post-Install Skim ===
Environment: DEV
Manifest: ./specs/main/desired-state-manifest.dev.json
Scan Type: Manual
[Phase 1] Version Validation...
  Status: PASS
[Phase 2] IIS/AppPool Validation...
  Status: PASS
[Phase 3] SQL Server Validation...
  Status: PASS
[Phase 4] Network Validation...
  Status: PASS
[Phase 5] Event Log Scan...
  Status: WARN
[Phase 6] Component Health Checks...
  Status: PASS
=== Summary ===
Total Checks: 6
PASS: 5
WARN: 1
FAIL: 0
Ready for Use: YES
✓ Environment is Ready for Use
```
---
## Prerequisites
### System Requirements
- **PowerShell 7.5+** ([Download](https://github.com/PowerShell/PowerShell/releases))
- **Windows Server 2019+** (where Radar Live is installed)
- **Network access** to SQL Server (port 1433)
- **IIS installed** (if validating IIS components)
### Required Permissions
The skim requires **read-only access** to:
- IIS configuration (`Get-IISSite`, `Get-IISAppPool`)
- Windows Event Log (`Get-WinEvent`)
- SQL Server connectivity (TCP/1433)
- Component health endpoints (HTTP GET)
- File system (read config files)
**Note:** The skim follows **least privilege** principles - no admin rights required unless checking privileged event logs.
### Environment Manifests
Create a manifest JSON file for each environment (DEV, UAT, PRD):
- `specs/main/desired-state-manifest.dev.json` (DEV)
- `specs/main/desired-state-manifest.uat.json` (UAT)
- `specs/main/desired-state-manifest.prd.json` (PRD)
See [Manifest Structure](#manifest-structure) below for format.
---
## Basic Usage
### Run Skim with Default Settings
```powershell
# DEV environment (uses default manifest)
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV
# UAT environment (specify custom manifest)
.\src\Invoke-PostInstallSkim.ps1 -Environment UAT -ManifestPath .\specs\main\desired-state-manifest.uat.json
# PRD environment
.\src\Invoke-PostInstallSkim.ps1 -Environment PRD -ManifestPath .\specs\main\desired-state-manifest.prd.json
```
### Output Formats
```powershell
# Table format (default, human-readable)
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV -OutputFormat Table
# JSON format (for automation/CI)
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV -OutputFormat JSON
# Markdown format (for documentation)
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV -OutputFormat Markdown
```
### Save Artifacts
```powershell
# Artifacts saved by default to .specify/baselines/
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV
# Disable artifact saving
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV -SaveArtifact $false
```
---
## Advanced Scenarios
### Scenario 1: Post-Installation Validation
**When:** Immediately after installing Radar Live on a fresh environment.
```powershell
# Run full skim
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV
# Review results
if ($LASTEXITCODE -eq 0) {
    Write-Host "Installation successful - environment ready for use"
} else {
    Write-Host "Installation issues detected - review failures before proceeding"
    exit 1
}
```
### Scenario 2: Post-Patching Validation
**When:** After applying patches or configuration changes.
```powershell
# Run skim to detect drift
.\src\Invoke-PostInstallSkim.ps1 -Environment PRD
# Compare with previous artifact
.\src\CLI\ReviewArtifacts.ps1 -Environment PRD -Top 2
```
### Scenario 3: Scheduled Compliance Scan
**When:** Nightly/weekly scans to detect drift.
```powershell
# Run with -Scheduled flag (affects metadata)
.\src\Invoke-PostInstallSkim.ps1 -Environment PRD -Scheduled
# Schedule with Windows Task Scheduler:
# Action: powershell.exe
# Arguments: -File "C:\radar-postinstall-skim\src\Invoke-PostInstallSkim.ps1" -Environment PRD -Scheduled
```
### Scenario 4: CI/CD Pipeline Integration
**When:** Automated validation in deployment pipeline.
```powershell
# Run skim in CI/CD
.\src\Invoke-PostInstallSkim.ps1 -Environment UAT -OutputFormat JSON > results.json
# Parse results
$Results = Get-Content results.json | ConvertFrom-Json
if (-not $Results.ReadyForUse) {
    Write-Error "Environment validation failed"
    exit 1
}
```
### Scenario 5: Audit/Compliance Review
**When:** Reviewing historical scan results for compliance.
```powershell
# Review last 90 days of artifacts
.\src\CLI\ReviewArtifacts.ps1 -Environment PRD -StartDate (Get-Date).AddDays(-90)
# Export to CSV for audit
.\src\CLI\ReviewArtifacts.ps1 -Environment PRD -ExportPath audit-report.csv
```
---
## Understanding Results
### Status Meanings
| Status | Meaning | Action Required |
|--------|---------|-----------------|
| **PASS** | Check passed all validation criteria | None - component is healthy |
| **WARN** | Non-critical issue detected | Review and acknowledge WARN; may proceed if threshold not exceeded |
| **FAIL** | Critical issue detected | **Block deployment** - resolve issue before proceeding |
### Ready for Use Logic
An environment is **Ready for Use** if:
1. **Zero FAIL statuses** (all critical checks passed)
2. **WARNs ≤ threshold** (default: 3)
If either condition fails, the environment is **NOT Ready for Use**.
### Exit Codes
| Exit Code | Meaning |
|-----------|---------|
| `0` | Ready for Use (PASS or acceptable WARNs) |
| `1` | NOT Ready for Use (FAILs or WARN threshold exceeded) |
### Result Fields
Each check returns:
```powershell
[PSCustomObject]@{
    CheckType = 'IIS'              # Type of check
    Status    = 'PASS'             # PASS/WARN/FAIL
    Message   = 'All checks passed' # Human-readable message
    Details   = @{ ... }           # Additional diagnostic info
}
```
---
## Artifact Review
### View Recent Artifacts
```powershell
# List all artifacts for DEV
.\src\CLI\ReviewArtifacts.ps1 -Environment DEV
# Show last 5 artifacts
.\src\CLI\ReviewArtifacts.ps1 -Environment PRD -Top 5
# Show detailed results
.\src\CLI\ReviewArtifacts.ps1 -Environment UAT -ShowDetails
```
### Filter Artifacts
```powershell
# Filter by status
.\src\CLI\ReviewArtifacts.ps1 -Environment PRD -Status FAIL
# Filter by date range
.\src\CLI\ReviewArtifacts.ps1 -Environment DEV -StartDate 2025-11-01 -EndDate 2025-11-30
# Combine filters
.\src\CLI\ReviewArtifacts.ps1 -Environment UAT -Status WARN -StartDate (Get-Date).AddDays(-7)
```
### Export Artifacts
```powershell
# Export to CSV for analysis
.\src\CLI\ReviewArtifacts.ps1 -Environment PRD -ExportPath artifacts-prd.csv
# Open in Excel
Invoke-Item artifacts-prd.csv
```
---
## Troubleshooting
### Issue: "Manifest not found"
**Cause:** Manifest file doesn't exist at specified path.
**Solution:**
```powershell
# Check manifest exists
Test-Path ./specs/main/desired-state-manifest.dev.json
# Create from template
Copy-Item ./specs/main/desired-state-manifest.dev.json ./specs/main/desired-state-manifest.uat.json
```
### Issue: "Environment mismatch"
**Cause:** `-Environment` parameter doesn't match `EnvironmentName` in manifest.
**Solution:**
```powershell
# Verify manifest content
(Get-Content ./specs/main/desired-state-manifest.dev.json | ConvertFrom-Json).EnvironmentName
# Ensure they match:
.\src\Invoke-PostInstallSkim.ps1 -Environment DEV -ManifestPath ./specs/main/desired-state-manifest.dev.json
```
### Issue: "Access denied" errors
**Cause:** Insufficient permissions to read IIS config or event logs.
**Solution:**
```powershell
# Run with elevated privileges (if required)
Start-Process pwsh -Verb RunAs -ArgumentList "-File", "C:\radar-postinstall-skim\src\Invoke-PostInstallSkim.ps1", "-Environment", "DEV"
# Or add user to appropriate groups:
# - IIS_IUSRS (for IIS read access)
# - Event Log Readers (for event log access)
```
### Issue: SQL connectivity failures
**Cause:** Network/firewall blocking port 1433 or SQL not running.
**Solution:**
```powershell
# Test SQL connectivity manually
Test-NetConnection -ComputerName sql-server.example.com -Port 1433
# Verify DNS resolution
Resolve-DnsName sql-server.example.com
# Check firewall rules
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*SQL*" }
```
### Issue: Health endpoint timeouts
**Cause:** Component not running or health endpoint misconfigured.
**Solution:**
```powershell
# Test health endpoint manually
Invoke-WebRequest -Uri http://localhost:8081/health -TimeoutSec 5
# Check component service
Get-Service -Name RadarManagementServer
# Verify AppPool running
Import-Module WebAdministration
Get-IISAppPool -Name ManagementServerAppPool | Select-Object Name, State
```
---
## Scheduled Scans
### Windows Task Scheduler Setup
1. **Open Task Scheduler** → Create Task
2. **General Tab:**
   - Name: `Radar Live Post-Install Skim - PRD`
   - Run whether user is logged on or not
   - Run with highest privileges (if needed)
3. **Triggers Tab:**
   - New → Daily at 2:00 AM
   - Or: Weekly on Sunday at 2:00 AM
4. **Actions Tab:**
   - Action: Start a program
   - Program: `C:\Program Files\PowerShell\7\pwsh.exe`
   - Arguments: `-File "C:\radar-postinstall-skim\src\Invoke-PostInstallSkim.ps1" -Environment PRD -Scheduled`
   - Start in: `C:\radar-postinstall-skim`
5. **Conditions Tab:**
   - Uncheck "Start only if on AC power"
6. **Settings Tab:**
   - If task fails, restart every 10 minutes (up to 3 times)
### Verify Scheduled Task
```powershell
# Check task status
Get-ScheduledTask -TaskName "Radar Live Post-Install Skim - PRD"
# View last run result
Get-ScheduledTaskInfo -TaskName "Radar Live Post-Install Skim - PRD"
# Test task manually
Start-ScheduledTask -TaskName "Radar Live Post-Install Skim - PRD"
```
---
## Manifest Structure
### Example: `desired-state-manifest.dev.json`
```json
{
  "EnvironmentName": "DEV",
  "GMSInUse": "TEST\\SVRPPRRDRLDEV01$",
  "Components": [
    {
      "displayName": "Management Server",
      "expectedServiceName": "RadarManagementServer",
      "expectedInstallPath": "C:/Program Files/Radar/ManagementServer",
      "expectedHealthUrl": "http://localhost:8081/health",
      "expectedAppPool": "ManagementServerAppPool",
      "runtimeDependencies": []
    }
  ],
  "IIS": {
    "requiredWindowsFeatures": ["Web-Server", "Web-ASP-Net45"],
    "expectedSites": ["RadarLive"],
    "expectedAppPools": [
      {"name": "ManagementServerAppPool", "expectedIdentity": "TEST\\SVRPPRRDRLDEV01$"}
    ]
  },
  "SQL": {
    "sqlServers": [
      {"host": "sql-dev.example.com", "database": "RadarLive_DEV"}
    ],
    "connectionTest": true,
    "dnsResolutionTimeoutSeconds": 3,
    "portConnectionTimeoutSeconds": 5
  },
  "Network": {
    "dnsResolution": true,
    "portOpen": [1433, 8081, 8082, 8083, 8084, 8085],
    "routingChecks": true,
    "routingCheckDescription": "Validate default gateway for outbound SQL connectivity"
  },
  "EventLog": {
    "lookbackHours": 12,
    "filterSources": ["RadarLive", "ASP.NET"],
    "severityLevels": ["Error", "Critical"]
  },
  "VersionChecks": {
    "dotnetHostingBundle": ">=7.0.0",
    "powershellMinimumVersion": ">=7.5.0",
    "wtwManagementModule": {"name": "WTW.Management", "minVersion": "1.0.0"}
  },
  "HealthAndTiming": {
    "healthHttpTimeoutSeconds": 5,
    "healthSuccessCodes": [200, 204],
    "maxTotalSkimDurationSeconds": 300
  },
  "DriftDetection": {
    "driftScanSchedule": "0 2 * * *",
    "driftScanScheduleFormat": "cron",
    "enabled": true
  }
}
```
### Creating Manifests for UAT/PRD
```powershell
# Copy DEV manifest as template
Copy-Item ./specs/main/desired-state-manifest.dev.json ./specs/main/desired-state-manifest.uat.json
# Edit UAT manifest
code ./specs/main/desired-state-manifest.uat.json
# Update:
# - EnvironmentName: "UAT"
# - GMSInUse: "PROD\\SVRPPRRDRLUAT01$"
# - SQL.sqlServers[].host: "sql-uat.example.com"
# - SQL.sqlServers[].database: "RadarLive_UAT"
# - Component URLs/paths as appropriate
```
---
## Best Practices
### Pre-Deployment
1. Run skim on UAT before promoting to PRD
2. Review all FAIL/WARN statuses with operations team
3. Acknowledge WARNs if acceptable for deployment
4. Save baseline snapshot for drift comparison
### Post-Deployment
1. Run skim immediately after deployment
2. Compare results with pre-deployment baseline
3. Investigate any new FAILs or drift
4. Document WARN acknowledgments
### Scheduled Compliance
1. Run nightly or weekly scheduled scans
2. Review artifacts monthly for trends
3. Investigate persistent WARNs
4. Update manifests when infrastructure changes
### Audit Trail
1. Export artifacts quarterly for compliance
2. Retain artifacts for 90+ days (constitutional requirement)
3. Document WARN acknowledgments with justification
4. Track ReadyForUse status over time
---
## Additional Resources
- **Constitution:** `.specify/memory/constitution.md` - Governance and requirements
- **Specification:** `specs/main/spec.md` - Feature details and acceptance criteria
- **Testing Guide:** `docs/TESTING.md` - Developer testing (unit tests)
- **Architecture:** `README.md` - Project structure and module reference
---
**Last Updated:** November 30, 2025
**Version:** 1.0.0