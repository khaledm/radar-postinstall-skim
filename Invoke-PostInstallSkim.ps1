#Requires -Version 7.5
#Requires -Modules Pester

<#
.SYNOPSIS
    Radar Live Post-Install Skim - Environment Readiness Validation Orchestrator.

.DESCRIPTION
    Orchestrates validation test suite execution against desired-state manifest.
    Produces ReadyForUse determination with PASS/FAIL/WARN classification.

.PARAMETER ManifestPath
    Path to desired-state manifest JSON file.

.PARAMETER OutputFormat
    Output format for orchestration report (Table, JSON, Markdown, All).

.PARAMETER SkipSecretRedaction
    Skip secret redaction in output (for debugging only).

.EXAMPLE
    .\Invoke-PostInstallSkim.ps1 -ManifestPath '.\manifests\desired-state-manifest.dev.json' -OutputFormat All

.OUTPUTS
    Exit code 0 if ReadyForUse=true, exit code 1 if ReadyForUse=false.

.NOTES
    Module follows PowerShell 7.5+ best practices.
    Implements constitution Section V ReadyForUse logic.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath,

    [Parameter()]
    [ValidateSet('Table', 'JSON', 'Markdown', 'All')]
    [string]$OutputFormat = 'All',

    [Parameter()]
    [switch]$SkipSecretRedaction
)

# Set strict mode for better error detection
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Write-Host "=== Radar Live Post-Install Skim ===" -ForegroundColor Cyan
    Write-Host ""

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    #region Module Import
    Write-Host "Step 1: Importing modules..." -ForegroundColor Cyan

    $moduleBasePath = Join-Path $PSScriptRoot 'modules'
    $requiredModules = @(
        'ManifestValidation'
        'SecretRedaction'
        'ArtifactManagement'
        'PesterInvocation'
        'ResultAggregation'
    )

    foreach ($moduleName in $requiredModules) {
        $modulePath = Join-Path $moduleBasePath "$moduleName\$moduleName.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Verbose "Imported module: $moduleName"
    }

    Write-Host "  ✓ Modules loaded" -ForegroundColor Green
    #endregion

    #region Manifest Loading and Validation
    Write-Host "Step 2: Loading and validating manifest..." -ForegroundColor Cyan

    # T1301: Manifest loading and validation
    $manifest = Import-DesiredStateManifest -Path $ManifestPath
    Write-Verbose "Loaded manifest for environment: $($manifest.EnvironmentName)"

    # Validate manifest schema
    $schemaValid = Test-ManifestSchema -Manifest $manifest
    if (-not $schemaValid) {
        throw "Manifest schema validation failed. Check manifest structure against contracts/manifest-schema.json"
    }

    # Validate dependency DAG (no circular dependencies)
    Test-DependencyDAG -Manifest $manifest

    # Validate gMSA consistency
    $gmsaResult = Get-GMSAConsistency -Manifest $manifest
    if (-not $gmsaResult.IsValid) {
        Write-Warning "gMSA consistency issues detected:"
        $gmsaResult.Mismatches | ForEach-Object {
            Write-Warning "  - $($_.Context): Expected '$($gmsaResult.GMSInUse)', Found '$($_.ActualIdentity)'"
        }
    }

    Write-Host "  ✓ Manifest validated (Environment: $($manifest.EnvironmentName), Components: $($manifest.ComponentsToDeploy.Count))" -ForegroundColor Green
    #endregion

    #region Test Discovery
    Write-Host "Step 3: Discovering test files..." -ForegroundColor Cyan

    # T1302: Pester test discovery
    $testPath = Join-Path $PSScriptRoot 'tests'
    $testFiles = Get-ChildItem -Path $testPath -Filter '*.Tests.ps1' -File

    Write-Host "  ✓ Found $($testFiles.Count) test suites" -ForegroundColor Green
    #endregion

    #region Pester Execution
    Write-Host "Step 4: Executing Pester tests..." -ForegroundColor Cyan

    # T1303: Pester execution with timeout
    $maxDuration = $manifest.MaxTotalSkimDurationSeconds ?? 300
    $timeoutSeconds = $maxDuration - 30  # Reserve 30s for report generation

    # Create temporary artifact directory for Pester results
    $tempArtifactPath = Join-Path $env:TEMP "radar-skim-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"
    New-Item -Path $tempArtifactPath -ItemType Directory -Force | Out-Null
    $pesterXmlPath = Join-Path $tempArtifactPath 'pester-results.xml'

    # Create Pester containers for each test file with manifest data
    $containers = $testFiles | ForEach-Object {
        New-PesterContainer -Path $_.FullName -Data @{ Manifest = $manifest }
    }

    # Configure Pester
    $config = New-PesterConfiguration
    $config.Run.Container = $containers
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $pesterXmlPath
    $config.TestResult.OutputFormat = 'NUnit3'

    $pesterResult = Invoke-Pester -Configuration $config

    Write-Host "  ✓ Pester execution complete (Total: $($pesterResult.TotalCount), Passed: $($pesterResult.PassedCount), Failed: $($pesterResult.FailedCount))" -ForegroundColor Green
    #endregion

    #region Result Aggregation
    Write-Host "Step 5: Aggregating results..." -ForegroundColor Cyan

    # T1304: Result aggregation
    $classification = Get-CriticalityClassification -PesterResult $pesterResult

    Write-Host "  ✓ Classification: PASS=$($classification.PassCount), FAIL=$($classification.FailCount), WARN=$($classification.WarnCount)" -ForegroundColor Green
    #endregion

    #region ReadyForUse Calculation
    Write-Host "Step 6: Calculating ReadyForUse..." -ForegroundColor Cyan

    # T1305: ReadyForUse calculation
    $warnThreshold = $manifest.WarnThreshold ?? 3
    $readyForUse = Get-ReadyForUse -Classification $classification -WarnThreshold $warnThreshold

    $status = if ($readyForUse.ReadyForUse) { "✓ READY" } else { "✗ NOT READY" }
    $color = if ($readyForUse.ReadyForUse) { "Green" } else { "Red" }

    Write-Host "  $status (FailCount=$($readyForUse.FailCount), WarnCount=$($readyForUse.WarnCount), Threshold=$warnThreshold)" -ForegroundColor $color
    #endregion

    #region Report Generation
    Write-Host "Step 7: Generating orchestration report..." -ForegroundColor Cyan

    # T1306: Orchestration report generation
    $stopwatch.Stop()
    $report = New-OrchestrationReport `
        -Manifest $manifest `
        -Classification $classification `
        -ReadyForUse $readyForUse `
        -ExecutionTime $stopwatch.Elapsed `
        -ArtifactPath $tempArtifactPath

    Write-Host "  ✓ Report generated" -ForegroundColor Green
    #endregion

    #region Secret Redaction
    Write-Host "Step 8: Redacting secrets..." -ForegroundColor Cyan

    # T1307: Secret redaction
    if (-not $SkipSecretRedaction) {
        $report.Json = Invoke-SecretRedaction -Input $report.Json
        $report.Markdown = Invoke-SecretRedaction -Input $report.Markdown

        # Validate no secrets remain
        $hasSecrets = Test-ContainsSecret -Input $report.Json
        if ($hasSecrets) {
            Write-Warning "Unredacted secrets detected in JSON report!"
        }

        Write-Host "  ✓ Secret redaction applied" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Secret redaction skipped (debugging mode)" -ForegroundColor Yellow
    }
    #endregion

    #region Artifact Storage (T1501-T1505)
    if ($manifest.Reporting.StoreHistory -and $manifest.Reporting.HistoryStoragePath) {
        Write-Host "Step 9: Storing artifacts..." -ForegroundColor Cyan

        try {
            $artifactTimestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH-mm-ssZ')

            # T1502: Create artifact directory structure
            $artifactPaths = New-ArtifactDirectory `
                -BasePath $manifest.Reporting.HistoryStoragePath `
                -Environment $manifest.EnvironmentName `
                -Timestamp $artifactTimestamp

            # T1503-T1504: Save test execution artifacts
            Save-TestExecutionArtifacts `
                -ArtifactPath $artifactPaths.TestExecutionPath `
                -PesterResult $pesterResult `
                -OrchestrationReportJson $report.Json `
                -OrchestrationReportMarkdown $report.Markdown

            # T1505: Save environment baseline artifacts
            Save-EnvironmentBaselineArtifacts `
                -ArtifactPath $artifactPaths.EnvironmentBaselinePath `
                -Manifest $manifest

            Write-Host "  ✓ Artifacts stored successfully" -ForegroundColor Green
            Write-Host "    Test Execution: $($artifactPaths.TestExecutionPath)" -ForegroundColor Gray
            Write-Host "    Baseline: $($artifactPaths.EnvironmentBaselinePath)" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to store artifacts: $($_.Exception.Message)"
        }
    }
    #endregion

    #region Output
    Write-Host ""
    Write-Host "=== Orchestration Report ===" -ForegroundColor Cyan
    Write-Host ""

    if ($OutputFormat -in @('Table', 'All')) {
        Write-Host "Environment: $($manifest.EnvironmentName)" -ForegroundColor White
        Write-Host "Execution Time: $($stopwatch.Elapsed.TotalSeconds)s" -ForegroundColor White
        Write-Host "Ready For Use: $($readyForUse.ReadyForUse)" -ForegroundColor $color
        Write-Host ""
        Write-Host "Summary:" -ForegroundColor White
        Write-Host "  Total Tests: $($classification.TotalCount)" -ForegroundColor White
        Write-Host "  Passed:      $($classification.PassCount)" -ForegroundColor Green
        Write-Host "  Failed:      $($classification.FailCount)" -ForegroundColor $(if ($classification.FailCount -gt 0) { 'Red' } else { 'White' })
        Write-Host "  Warned:      $($classification.WarnCount)" -ForegroundColor $(if ($classification.WarnCount -gt 0) { 'Yellow' } else { 'White' })
        Write-Host "  Skipped:     $($classification.SkipCount)" -ForegroundColor Gray
        Write-Host ""
    }

    if ($OutputFormat -in @('JSON', 'All')) {
        Write-Host "JSON Report:" -ForegroundColor White
        Write-Host $report.Json
        Write-Host ""
    }

    if ($OutputFormat -in @('Markdown', 'All')) {
        Write-Host "Markdown Report:" -ForegroundColor White
        Write-Host $report.Markdown
        Write-Host ""
    }
    #endregion

    # T1308: Exit code logic
    $exitCode = if ($readyForUse.ReadyForUse) { 0 } else { 1 }

    Write-Host "=== Validation Complete ===" -ForegroundColor Cyan
    Write-Host ""

    exit $exitCode
}
catch {
    Write-Host ""
    Write-Host "=== Validation Failed ===" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host ""

    exit 1
}
