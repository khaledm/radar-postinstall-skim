#Requires -Modules Pester
#Requires -Version 7.5

<#
.SYNOPSIS
    Version validation tests for Radar Live Post-Install Skim.

.DESCRIPTION
    Validates .NET Hosting Bundle, PowerShell, and PowerShell module versions.
#>

# Initialize script variables for discovery phase
$script:VersionConfig = @{ RequiredDotNetVersions = @(); RequiredModules = @() }

BeforeAll {
    param($Manifest)

    # Import required modules
    Import-Module "$PSScriptRoot\..\modules\ManifestValidation\ManifestValidation.psd1" -Force

    # Manifest will be passed via -Data parameter in orchestrator
    if ($Manifest) {
        $script:Manifest = $Manifest
        $script:VersionConfig = $script:Manifest.VersionConfig
    }
}

Describe 'Version Checks Validation' {
    Context '.NET Hosting Bundle Validation' {
        It 'Should validate .NET Hosting Bundle version <_> is installed' -ForEach $script:VersionConfig.RequiredDotNetVersions {
            # T1101: .NET Hosting Bundle validation
            $requiredVersion = $_

            # Query registry for .NET Hosting Bundle versions
            $netHostingKeys = Get-ChildItem 'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App' -ErrorAction SilentlyContinue

            if (-not $netHostingKeys) {
                Set-ItResult -Failed -Because ".NET Hosting Bundle not installed (registry key not found). Download and install from: https://dotnet.microsoft.com/download/dotnet"
            }

            $installedVersions = $netHostingKeys | Get-ItemProperty -Name Version -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Version
            $installedVersions | Should -Contain { $_ -like "$requiredVersion*" } -Because ".NET Hosting Bundle version mismatch. Required: $requiredVersion.x, Installed: $($installedVersions -join ', '). Download correct version from: https://dotnet.microsoft.com/download/dotnet/$requiredVersion"
        }
    }

    Context 'PowerShell Version Validation' {
        It 'Should validate PowerShell version is 7.5 or higher' {
            # T1102: PowerShell version validation
            $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 7 -Because "PowerShell version mismatch. Required: 7.5+, Current: $($PSVersionTable.PSVersion). Upgrade PowerShell from: https://github.com/PowerShell/PowerShell/releases"
            if ($PSVersionTable.PSVersion.Major -eq 7) {
                $PSVersionTable.PSVersion.Minor | Should -BeGreaterOrEqual 5 -Because "PowerShell version mismatch. Required: 7.5+, Current: $($PSVersionTable.PSVersion). Upgrade to PowerShell 7.5 or later from: https://github.com/PowerShell/PowerShell/releases"
            }
        }
    }

    Context 'PowerShell Module Validation' {
        It 'Should validate required module <ModuleName> version <MinVersion>+ is available' -ForEach $script:VersionConfig.RequiredModules {
            # T1103: PowerShell module validation
            $moduleName = $_.ModuleName
            $minVersion = [version]$_.MinVersion

            $module = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
            $module | Should -Not -BeNullOrEmpty -Because "Module '$moduleName' not installed. Run: Install-Module -Name '$moduleName' -MinimumVersion $minVersion -Scope AllUsers"
            $module.Version | Should -BeGreaterOrEqual $minVersion -Because "Module '$moduleName' version mismatch. Required: $minVersion+, Installed: $($module.Version). Run: Update-Module -Name '$moduleName' or Install-Module -Name '$moduleName' -MinimumVersion $minVersion -Force"
        }
    }
}
