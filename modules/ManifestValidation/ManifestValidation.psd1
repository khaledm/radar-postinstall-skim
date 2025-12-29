@{
    RootModule = 'ManifestValidation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-4789-a012-3456789abcde'
    Author = 'Radar Live Post-Install Skim Team'
    CompanyName = 'Unknown'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Manifest validation module for Radar Live Post-Install Skim. Loads and validates desired-state manifests against JSON schema.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @(
        'Import-DesiredStateManifest'
        'Test-ManifestSchema'
        'Test-DependencyDAG'
        'Get-GMSAConsistency'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Radar', 'Validation', 'Manifest', 'PostInstall')
            ProjectUri = 'https://github.com/khaledm/radar-postinstall-skim'
        }
    }
}
