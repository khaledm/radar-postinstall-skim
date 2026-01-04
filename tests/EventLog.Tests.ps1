#Requires -Modules Pester
#Requires -Version 7.5
<#
.SYNOPSIS
    Event log validation tests for Radar Live Post-Install Skim.
.DESCRIPTION
    Scans event logs for errors and warnings, classifies by criticality.
#>
# Initialize script variables for discovery phase
$script:EventLogConfig = @{ Logs = @() }
BeforeAll {
    param($Manifest)
    # Import required modules
    Import-Module "$PSScriptRoot\..\modules\ManifestValidation\ManifestValidation.psd1" -Force
    # Manifest will be passed via -Data parameter in orchestrator
    if ($Manifest) {
        $script:Manifest = $Manifest
        $script:EventLogConfig = $script:Manifest.EventLogConfig
    }
}
Describe 'Event Log Validation' {
    Context 'Event Log Scan' {
        It 'Should scan <LogName> event log for critical errors' -ForEach $script:EventLogConfig.Logs {
            # T1001: Event log scanning
            $logName = $_.LogName
            $scanWindowMinutes = $_.ScanWindowMinutes ?? 60
            $after = (Get-Date).AddMinutes(-$scanWindowMinutes)
            $errors = Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Level = @(1, 2)  # Critical, Error
                StartTime = $after
            } -ErrorAction SilentlyContinue
            # Non-critical test: Collect errors but don't fail (classification in next test)
            if ($errors) {
                Write-Verbose "Found $($errors.Count) critical/error events in '$logName' log"
                $errors.Count | Should -BeLessThan 1000 -Because "Event log '$logName' should not have excessive errors (>1000)"
            }
        }
    }
    Context 'Event Severity Classification' {
        It 'Should classify errors from <LogName> by severity and filter known issues' -ForEach $script:EventLogConfig.Logs {
            # T1002: Error classification
            $logName = $_.LogName
            $scanWindowMinutes = $_.ScanWindowMinutes ?? 60
            $excludeProviders = $_.ExcludeProviders ?? @()
            $after = (Get-Date).AddMinutes(-$scanWindowMinutes)
            $errors = Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Level = @(1, 2)  # Critical, Error
                StartTime = $after
            } -ErrorAction SilentlyContinue
            if ($errors) {
                # Filter out excluded providers (known benign errors)
                $filteredErrors = $errors | Where-Object {
                    $_.ProviderName -notin $excludeProviders
                }
                if ($filteredErrors) {
                    Write-Warning "Found $($filteredErrors.Count) unfiltered errors in '$logName' log"
                    $filteredErrors | ForEach-Object {
                        Write-Verbose "  - $($_.TimeCreated): [$($_.ProviderName)] $($_.Message)"
                    }
                }
                # Non-critical: Just warn, don't fail validation
                $filteredErrors.Count | Should -BeLessThan 100 -Because "Event log '$logName' should not have excessive unfiltered errors (>100)"
            }
        }
    }
}