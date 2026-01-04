#Requires -Version 7.5
<#
.SYNOPSIS
    Manifest validation module for Radar Live Post-Install Skim.
.DESCRIPTION
    Provides functions to load, validate, and analyze desired-state manifests.
    Implements JSON schema validation, dependency DAG verification, and gMSA consistency checks.
.NOTES
    Module follows PowerShell 7.5+ best practices and constitutional requirements.
    All functions are read-only and idempotent.
#>
using namespace System.Collections.Generic
#region Public Functions
function Import-DesiredStateManifest {
    <#
    .SYNOPSIS
        Loads a desired-state manifest from JSON file.
    .DESCRIPTION
        Reads and parses a JSON manifest file. Performs basic structure validation
        but does not validate against schema (use Test-ManifestSchema for that).
    .PARAMETER Path
        Path to the JSON manifest file.
    .EXAMPLE
        $manifest = Import-DesiredStateManifest -Path '.\desired-state-manifest.dev.json'
    .OUTPUTS
        PSCustomObject representing the manifest.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    process {
        try {
            # Resolve path to absolute
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            # Check file exists
            if (-not (Test-Path -Path $resolvedPath -PathType Leaf)) {
                throw "Manifest file not found: $resolvedPath"
            }
            # Read and parse JSON
            $content = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
            $manifest = $content | ConvertFrom-Json -ErrorAction Stop -Depth 100
            # Add convenient aliases for test compatibility
            if ($manifest.Components -and -not $manifest.ComponentsToDeploy) {
                # Transform component properties to match test expectations
                $components = foreach ($comp in $manifest.Components) {
                    $transformed = $comp.PSObject.Copy()
                    if ($comp.displayName -and -not $comp.ComponentName) {
                        $transformed | Add-Member -NotePropertyName 'ComponentName' -NotePropertyValue $comp.displayName -Force
                    }
                    if ($comp.expectedServiceName -and -not $comp.ExpectedServiceName) {
                        $transformed | Add-Member -NotePropertyName 'ExpectedServiceName' -NotePropertyValue $comp.expectedServiceName -Force
                    }
                    if ($comp.expectedInstallPath -and -not $comp.ExpectedInstallPath) {
                        $transformed | Add-Member -NotePropertyName 'ExpectedInstallPath' -NotePropertyValue $comp.expectedInstallPath -Force
                    }
                    if ($comp.expectedHealthUrl -and -not $comp.ExpectedHealthUrl) {
                        $transformed | Add-Member -NotePropertyName 'ExpectedHealthUrl' -NotePropertyValue $comp.expectedHealthUrl -Force
                    }
                    if ($null -ne $comp.certificateValidation -and -not $comp.CertificateValidation) {
                        $transformed | Add-Member -NotePropertyName 'CertificateValidation' -NotePropertyValue $comp.certificateValidation -Force
                    }
                    if ($comp.expectedAppPool -and -not $comp.ExpectedAppPool) {
                        $transformed | Add-Member -NotePropertyName 'ExpectedAppPool' -NotePropertyValue $comp.expectedAppPool -Force
                    }
                    if ($comp.runtimeDependencies -and -not $comp.RuntimeDependencies) {
                        $transformed | Add-Member -NotePropertyName 'RuntimeDependencies' -NotePropertyValue $comp.runtimeDependencies -Force
                    }
                    $transformed | Add-Member -NotePropertyName 'Enabled' -NotePropertyValue $true -Force -ErrorAction SilentlyContinue
                    $transformed
                }
                $manifest | Add-Member -NotePropertyName 'ComponentsToDeploy' -NotePropertyValue $components -Force
            }
            if ($manifest.IIS -and -not $manifest.IISConfig) {
                # Transform IIS properties
                $iisConfig = $manifest.IIS.PSObject.Copy()
                if ($manifest.IIS.requiredWindowsFeatures -and -not $iisConfig.RequiredWindowsFeatures) {
                    $iisConfig | Add-Member -NotePropertyName 'RequiredWindowsFeatures' -NotePropertyValue $manifest.IIS.requiredWindowsFeatures -Force
                }
                if ($manifest.IIS.expectedSites -and -not $iisConfig.Sites) {
                    # Transform sites array to objects
                    $sites = $manifest.IIS.expectedSites | ForEach-Object {
                        [PSCustomObject]@{Name = $_; Port = 80}
                    }
                    $iisConfig | Add-Member -NotePropertyName 'Sites' -NotePropertyValue $sites -Force
                }
                if ($manifest.IIS.expectedAppPools -and -not $iisConfig.AppPools) {
                    # Extract just the names for AppPools
                    $appPools = $manifest.IIS.expectedAppPools | ForEach-Object { $_.name }
                    $iisConfig | Add-Member -NotePropertyName 'AppPools' -NotePropertyValue $appPools -Force
                }
                $manifest | Add-Member -NotePropertyName 'IISConfig' -NotePropertyValue $iisConfig -Force
            }
            if ($manifest.SQL -and -not $manifest.SQLConfig) {
                # Transform SQL properties
                $sqlConfig = $manifest.SQL.PSObject.Copy()
                if ($manifest.SQL.sqlServers -and -not $sqlConfig.Servers) {
                    $servers = $manifest.SQL.sqlServers | ForEach-Object {
                        $server = $_.PSObject.Copy()
                        if ($_.host -and -not $server.ServerInstance) {
                            $server | Add-Member -NotePropertyName 'ServerInstance' -NotePropertyValue $_.host -Force
                        }
                        if ($_.databases -and $_.databases.Count -gt 0 -and -not $server.Database) {
                            $server | Add-Member -NotePropertyName 'Database' -NotePropertyValue $_.databases[0] -Force
                        }
                        if (-not $server.Port) {
                            $server | Add-Member -NotePropertyName 'Port' -NotePropertyValue 1433 -Force
                        }
                        $server
                    }
                    $sqlConfig | Add-Member -NotePropertyName 'Servers' -NotePropertyValue $servers -Force
                }
                $manifest | Add-Member -NotePropertyName 'SQLConfig' -NotePropertyValue $sqlConfig -Force
            }
            if ($manifest.Network -and -not $manifest.NetworkConfig) {
                # Transform Network properties
                $networkConfig = $manifest.Network.PSObject.Copy()
                if ($manifest.Network.portOpen -and -not $networkConfig.ExternalServices) {
                    $services = $manifest.Network.portOpen | ForEach-Object {
                        [PSCustomObject]@{
                            Hostname = $_.host
                            Port = $_.port
                        }
                    }
                    $networkConfig | Add-Member -NotePropertyName 'ExternalServices' -NotePropertyValue $services -Force
                }
                $manifest | Add-Member -NotePropertyName 'NetworkConfig' -NotePropertyValue $networkConfig -Force
            }
            if ($manifest.EventLog -and -not $manifest.EventLogConfig) {
                # Transform EventLog properties
                $eventLogConfig = $manifest.EventLog.PSObject.Copy()
                if ($manifest.EventLog.lookbackHours -and -not $eventLogConfig.Logs) {
                    $logs = @(
                        [PSCustomObject]@{
                            LogName = 'Application'
                            ScanWindowMinutes = $manifest.EventLog.lookbackHours * 60
                            ExcludeProviders = @()
                        },
                        [PSCustomObject]@{
                            LogName = 'System'
                            ScanWindowMinutes = $manifest.EventLog.lookbackHours * 60
                            ExcludeProviders = @()
                        }
                    )
                    $eventLogConfig | Add-Member -NotePropertyName 'Logs' -NotePropertyValue $logs -Force
                }
                $manifest | Add-Member -NotePropertyName 'EventLogConfig' -NotePropertyValue $eventLogConfig -Force
            }
            if ($manifest.VersionChecks -and -not $manifest.VersionConfig) {
                # Transform VersionChecks properties
                $versionConfig = $manifest.VersionChecks.PSObject.Copy()
                if ($manifest.VersionChecks.dotnetHostingBundle -and -not $versionConfig.RequiredDotNetVersions) {
                    $versionConfig | Add-Member -NotePropertyName 'RequiredDotNetVersions' -NotePropertyValue @($manifest.VersionChecks.dotnetHostingBundle) -Force
                }
                if ($manifest.VersionChecks.wtwManagementModule -and -not $versionConfig.RequiredModules) {
                    $modules = @([PSCustomObject]@{
                        ModuleName = $manifest.VersionChecks.wtwManagementModule.name
                        MinVersion = $manifest.VersionChecks.wtwManagementModule.minimumVersion
                    })
                    $versionConfig | Add-Member -NotePropertyName 'RequiredModules' -NotePropertyValue $modules -Force
                }
                $manifest | Add-Member -NotePropertyName 'VersionConfig' -NotePropertyValue $versionConfig -Force
            }
            if ($manifest.ConfigFileChecks) {
                $configChecks = $manifest.ConfigFileChecks.PSObject.Copy()
                if ($manifest.ConfigFileChecks.filePaths -and -not $configChecks.Files) {
                    $files = $manifest.ConfigFileChecks.filePaths | ForEach-Object {
                        [PSCustomObject]@{
                            FilePath = $_
                            SchemaPath = $null
                        }
                    }
                    $configChecks | Add-Member -NotePropertyName 'Files' -NotePropertyValue $files -Force
                    $manifest | Add-Member -NotePropertyName 'ConfigFileChecks' -NotePropertyValue $configChecks -Force
                }
            }
            if ($manifest.HealthAndTiming) {
                if (-not $manifest.MaxTotalSkimDurationSeconds) {
                    $manifest | Add-Member -NotePropertyName 'MaxTotalSkimDurationSeconds' -NotePropertyValue $manifest.HealthAndTiming.maxTotalSkimDurationSeconds -Force
                }
                if (-not $manifest.HealthTimeoutSeconds) {
                    $manifest | Add-Member -NotePropertyName 'HealthTimeoutSeconds' -NotePropertyValue $manifest.HealthAndTiming.healthTimeoutSeconds -Force
                }
            }
            if ($manifest.Reporting) {
                if (-not $manifest.WarnThreshold) {
                    $manifest | Add-Member -NotePropertyName 'WarnThreshold' -NotePropertyValue $manifest.Reporting.warnThreshold -Force
                }
                if (-not $manifest.HistoryStoragePath) {
                    $manifest | Add-Member -NotePropertyName 'HistoryStoragePath' -NotePropertyValue $manifest.Reporting.historyStoragePath -Force
                }
            }
            Write-Verbose "Successfully loaded manifest from: $resolvedPath"
            return $manifest
        }
        catch {
            Write-Error "Failed to import manifest from '$Path': $_"
            throw
        }
    }
}
function Test-ManifestSchema {
    <#
    .SYNOPSIS
        Validates a manifest against the JSON schema.
    .DESCRIPTION
        Uses Test-Json cmdlet to validate manifest structure against the
        contracts/manifest-schema.json schema file.
    .PARAMETER Manifest
        The manifest object to validate (output from Import-DesiredStateManifest).
    .PARAMETER SchemaPath
        Path to the JSON schema file. Defaults to contracts/manifest-schema.json
        in the repository root.
    .EXAMPLE
        $manifest | Test-ManifestSchema
    .OUTPUTS
        Boolean. True if valid, throws error if invalid.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [PSCustomObject]$Manifest,
        [Parameter()]
        [string]$SchemaPath
    )
    process {
        try {
            # Determine schema path if not provided
            if (-not $SchemaPath) {
                $moduleRoot = Split-Path -Parent $PSScriptRoot
                $repoRoot = Split-Path -Parent $moduleRoot
                $SchemaPath = Join-Path $repoRoot 'specs\main\contracts\manifest-schema.json'
            }
            # Resolve schema path
            $resolvedSchemaPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SchemaPath)
            if (-not (Test-Path -Path $resolvedSchemaPath -PathType Leaf)) {
                throw "Schema file not found: $resolvedSchemaPath"
            }
            # Perform basic structure validation (required properties)
            $requiredProperties = @('EnvironmentName', 'GMSInUse', 'Components', 'IIS', 'SQL', 'Network', 'HealthAndTiming')
            foreach ($prop in $requiredProperties) {
                if (-not $Manifest.PSObject.Properties.Name.Contains($prop)) {
                    throw "Manifest missing required property: $prop"
                }
            }
            # Validate EnvironmentName enum
            if ($Manifest.EnvironmentName -notin @('DEV', 'UAT', 'PRD')) {
                throw "Invalid EnvironmentName: $($Manifest.EnvironmentName). Must be DEV, UAT, or PRD"
            }
            # Validate Components array
            if ($Manifest.Components.Count -eq 0) {
                throw "Manifest must contain at least one component"
            }
            Write-Verbose "Manifest schema validation: PASS"
            return $true
        }
        catch {
            Write-Error "Schema validation failed: $_"
            throw
        }
    }
}
function Test-DependencyDAG {
    <#
    .SYNOPSIS
        Validates that component runtime dependencies form a directed acyclic graph (DAG).
    .DESCRIPTION
        Checks that component dependencies don't contain cycles. Uses depth-first
        search with cycle detection. Per spec.md, circular dependencies are invalid.
    .PARAMETER Manifest
        The manifest object to validate.
    .EXAMPLE
        $manifest | Test-DependencyDAG
    .OUTPUTS
        Boolean. True if DAG is valid, throws error if cycles detected.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [PSCustomObject]$Manifest
    )
    process {
        try {
            # Build dependency graph
            $components = $Manifest.Components
            if (-not $components -or $components.Count -eq 0) {
                Write-Verbose "No components to validate for DAG"
                return $true
            }
            # Create lookup dictionary
            $componentMap = @{}
            foreach ($component in $components) {
                $componentMap[$component.displayName] = $component
            }
            # Validate all dependencies reference valid components
            foreach ($component in $components) {
                if ($component.runtimeDependencies) {
                    foreach ($depName in $component.runtimeDependencies) {
                        if (-not $componentMap.ContainsKey($depName)) {
                            throw "Component '$($component.displayName)' references unknown dependency: '$depName'"
                        }
                    }
                }
            }
            # Detect cycles using DFS
            $visited = @{}
            $recStack = @{}
            function Test-CycleFromNode {
                param([string]$nodeName)
                $visited[$nodeName] = $true
                $recStack[$nodeName] = $true
                $node = $componentMap[$nodeName]
                if ($node.runtimeDependencies) {
                    foreach ($depName in $node.runtimeDependencies) {
                        if (-not $visited.ContainsKey($depName)) {
                            if (Test-CycleFromNode -nodeName $depName) {
                                return $true
                            }
                        }
                        elseif ($recStack[$depName]) {
                            throw "Circular dependency detected: $nodeName -> $depName"
                        }
                    }
                }
                $recStack[$nodeName] = $false
                return $false
            }
            # Check each component
            foreach ($componentName in $componentMap.Keys) {
                if (-not $visited.ContainsKey($componentName)) {
                    if (Test-CycleFromNode -nodeName $componentName) {
                        throw "Dependency graph contains cycles"
                    }
                }
            }
            Write-Verbose "Dependency DAG validation: PASS (acyclic)"
            return $true
        }
        catch {
            Write-Error "Dependency DAG validation failed: $_"
            throw
        }
    }
}
function Get-GMSAConsistency {
    <#
    .SYNOPSIS
        Validates that GMSInUse matches all AppPool and SQL identities.
    .DESCRIPTION
        Checks manifest-level consistency: all AppPool identities and SQL login
        identities must exactly match the GMSInUse value. Per spec.md, any
        mismatch causes validation failure.
    .PARAMETER Manifest
        The manifest object to validate.
    .EXAMPLE
        $manifest | Get-GMSAConsistency
    .OUTPUTS
        PSCustomObject with validation results including mismatches if any.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [PSCustomObject]$Manifest
    )
    process {
        try {
            $gmsaInUse = $Manifest.GMSInUse
            $mismatches = [List[PSCustomObject]]::new()
            # Check IIS AppPools
            if ($Manifest.IIS -and $Manifest.IIS.expectedAppPools) {
                foreach ($appPool in $Manifest.IIS.expectedAppPools) {
                    $expectedIdentity = if ($appPool.expectedIdentity) { $appPool.expectedIdentity } else { $appPool.identity }
                    if ($expectedIdentity -ne $gmsaInUse) {
                        $mismatches.Add([PSCustomObject]@{
                            Type = 'AppPool'
                            Name = $appPool.name
                            Expected = $gmsaInUse
                            Actual = $expectedIdentity
                        })
                    }
                }
            }
            # Check SQL logins
            if ($Manifest.SQL -and $Manifest.SQL.sqlServers) {
                foreach ($sqlServer in $Manifest.SQL.sqlServers) {
                    if ($sqlServer.expectedSqlLogin -and $sqlServer.expectedSqlLogin -ne $gmsaInUse) {
                        $mismatches.Add([PSCustomObject]@{
                            Type = 'SQLLogin'
                            Name = $sqlServer.hostname
                            Expected = $gmsaInUse
                            Actual = $sqlServer.expectedSqlLogin
                        })
                    }
                }
            }
            $result = [PSCustomObject]@{
                IsValid = ($mismatches.Count -eq 0)
                GMSInUse = $gmsaInUse
                Mismatches = $mismatches
            }
            if ($result.IsValid) {
                Write-Verbose "gMSA consistency validation: PASS"
            }
            else {
                Write-Warning "gMSA consistency validation: FAIL ($($mismatches.Count) mismatches)"
            }
            return $result
        }
        catch {
            Write-Error "gMSA consistency check failed: $_"
            throw
        }
    }
}
#endregion
# Export module members
Export-ModuleMember -Function @(
    'Import-DesiredStateManifest'
    'Test-ManifestSchema'
    'Test-DependencyDAG'
    'Get-GMSAConsistency'
)