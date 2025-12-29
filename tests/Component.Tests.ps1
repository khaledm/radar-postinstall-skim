#Requires -Modules Pester
#Requires -Version 7.5

<#
.SYNOPSIS
    Component health validation tests for Radar Live Post-Install Skim.

.DESCRIPTION
    Validates component service status, installation paths, health endpoints,
    AppPool configurations, and dependency chains.
#>

# Initialize script variables for discovery phase
$script:Components = @()

BeforeAll {
    param($Manifest)

    # Import required modules
    Import-Module "$PSScriptRoot\..\modules\ManifestValidation\ManifestValidation.psd1" -Force
    Import-Module "$PSScriptRoot\..\modules\PesterInvocation\PesterInvocation.psd1" -Force

    # Manifest will be passed via -Data parameter in orchestrator
    if ($Manifest) {
        $script:Manifest = $Manifest
        $script:GMSInUse = $script:Manifest.GMSInUse

        # Get enabled components only
        $script:Components = $script:Manifest.ComponentsToDeploy | Where-Object { $_.Enabled -eq $true }
    }
}

Describe 'Component Health Validation' {

    Context 'Service Validation' {
        It 'Should validate <ComponentName> service exists and is running' -ForEach $script:Components {
            # T601: Service validation
            $serviceName = $_.ExpectedServiceName

            if (-not $serviceName) {
                Set-ItResult -Skipped -Because "Component does not have expectedServiceName defined"
            }

            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            $service | Should -Not -BeNullOrEmpty -Because "Service '$serviceName' not found. Verify component installation completed successfully."
            $service.Status | Should -Be 'Running' -Because "Service '$serviceName' is in state '$($service.Status)'. Expected: Running. Run 'Start-Service -Name $serviceName' to start the service."
        }
    }

    Context 'Installation Path Validation' {
        It 'Should validate <ComponentName> installation path exists and is accessible' -ForEach $script:Components {
            # T602: Installation path validation
            $installPath = $_.ExpectedInstallPath

            if (-not $installPath) {
                Set-ItResult -Skipped -Because "Component does not have expectedInstallPath defined"
            }

            Test-Path -Path $installPath -PathType Container | Should -BeTrue -Because "Installation path '$installPath' not found. Verify component deployment completed and path is correct in manifest."

            # Verify read access
            $access = Get-ChildItem -Path $installPath -ErrorAction SilentlyContinue
            $access | Should -Not -BeNullOrEmpty -Because "Installation path '$installPath' exists but is not accessible. Verify file system permissions for current identity."
        }
    }

    Context 'Health Endpoint Validation' {
        It 'Should validate <ComponentName> health endpoint responds successfully' -ForEach $script:Components {
            # T603: Health endpoint validation
            $healthUrl = $_.ExpectedHealthUrl

            if (-not $healthUrl) {
                Set-ItResult -Skipped -Because "Component does not have expectedHealthUrl defined"
            }

            $certificateValidation = $_.CertificateValidation ?? $true
            $successCodes = $_.HealthSuccessCodes ?? @(200)
            $timeoutSeconds = $script:Manifest.HealthTimeoutSeconds ?? 5

            # Use retry logic from PesterInvocation module
            $result = Invoke-HealthCheckWithRetry `
                -Uri $healthUrl `
                -TimeoutSeconds $timeoutSeconds `
                -SkipCertificateCheck:(-not $certificateValidation)

            $result.IsHealthy | Should -BeTrue -Because "Health endpoint '$healthUrl' returned HTTP $($result.StatusCode). Expected: $($successCodes -join '/'). Check service logs and verify component is fully initialized."
            $result.StatusCode | Should -BeIn $successCodes -Because "Health endpoint '$healthUrl' returned HTTP $($result.StatusCode). Expected: $($successCodes -join '/'). This may indicate service degradation."
        }
    }

    Context 'AppPool Validation' {
        It 'Should validate <ComponentName> AppPool exists and uses correct gMSA identity' -ForEach $script:Components {
            # T604: AppPool validation
            $expectedAppPool = $_.ExpectedAppPool

            if (-not $expectedAppPool) {
                Set-ItResult -Skipped -Because "Component does not have expectedAppPool defined"
            }

            # Query IIS AppPool configuration
            $appPool = Get-Item "IIS:\AppPools\$expectedAppPool" -ErrorAction SilentlyContinue
            $appPool | Should -Not -BeNullOrEmpty -Because "AppPool '$expectedAppPool' not found in IIS. Verify IIS configuration and component deployment."

            # Validate identity matches gMSA
            $identity = $appPool.ProcessModel.IdentityType
            $userName = $appPool.ProcessModel.UserName

            if ($identity -eq 'SpecificUser') {
                $userName | Should -Be $script:GMSInUse -Because "AppPool '$expectedAppPool' identity mismatch. Expected: '$($script:GMSInUse)', Actual: '$userName'. Update AppPool identity to use gMSA account."
            }
            elseif ($identity -eq 'ApplicationPoolIdentity') {
                Set-ItResult -Failed -Because "AppPool '$expectedAppPool' identity mismatch. Expected: gMSA '$($script:GMSInUse)', Actual: ApplicationPoolIdentity. Run: Set-ItemProperty 'IIS:\AppPools\$expectedAppPool' -Name processModel.identityType -Value SpecificUser; Set-ItemProperty 'IIS:\AppPools\$expectedAppPool' -Name processModel.userName -Value '$($script:GMSInUse)'"
            }
            else {
                Set-ItResult -Failed -Because "AppPool '$expectedAppPool' identity mismatch. Expected: gMSA '$($script:GMSInUse)', Actual: $identity. Reconfigure AppPool to use SpecificUser with gMSA identity."
            }
        }
    }

    Context 'Dependency Chain Validation' {
        It 'Should validate <ComponentName> runtime dependencies are healthy in topological order' -ForEach $script:Components {
            # T605: Dependency chain validation
            $dependencies = $_.RuntimeDependencies

            if (-not $dependencies -or $dependencies.Count -eq 0) {
                Set-ItResult -Skipped -Because "Component has no runtime dependencies"
            }

            # Validate each dependency in order
            foreach ($dependencyName in $dependencies) {
                # Find dependency component
                $depComponent = $script:Manifest.ComponentsToDeploy | Where-Object { $_.ComponentName -eq $dependencyName }

                $depComponent | Should -Not -BeNullOrEmpty -Because "Dependency '$dependencyName' not found in manifest for component '$($_.ComponentName)'. Verify manifest runtimeDependencies configuration."

                # Check dependency health: service running + health endpoint + gMSA correct
                $depServiceName = $depComponent.ExpectedServiceName
                if ($depServiceName) {
                    $depService = Get-Service -Name $depServiceName -ErrorAction SilentlyContinue
                    $depService.Status | Should -Be 'Running' -Because "Dependency chain broken: '$dependencyName' service '$depServiceName' is in state '$($depService.Status)'. Component '$($_.ComponentName)' requires this dependency to be Running."
                }

                $depHealthUrl = $depComponent.ExpectedHealthUrl
                if ($depHealthUrl) {
                    $depResult = Invoke-HealthCheckWithRetry -Uri $depHealthUrl -TimeoutSeconds 5
                    $depResult.IsHealthy | Should -BeTrue -Because "Dependency chain broken: '$dependencyName' health endpoint '$depHealthUrl' returned HTTP $($depResult.StatusCode). Component '$($_.ComponentName)' requires healthy dependencies."
                }

                $depAppPool = $depComponent.ExpectedAppPool
                if ($depAppPool) {
                    $depPool = Get-Item "IIS:\AppPools\$depAppPool" -ErrorAction SilentlyContinue
                    if ($depPool.ProcessModel.IdentityType -eq 'SpecificUser') {
                        $depPool.ProcessModel.UserName | Should -Be $script:GMSInUse -Because "Dependency chain broken: '$dependencyName' AppPool '$depAppPool' identity mismatch. Expected: '$($script:GMSInUse)', Actual: '$($depPool.ProcessModel.UserName)'."
                    }
                }
            }
        }
    }
}
