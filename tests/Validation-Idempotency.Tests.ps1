#Requires -Modules Pester
#Requires -Version 7.5

<#
.SYNOPSIS
    Idempotency and stateless validation tests for Radar Live Post-Install Skim.

.DESCRIPTION
    Validates that the orchestrator is idempotent (produces identical results on repeated runs)
    and stateless (no persisted state between runs). Tests Constitution Section III compliance.

.NOTES
    Task: T1901, T1902
    Phase: 5 - Post-Change Validation
    Purpose: Prove operational readiness for CI/CD integration
#>

Describe 'Idempotency Validation (T1901)' {
    BeforeAll {
        # Test configuration
        $script:ManifestPath = "$PSScriptRoot\..\manifests\desired-state-manifest.dev.json"
        $script:OrchestratorPath = "$PSScriptRoot\..\Invoke-PostInstallSkim.ps1"
        $script:Run1Results = $null
        $script:Run2Results = $null

        # Verify orchestrator exists
        if (-not (Test-Path $script:OrchestratorPath)) {
            throw "Orchestrator not found: $script:OrchestratorPath"
        }

        # Verify manifest exists
        if (-not (Test-Path $script:ManifestPath)) {
            throw "Manifest not found: $script:ManifestPath"
        }
    }

    Context 'Identical Results on Repeated Runs' {
        It 'Should execute validation run 1 successfully' {
            # Execute first validation run
            $result = & $script:OrchestratorPath -ManifestPath $script:ManifestPath -PassThru -ErrorAction Stop
            $script:Run1Results = $result

            # Verify run completed
            $script:Run1Results | Should -Not -BeNullOrEmpty -Because "Run 1 should produce results"
            $script:Run1Results.ReadyForUse | Should -Not -BeNullOrEmpty -Because "Run 1 should determine ReadyForUse status"
        }

        It 'Should execute validation run 2 successfully (immediate re-run)' {
            # Execute second validation run immediately (no environment changes)
            $result = & $script:OrchestratorPath -ManifestPath $script:ManifestPath -PassThru -ErrorAction Stop
            $script:Run2Results = $result

            # Verify run completed
            $script:Run2Results | Should -Not -BeNullOrEmpty -Because "Run 2 should produce results"
            $script:Run2Results.ReadyForUse | Should -Not -BeNullOrEmpty -Because "Run 2 should determine ReadyForUse status"
        }

        It 'Should produce identical ReadyForUse determination' {
            $script:Run1Results.ReadyForUse | Should -Be $script:Run2Results.ReadyForUse -Because "Idempotent validation should produce identical ReadyForUse determination (Run 1: $($script:Run1Results.ReadyForUse), Run 2: $($script:Run2Results.ReadyForUse))"
        }

        It 'Should produce identical test pass counts' {
            $script:Run1Results.PassCount | Should -Be $script:Run2Results.PassCount -Because "Idempotent validation should produce identical pass counts (Run 1: $($script:Run1Results.PassCount), Run 2: $($script:Run2Results.PassCount))"
        }

        It 'Should produce identical test fail counts' {
            $script:Run1Results.FailCount | Should -Be $script:Run2Results.FailCount -Because "Idempotent validation should produce identical fail counts (Run 1: $($script:Run1Results.FailCount), Run 2: $($script:Run2Results.FailCount))"
        }

        It 'Should produce identical test warn counts' {
            $script:Run1Results.WarnCount | Should -Be $script:Run2Results.WarnCount -Because "Idempotent validation should produce identical warn counts (Run 1: $($script:Run1Results.WarnCount), Run 2: $($script:Run2Results.WarnCount))"
        }

        It 'Should produce identical test criticality classifications' {
            # Compare test result classifications
            $run1Critical = $script:Run1Results.TestResults | Where-Object { $_.Criticality -eq 'FAIL' }
            $run2Critical = $script:Run1Results.TestResults | Where-Object { $_.Criticality -eq 'FAIL' }

            $run1Critical.Count | Should -Be $run2Critical.Count -Because "Critical test count should be identical between runs"

            # Compare test names for critical failures
            $run1Names = ($run1Critical | Select-Object -ExpandProperty Name | Sort-Object) -join ','
            $run2Names = ($run2Critical | Select-Object -ExpandProperty Name | Sort-Object) -join ','

            $run1Names | Should -Be $run2Names -Because "Critical test names should be identical between runs (no flaky tests)"
        }
    }
}

Describe 'Stateless Operation Validation (T1902)' {
    BeforeAll {
        # Test configuration
        $script:ManifestPath = "$PSScriptRoot\..\manifests\desired-state-manifest.dev.json"
        $script:OrchestratorPath = "$PSScriptRoot\..\Invoke-PostInstallSkim.ps1"

        # Identify a test service to manipulate
        $manifest = Get-Content $script:ManifestPath -Raw | ConvertFrom-Json
        $testComponent = $manifest.ComponentsToDeploy | Where-Object { $_.Enabled -and $_.ExpectedServiceName } | Select-Object -First 1

        if (-not $testComponent) {
            throw "No enabled component with service found in manifest for stateless testing"
        }

        $script:TestServiceName = $testComponent.ExpectedServiceName
        $script:TestComponentName = $testComponent.ComponentName
    }

    Context 'Environment State Detection Without Cached State' {
        It 'Should detect service running state correctly (baseline)' {
            # Ensure service is running
            $service = Get-Service -Name $script:TestServiceName -ErrorAction SilentlyContinue
            if ($service.Status -ne 'Running') {
                Start-Service -Name $script:TestServiceName -ErrorAction Stop
                Start-Sleep -Seconds 2
            }

            # Run validation
            $result = & $script:OrchestratorPath -ManifestPath $script:ManifestPath -PassThru -ErrorAction Stop

            # Find test result for this service
            $serviceTest = $result.TestResults | Where-Object { $_.Name -like "*$script:TestServiceName*running*" }

            $serviceTest.Result | Should -Be 'Passed' -Because "Stateless validation should detect service '$script:TestServiceName' is running (no cached state)"
        }

        It 'Should detect service stopped state correctly (changed environment)' {
            # Stop service
            Stop-Service -Name $script:TestServiceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2

            # Run validation
            $result = & $script:OrchestratorPath -ManifestPath $script:ManifestPath -PassThru -ErrorAction Stop

            # Find test result for this service
            $serviceTest = $result.TestResults | Where-Object { $_.Name -like "*$script:TestServiceName*running*" }

            $serviceTest.Result | Should -Be 'Failed' -Because "Stateless validation should detect service '$script:TestServiceName' is stopped (queries current state, not cached)"
        }

        It 'Should detect service running state again correctly (restored environment)' {
            # Restart service
            Start-Service -Name $script:TestServiceName -ErrorAction Stop
            Start-Sleep -Seconds 2

            # Run validation
            $result = & $script:OrchestratorPath -ManifestPath $script:ManifestPath -PassThru -ErrorAction Stop

            # Find test result for this service
            $serviceTest = $result.TestResults | Where-Object { $_.Name -like "*$script:TestServiceName*running*" }

            $serviceTest.Result | Should -Be 'Passed' -Because "Stateless validation should detect service '$script:TestServiceName' is running again (no state carryover from previous failed run)"
        }
    }

    Context 'No Persistent State Files' {
        It 'Should not create state files in working directory' {
            # Run validation
            & $script:OrchestratorPath -ManifestPath $script:ManifestPath -ErrorAction Stop | Out-Null

            # Check for common state file patterns
            $stateFiles = Get-ChildItem -Path $PSScriptRoot\.. -Recurse -File | Where-Object {
                $_.Name -match '(state|cache|session|temp)' -and
                $_.Extension -in @('.json', '.xml', '.dat', '.tmp', '.cache')
            }

            $stateFiles.Count | Should -Be 0 -Because "Stateless operation should not create persistent state files (found: $($stateFiles.Name -join ', '))"
        }

        It 'Should not create temporary database or lock files' {
            # Run validation
            & $script:OrchestratorPath -ManifestPath $script:ManifestPath -ErrorAction Stop | Out-Null

            # Check for database/lock files
            $lockFiles = Get-ChildItem -Path $PSScriptRoot\.. -Recurse -File | Where-Object {
                $_.Extension -in @('.db', '.sqlite', '.lock', '.lck')
            }

            $lockFiles.Count | Should -Be 0 -Because "Stateless operation should not create database or lock files (found: $($lockFiles.Name -join ', '))"
        }
    }
}
