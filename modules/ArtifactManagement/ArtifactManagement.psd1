@{
    RootModule = 'ArtifactManagement.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c3d4e5f6-a7b8-4901-c234-56789abcdef0'
    Author = 'Radar Live Post-Install Skim Team'
    CompanyName = 'Unknown'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Artifact management module for Radar Live Post-Install Skim. Manages storage of test execution and environment baseline artifacts.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @(
        'New-ArtifactDirectory'
        'Save-TestExecutionArtifacts'
        'Save-EnvironmentBaselineArtifacts'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Radar', 'Artifacts', 'Storage', 'PostInstall')
            ProjectUri = 'https://github.com/khaledm/radar-postinstall-skim'
        }
    }
}
