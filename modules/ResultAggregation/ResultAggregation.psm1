#Requires -Version 7.5

<#
.SYNOPSIS
    Result aggregation module for Radar Live Post-Install Skim.

.DESCRIPTION
    Aggregates Pester test results, classifies criticality, calculates ReadyForUse status,
    and generates orchestration reports per constitution Section V.

.NOTES
    Module follows PowerShell 7.5+ best practices.
    Implements ReadyForUse = (FailCount == 0) AND (WarnCount <= WarnThreshold).
#>

#region Private Variables

# Critical test patterns per constitution Section V
$script:CriticalPatterns = @(
    '*gMSA*identity*'
    '*SQL*unreachable*'
    '*service*not*running*'
    '*component*missing*'
    '*dependency*chain*'
    '*Windows*feature*missing*'
)

#endregion

#region Public Functions

function Test-IsCriticalTest {
    <#
    .SYNOPSIS
        Determines if a test is critical based on pattern matching.

    .DESCRIPTION
        Checks test name against critical patterns defined in constitution Section V.
        Critical tests trigger FAIL classification on failure.

    .PARAMETER TestName
        The full name of the Pester test.

    .EXAMPLE
        $isCritical = Test-IsCriticalTest -TestName 'Component Health: gMSA identity mismatch'

    .OUTPUTS
        Boolean indicating if test is critical.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$TestName
    )

    process {
        foreach ($pattern in $script:CriticalPatterns) {
            if ($TestName -like $pattern) {
                Write-Verbose "Test '$TestName' matched critical pattern: $pattern"
                return $true
            }
        }

        return $false
    }
}

function Get-CriticalityClassification {
    <#
    .SYNOPSIS
        Classifies Pester test results into PASS/FAIL/WARN categories.

    .DESCRIPTION
        Maps Pester test results to criticality classifications:
        - PASS: Test passed
        - FAIL: Test failed and is critical (matches critical patterns)
        - WARN: Test failed but is not critical

    .PARAMETER PesterResult
        Pester test result object from Invoke-Pester.

    .EXAMPLE
        $classification = Get-CriticalityClassification -PesterResult $pesterResult

    .OUTPUTS
        PSCustomObject with PassCount, FailCount, WarnCount, Details array.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$PesterResult
    )

    process {
        try {
            $passCount = 0
            $failCount = 0
            $warnCount = 0
            $details = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Process each test result
            foreach ($test in $PesterResult.Tests) {
                $classification = switch ($test.Result) {
                    'Passed' {
                        $passCount++
                        'PASS'
                    }
                    'Failed' {
                        $isCritical = Test-IsCriticalTest -TestName $test.ExpandedName
                        if ($isCritical) {
                            $failCount++
                            'FAIL'
                        }
                        else {
                            $warnCount++
                            'WARN'
                        }
                    }
                    'Skipped' {
                        'SKIP'
                    }
                    default {
                        'UNKNOWN'
                    }
                }

                $details.Add([PSCustomObject]@{
                    TestName = $test.ExpandedName
                    Result = $test.Result
                    Classification = $classification
                    Duration = $test.Duration
                    ErrorMessage = if ($test.ErrorRecord) { $test.ErrorRecord.Exception.Message } else { $null }
                })
            }

            Write-Verbose "Classification complete: PASS=$passCount, FAIL=$failCount, WARN=$warnCount"

            return [PSCustomObject]@{
                PassCount = $passCount
                FailCount = $failCount
                WarnCount = $warnCount
                SkipCount = $PesterResult.SkippedCount
                TotalCount = $PesterResult.TotalCount
                Details = $details.ToArray()
            }
        }
        catch {
            Write-Error "Failed to classify test results: $_"
            throw
        }
    }
}

function Get-ReadyForUse {
    <#
    .SYNOPSIS
        Calculates ReadyForUse status per constitution Section V.

    .DESCRIPTION
        ReadyForUse = (FailCount == 0) AND (WarnCount <= WarnThreshold)
        Per constitution: No critical failures and warnings within threshold.

    .PARAMETER Classification
        Classification object from Get-CriticalityClassification.

    .PARAMETER WarnThreshold
        Maximum allowed warning count (from manifest).

    .EXAMPLE
        $readyForUse = Get-ReadyForUse -Classification $classification -WarnThreshold 3

    .OUTPUTS
        PSCustomObject with ReadyForUse boolean, FailCount, WarnCount, WarnThreshold.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Classification,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$WarnThreshold
    )

    process {
        try {
            $failCount = $Classification.FailCount
            $warnCount = $Classification.WarnCount

            # Calculate ReadyForUse per constitution formula
            $readyForUse = ($failCount -eq 0) -and ($warnCount -le $WarnThreshold)

            Write-Verbose "ReadyForUse calculation: FailCount=$failCount, WarnCount=$warnCount, Threshold=$WarnThreshold, Result=$readyForUse"

            return [PSCustomObject]@{
                ReadyForUse = $readyForUse
                FailCount = $failCount
                WarnCount = $warnCount
                WarnThreshold = $WarnThreshold
                PassCount = $Classification.PassCount
                Reason = if (-not $readyForUse) {
                    if ($failCount -gt 0) {
                        "Critical failures detected ($failCount)"
                    }
                    else {
                        "Warning count ($warnCount) exceeds threshold ($WarnThreshold)"
                    }
                } else { $null }
            }
        }
        catch {
            Write-Error "Failed to calculate ReadyForUse: $_"
            throw
        }
    }
}

function New-OrchestrationReport {
    <#
    .SYNOPSIS
        Generates orchestration report in JSON and Markdown formats.

    .DESCRIPTION
        Creates comprehensive orchestration report with component health status,
        ReadyForUse calculation, and test result details.

    .PARAMETER Manifest
        The manifest object used for validation.

    .PARAMETER Classification
        Classification object from Get-CriticalityClassification.

    .PARAMETER ReadyForUse
        ReadyForUse object from Get-ReadyForUse.

    .PARAMETER ExecutionTime
        Total execution time for validation run.

    .PARAMETER ArtifactPath
        Path to test execution artifacts.

    .EXAMPLE
        $report = New-OrchestrationReport -Manifest $manifest -Classification $classification -ReadyForUse $readyForUse -ExecutionTime $duration

    .OUTPUTS
        PSCustomObject with Json and Markdown report strings.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Manifest,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Classification,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$ReadyForUse,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [timespan]$ExecutionTime,

        [Parameter()]
        [string]$ArtifactPath
    )

    process {
        try {
            # Build report object
            $reportObject = [ordered]@{
                Environment = $Manifest.EnvironmentName
                ValidationTimestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                ExecutionTimeSeconds = [math]::Round($ExecutionTime.TotalSeconds, 2)
                ReadyForUse = $ReadyForUse.ReadyForUse
                Summary = [ordered]@{
                    TotalTests = $Classification.TotalCount
                    Passed = $Classification.PassCount
                    Failed = $Classification.FailCount
                    Warned = $Classification.WarnCount
                    Skipped = $Classification.SkipCount
                    WarnThreshold = $ReadyForUse.WarnThreshold
                    Reason = $ReadyForUse.Reason
                }
                Components = @(
                    foreach ($component in $Manifest.ComponentsToDeploy) {
                        [ordered]@{
                            Name = $component.ComponentName
                            Type = $component.Type
                            Enabled = $component.Enabled
                        }
                    }
                )
                TestResults = @(
                    foreach ($detail in $Classification.Details) {
                        [ordered]@{
                            TestName = $detail.TestName
                            Result = $detail.Result
                            Classification = $detail.Classification
                            DurationMs = [math]::Round($detail.Duration.TotalMilliseconds, 2)
                            ErrorMessage = $detail.ErrorMessage
                        }
                    }
                )
            }

            if ($ArtifactPath) {
                $reportObject.ArtifactPath = $ArtifactPath
            }

            # Generate JSON report
            $jsonReport = $reportObject | ConvertTo-Json -Depth 100

            # Generate Markdown report
            $mdReport = @"
# Radar Live Post-Install Skim - Orchestration Report

## Environment: $($Manifest.EnvironmentName)

**Validation Timestamp:** $($reportObject.ValidationTimestamp)
**Execution Time:** $($reportObject.ExecutionTimeSeconds)s
**Ready For Use:** $($ReadyForUse.ReadyForUse -eq $true ? '✅ YES' : '❌ NO')

$(if ($ReadyForUse.Reason) { "**Reason:** $($ReadyForUse.Reason)" })

---

## Summary

| Metric | Count |
|--------|-------|
| **Total Tests** | $($Classification.TotalCount) |
| **Passed** | $($Classification.PassCount) |
| **Failed (Critical)** | $($Classification.FailCount) |
| **Warned (Non-Critical)** | $($Classification.WarnCount) |
| **Skipped** | $($Classification.SkipCount) |
| **Warn Threshold** | $($ReadyForUse.WarnThreshold) |

---

## Components

$(foreach ($component in $Manifest.ComponentsToDeploy) {
"- **$($component.ComponentName)** ($($component.Type)) - $(if ($component.Enabled) { 'Enabled' } else { 'Disabled' })"
})

---

## Test Results

| Test Name | Result | Classification | Duration (ms) |
|-----------|--------|----------------|---------------|
$(foreach ($detail in $Classification.Details) {
"| $($detail.TestName) | $($detail.Result) | $($detail.Classification) | $([math]::Round($detail.Duration.TotalMilliseconds, 2)) |"
})

---

$(if ($ArtifactPath) { "**Artifacts:** ``$ArtifactPath``" })

*Generated by Radar Live Post-Install Skim*
"@

            Write-Verbose "Orchestration report generated successfully"

            return [PSCustomObject]@{
                Json = $jsonReport
                Markdown = $mdReport
                Object = $reportObject
            }
        }
        catch {
            Write-Error "Failed to generate orchestration report: $_"
            throw
        }
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Test-IsCriticalTest'
    'Get-CriticalityClassification'
    'Get-ReadyForUse'
    'New-OrchestrationReport'
)
