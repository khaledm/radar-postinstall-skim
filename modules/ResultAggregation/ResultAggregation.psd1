@{
    RootModule = 'ResultAggregation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'e5f6a7b8-c9d0-4123-e456-789abcdef012'
    Author = 'Radar Live Post-Install Skim Team'
    CompanyName = 'Unknown'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Result aggregation module for Radar Live Post-Install Skim. Classifies test results by criticality and calculates ReadyForUse determination.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @(
        'Test-IsCriticalTest'
        'Get-CriticalityClassification'
        'Get-ReadyForUse'
        'New-OrchestrationReport'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Radar', 'Results', 'Aggregation', 'PostInstall')
            ProjectUri = 'https://github.com/khaledm/radar-postinstall-skim'
        }
    }
}
