#Requires -Modules Pester
#Requires -Version 7.5
<#
.SYNOPSIS
    IIS configuration validation tests for Radar Live Post-Install Skim.
.DESCRIPTION
    Validates Windows features, IIS sites, and AppPool configurations.
#>
# Initialize script variables for discovery phase
$script:IISConfig = @{ RequiredWindowsFeatures = @(); Sites = @(); AppPools = @() }
BeforeAll {
    param($Manifest)
    # Import required modules
    Import-Module "$PSScriptRoot\..\modules\ManifestValidation\ManifestValidation.psd1" -Force
    # Manifest will be passed via -Data parameter in orchestrator
    if ($Manifest) {
        $script:Manifest = $Manifest
        $script:IISConfig = $script:Manifest.IISConfig
        $script:GMSInUse = $script:Manifest.GMSInUse
    }
}
Describe 'IIS Configuration Validation' {
    Context 'Windows Features Validation' {
        It 'Should validate required Windows feature <_> is installed' -ForEach $script:IISConfig.RequiredWindowsFeatures {
            # T701: Windows feature validation
            $featureName = $_
            $feature = Get-WindowsFeature -Name $featureName -ErrorAction SilentlyContinue
            $feature | Should -Not -BeNullOrEmpty -Because "Windows feature '$featureName' not found. Verify feature name is correct for this Windows Server version."
            $feature.Installed | Should -BeTrue -Because "Windows feature '$featureName' not installed (Install State: $($feature.InstallState)). Run: Install-WindowsFeature -Name '$featureName' -IncludeManagementTools"
        }
    }
    Context 'IIS Sites Validation' {
        It 'Should validate IIS site <Name> exists, is running, and bound to port <Port>' -ForEach $script:IISConfig.Sites {
            # T702: IIS site validation
            $siteName = $_.Name
            $expectedPort = $_.Port
            $site = Get-Website -Name $siteName -ErrorAction SilentlyContinue
            $site | Should -Not -BeNullOrEmpty -Because "IIS site '$siteName' not found. Verify IIS configuration and component deployment completed. Run: Get-Website to list all sites."
            $site.State | Should -Be 'Started' -Because "IIS site '$siteName' is in state '$($site.State)'. Expected: Started. Run: Start-Website -Name '$siteName' to start the site."
            # Validate port binding
            $bindings = $site.Bindings.Collection | Where-Object { $_.Protocol -in @('http', 'https') }
            $ports = $bindings | ForEach-Object {
                if ($_.BindingInformation -match ':(\d+):') {
                    [int]$matches[1]
                }
            }
            $ports | Should -Contain $expectedPort -Because "IIS site '$siteName' port binding mismatch. Expected port: $expectedPort, Actual ports: $($ports -join ', '). Verify site bindings in IIS Manager or manifest configuration."
        }
    }
    Context 'AppPool Validation' {
        It 'Should validate AppPool <_> exists and uses gMSA identity' -ForEach $script:IISConfig.AppPools {
            # T703: AppPool validation with gMSA identity check
            $appPoolName = $_
            $appPool = Get-Item "IIS:\AppPools\$appPoolName" -ErrorAction SilentlyContinue
            $appPool | Should -Not -BeNullOrEmpty -Because "AppPool '$appPoolName' not found. Verify IIS configuration. Run: Get-ChildItem 'IIS:\AppPools' to list all AppPools."
            $appPool.State | Should -Be 'Started' -Because "AppPool '$appPoolName' is in state '$($appPool.State)'. Expected: Started. Run: Start-WebAppPool -Name '$appPoolName' to start the AppPool."
            # Validate gMSA identity
            $identity = $appPool.ProcessModel.IdentityType
            $userName = $appPool.ProcessModel.UserName
            if ($identity -eq 'SpecificUser') {
                $userName | Should -Be $script:GMSInUse -Because "AppPool '$appPoolName' identity mismatch. Expected: '$($script:GMSInUse)', Actual: '$userName'. Reconfigure AppPool identity."
            }
            elseif ($identity -eq 'ApplicationPoolIdentity') {
                Set-ItResult -Failed -Because "AppPool '$appPoolName' identity mismatch. Expected: gMSA '$($script:GMSInUse)', Actual: ApplicationPoolIdentity (built-in). Run: Set-ItemProperty 'IIS:\AppPools\$appPoolName' -Name processModel.identityType -Value SpecificUser; Set-ItemProperty 'IIS:\AppPools\$appPoolName' -Name processModel.userName -Value '$($script:GMSInUse)'"
            }
            else {
                Set-ItResult -Failed -Because "AppPool '$appPoolName' identity mismatch. Expected: gMSA '$($script:GMSInUse)', Actual: $identity (identity type). Reconfigure AppPool to use SpecificUser with gMSA identity."
            }
        }
    }
}