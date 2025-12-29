@{
    RootModule = 'SecretRedaction.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b2c3d4e5-f6a7-4890-b123-456789abcdef'
    Author = 'Radar Live Post-Install Skim Team'
    CompanyName = 'Unknown'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Secret redaction module for Radar Live Post-Install Skim. Redacts connection strings and sensitive data from logs and reports.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @(
        'Invoke-SecretRedaction'
        'Test-ContainsSecret'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Radar', 'Security', 'Redaction', 'PostInstall')
            ProjectUri = 'https://github.com/khaledm/radar-postinstall-skim'
        }
    }
}
