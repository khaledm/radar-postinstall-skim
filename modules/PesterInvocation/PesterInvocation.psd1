@{
    RootModule = 'PesterInvocation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'd4e5f6a7-b8c9-4012-d345-6789abcdef01'
    Author = 'Radar Live Post-Install Skim Team'
    CompanyName = 'Unknown'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Pester invocation module for Radar Live Post-Install Skim. Executes Pester tests with retry logic for health endpoints and SQL connections.'
    PowerShellVersion = '7.5'
    RequiredModules = @('Pester')
    FunctionsToExport = @(
        'Invoke-PesterWithRetry'
        'Invoke-HealthCheckWithRetry'
        'Test-SqlConnectionWithRetry'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Radar', 'Pester', 'Testing', 'PostInstall')
            ProjectUri = 'https://github.com/khaledm/radar-postinstall-skim'
        }
    }
}
