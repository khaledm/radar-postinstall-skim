#Requires -Version 7.5
<#
.SYNOPSIS
    Artifact management module for Radar Live Post-Install Skim.
.DESCRIPTION
    Manages storage of test execution and environment baseline artifacts.
    Implements constitution Section VIII artifact storage requirements.
.NOTES
    Module follows PowerShell 7.5+ best practices.
    Artifacts stored in local file system with ISO 8601 timestamps.
#>
using namespace System.IO
#region Public Functions
function New-ArtifactDirectory {
    <#
    .SYNOPSIS
        Creates artifact directory structure for test execution and environment baseline storage.
    .DESCRIPTION
        Creates subdirectories following the pattern:
        - {historyStoragePath}/test-execution/{environment}/{ISO8601-timestamp}/
        - {historyStoragePath}/environment-baseline/{environment}/{ISO8601-timestamp}/
    .PARAMETER BasePath
        Base path for artifact storage (from manifest historyStoragePath).
    .PARAMETER Environment
        Environment name (DEV/UAT/PRD).
    .PARAMETER Timestamp
        Optional ISO 8601 timestamp. Defaults to current UTC time.
    .EXAMPLE
        $paths = New-ArtifactDirectory -BasePath 'D:\Logs\RadarSkim\History' -Environment 'DEV'
    .OUTPUTS
        PSCustomObject with TestExecutionPath and EnvironmentBaselinePath.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath,
        [Parameter(Mandatory)]
        [ValidateSet('DEV', 'UAT', 'PRD')]
        [string]$Environment,
        [Parameter()]
        [string]$Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH-mm-ssZ')
    )
    process {
        try {
            # Sanitize timestamp for filesystem (replace colons)
            $safeTimestamp = $Timestamp -replace ':', '-'
            # Build paths
            $testExecutionPath = Join-Path $BasePath "test-execution\$Environment\$safeTimestamp"
            $baselinePath = Join-Path $BasePath "environment-baseline\$Environment\$safeTimestamp"
            # Create directories
            if ($PSCmdlet.ShouldProcess($testExecutionPath, 'Create directory')) {
                $null = New-Item -Path $testExecutionPath -ItemType Directory -Force
                Write-Verbose "Created test execution artifact directory: $testExecutionPath"
            }
            if ($PSCmdlet.ShouldProcess($baselinePath, 'Create directory')) {
                $null = New-Item -Path $baselinePath -ItemType Directory -Force
                Write-Verbose "Created environment baseline artifact directory: $baselinePath"
            }
            return [PSCustomObject]@{
                TestExecutionPath = $testExecutionPath
                EnvironmentBaselinePath = $baselinePath
                Timestamp = $Timestamp
            }
        }
        catch {
            Write-Error "Failed to create artifact directories: $_"
            throw
        }
    }
}
function Save-TestExecutionArtifacts {
    <#
    .SYNOPSIS
        Saves test execution artifacts (Pester results, orchestration reports).
    .DESCRIPTION
        Stores Pester NUnit3 XML, orchestration-report.json, and orchestration-report.md
        in the test-execution directory.
    .PARAMETER ArtifactPath
        Path to test-execution artifact directory (from New-ArtifactDirectory).
    .PARAMETER PesterResult
        Pester test result object (from Invoke-Pester with -PassThru).
    .PARAMETER OrchestrationReportJson
        Orchestration report as JSON string.
    .PARAMETER OrchestrationReportMarkdown
        Orchestration report as Markdown string.
    .EXAMPLE
        Save-TestExecutionArtifacts -ArtifactPath $paths.TestExecutionPath `
            -PesterResult $pesterResult `
            -OrchestrationReportJson $reportJson `
            -OrchestrationReportMarkdown $reportMd
    .OUTPUTS
        PSCustomObject with saved file paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactPath,
        [Parameter()]
        [object]$PesterResult,
        [Parameter()]
        [string]$OrchestrationReportJson,
        [Parameter()]
        [string]$OrchestrationReportMarkdown
    )
    process {
        try {
            $savedFiles = @()
            # Save Pester NUnit3 XML (copy from Pester output path if provided)
            if ($PesterResult -and $PesterResult.Configuration.TestResult.OutputPath) {
                $sourcePath = $PesterResult.Configuration.TestResult.OutputPath.Value
                $destPath = Join-Path $ArtifactPath 'pester-results.xml'
                if (Test-Path $sourcePath) {
                    if ($PSCmdlet.ShouldProcess($destPath, 'Copy Pester NUnit3 XML')) {
                        Copy-Item -Path $sourcePath -Destination $destPath -Force
                        $savedFiles += $destPath
                        Write-Verbose "Copied Pester NUnit3 XML from: $sourcePath to: $destPath"
                    }
                }
                else {
                    Write-Warning "Pester XML not found at configured output path: $sourcePath"
                }
            }
            # Save orchestration report JSON
            if ($OrchestrationReportJson) {
                $jsonPath = Join-Path $ArtifactPath 'orchestration-report.json'
                if ($PSCmdlet.ShouldProcess($jsonPath, 'Save JSON report')) {
                    $OrchestrationReportJson | Out-File -FilePath $jsonPath -Encoding utf8 -Force
                    $savedFiles += $jsonPath
                    Write-Verbose "Saved orchestration report JSON: $jsonPath"
                }
            }
            # Save orchestration report Markdown
            if ($OrchestrationReportMarkdown) {
                $mdPath = Join-Path $ArtifactPath 'orchestration-report.md'
                if ($PSCmdlet.ShouldProcess($mdPath, 'Save Markdown report')) {
                    $OrchestrationReportMarkdown | Out-File -FilePath $mdPath -Encoding utf8 -Force
                    $savedFiles += $mdPath
                    Write-Verbose "Saved orchestration report Markdown: $mdPath"
                }
            }
            return [PSCustomObject]@{
                ArtifactPath = $ArtifactPath
                SavedFiles = $savedFiles
                Count = $savedFiles.Count
            }
        }
        catch {
            Write-Error "Failed to save test execution artifacts: $_"
            throw
        }
    }
}
function Save-EnvironmentBaselineArtifacts {
    <#
    .SYNOPSIS
        Saves environment baseline artifacts (manifest snapshots).
    .DESCRIPTION
        Stores manifest-snapshot.json in the environment-baseline directory.
        Represents the desired state at the time of validation.
    .PARAMETER ArtifactPath
        Path to environment-baseline artifact directory (from New-ArtifactDirectory).
    .PARAMETER Manifest
        The manifest object to save as snapshot.
    .EXAMPLE
        Save-EnvironmentBaselineArtifacts -ArtifactPath $paths.EnvironmentBaselinePath -Manifest $manifest
    .OUTPUTS
        PSCustomObject with saved file path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactPath,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Manifest
    )
    process {
        try {
            $snapshotPath = Join-Path $ArtifactPath 'manifest-snapshot.json'
            if ($PSCmdlet.ShouldProcess($snapshotPath, 'Save manifest snapshot')) {
                $manifestJson = $Manifest | ConvertTo-Json -Depth 100
                $manifestJson | Out-File -FilePath $snapshotPath -Encoding utf8 -Force
                Write-Verbose "Saved manifest snapshot: $snapshotPath"
            }
            return [PSCustomObject]@{
                ArtifactPath = $ArtifactPath
                SnapshotPath = $snapshotPath
            }
        }
        catch {
            Write-Error "Failed to save environment baseline artifacts: $_"
            throw
        }
    }
}
#endregion
# Export module members
Export-ModuleMember -Function @(
    'New-ArtifactDirectory'
    'Save-TestExecutionArtifacts'
    'Save-EnvironmentBaselineArtifacts'
)