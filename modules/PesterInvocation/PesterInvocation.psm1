#Requires -Version 7.5
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester invocation module for Radar Live Post-Install Skim.
.DESCRIPTION
    Wraps Pester execution with retry logic for health checks and SQL connections.
    Implements exponential backoff per spec.md (2 retries, 1s/2s delays).
.NOTES
    Module follows PowerShell 7.5+ best practices.
    Requires Pester 5.0+ for NUnit3 XML output support.
#>
using namespace System.Net.Http
using namespace System.Data.SqlClient
#region Public Functions
function Invoke-PesterWithRetry {
    <#
    .SYNOPSIS
        Executes Pester tests with NUnit3 XML output format.
    .DESCRIPTION
        Invokes Pester with -Output PassThru and -OutputFormat NUnit3.
        Returns Pester result object for further processing.
    .PARAMETER Path
        Path to Pester test file or directory.
    .PARAMETER OutputPath
        Path to save NUnit3 XML output file.
    .PARAMETER TagFilter
        Optional tag filter for test execution.
    .PARAMETER Container
        Optional Pester container for advanced test configuration.
    .EXAMPLE
        $result = Invoke-PesterWithRetry -Path '.\tests' -OutputPath '.\pester-results.xml'
    .OUTPUTS
        Pester test result object.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        [Parameter()]
        [string[]]$TagFilter,
        [Parameter()]
        [object]$Container
    )
    process {
        try {
            Write-Verbose "Executing Pester tests from: $Path"
            # Build Pester configuration
            $pesterConfig = @{
                Run = @{
                    Path = $Path
                    PassThru = $true
                }
                Output = @{
                    Verbosity = 'Detailed'
                }
                TestResult = @{
                    Enabled = $true
                    OutputPath = $OutputPath
                    OutputFormat = 'NUnit3'
                }
            }
            if ($TagFilter) {
                $pesterConfig.Filter = @{
                    Tag = $TagFilter
                }
            }
            # Use container if provided (for advanced scenarios)
            if ($Container) {
                $pesterConfig.Run.Container = $Container
            }
            # Convert to Pester configuration object
            $config = New-PesterConfiguration -Hashtable $pesterConfig
            # Execute Pester
            $result = Invoke-Pester -Configuration $config
            Write-Verbose "Pester execution completed. Total: $($result.TotalCount), Passed: $($result.PassedCount), Failed: $($result.FailedCount)"
            return $result
        }
        catch {
            Write-Error "Failed to execute Pester tests: $_"
            throw
        }
    }
}
function Invoke-HealthCheckWithRetry {
    <#
    .SYNOPSIS
        Invokes HTTP/HTTPS health check endpoint with retry logic.
    .DESCRIPTION
        Performs GET request to health endpoint with exponential backoff retry.
        Per spec.md: 2 retries with 1s/2s delays.
    .PARAMETER Uri
        Health check endpoint URI (HTTP/HTTPS).
    .PARAMETER TimeoutSeconds
        Request timeout in seconds (default 5).
    .PARAMETER SkipCertificateCheck
        Skip SSL certificate validation (for self-signed certs).
    .PARAMETER MaxRetries
        Maximum retry attempts (default 2 per spec).
    .EXAMPLE
        $result = Invoke-HealthCheckWithRetry -Uri 'https://server/health' -TimeoutSeconds 5
    .OUTPUTS
        PSCustomObject with IsHealthy, StatusCode, ResponseTime, Attempts.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [uri]$Uri,
        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 5,
        [Parameter()]
        [switch]$SkipCertificateCheck,
        [Parameter()]
        [ValidateRange(0, 5)]
        [int]$MaxRetries = 2
    )
    process {
        $attempt = 0
        $delaySeconds = 1
        $isHealthy = $false
        $statusCode = 0
        $responseTime = 0
        $lastError = $null
        while ($attempt -le $MaxRetries) {
            $attempt++
            try {
                Write-Verbose "Health check attempt $attempt of $($MaxRetries + 1): $Uri"
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                # Invoke web request with timeout
                $params = @{
                    Uri = $Uri
                    Method = 'Get'
                    TimeoutSec = $TimeoutSeconds
                    UseBasicParsing = $true
                    ErrorAction = 'Stop'
                }
                if ($SkipCertificateCheck) {
                    $params.SkipCertificateCheck = $true
                }
                $response = Invoke-WebRequest @params
                $stopwatch.Stop()
                $responseTime = $stopwatch.ElapsedMilliseconds
                $statusCode = $response.StatusCode
                # Success: 2xx status codes
                if ($statusCode -ge 200 -and $statusCode -lt 300) {
                    $isHealthy = $true
                    Write-Verbose "Health check succeeded (HTTP $statusCode) in ${responseTime}ms"
                    break
                }
            }
            catch {
                $lastError = $_
                Write-Verbose "Health check attempt $attempt failed: $($_.Exception.Message)"
                # Check if this is a transient error (timeout, connection refused, etc.)
                $isTransient = $_.Exception.Message -match '(timeout|connection|refused|unavailable|unreachable)'
                if ($attempt -le $MaxRetries -and $isTransient) {
                    Write-Verbose "Retrying after ${delaySeconds}s delay..."
                    Start-Sleep -Seconds $delaySeconds
                    $delaySeconds *= 2  # Exponential backoff: 1s -> 2s
                }
            }
        }
        return [PSCustomObject]@{
            Uri = $Uri.ToString()
            IsHealthy = $isHealthy
            StatusCode = $statusCode
            ResponseTimeMs = $responseTime
            Attempts = $attempt
            LastError = if ($lastError) { $lastError.Exception.Message } else { $null }
        }
    }
}
function Test-SqlConnectionWithRetry {
    <#
    .SYNOPSIS
        Tests SQL Server connection with retry logic.
    .DESCRIPTION
        Attempts SQL connection with exponential backoff retry.
        Per spec.md: 2 retries with 1s/2s delays for transient errors.
    .PARAMETER ServerInstance
        SQL Server instance name (e.g., 'SERVER\INSTANCE').
    .PARAMETER Database
        Database name to connect to.
    .PARAMETER IntegratedSecurity
        Use Windows integrated authentication (default true).
    .PARAMETER Username
        SQL authentication username (if IntegratedSecurity is false).
    .PARAMETER Password
        SQL authentication password (if IntegratedSecurity is false).
    .PARAMETER TimeoutSeconds
        Connection timeout in seconds (default 5).
    .PARAMETER MaxRetries
        Maximum retry attempts (default 2 per spec).
    .EXAMPLE
        $result = Test-SqlConnectionWithRetry -ServerInstance 'SERVER\INSTANCE' -Database 'MyDB'
    .OUTPUTS
        PSCustomObject with IsConnected, ServerVersion, Attempts, LastError.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerInstance,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Database,
        [Parameter()]
        [bool]$IntegratedSecurity = $true,
        [Parameter()]
        [string]$Username,
        [Parameter()]
        [securestring]$Password,
        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 5,
        [Parameter()]
        [ValidateRange(0, 5)]
        [int]$MaxRetries = 2
    )
    process {
        $attempt = 0
        $delaySeconds = 1
        $isConnected = $false
        $serverVersion = $null
        $lastError = $null
        # Build connection string
        $connStringBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
        $connStringBuilder['Data Source'] = $ServerInstance
        $connStringBuilder['Initial Catalog'] = $Database
        $connStringBuilder['Connect Timeout'] = $TimeoutSeconds
        if ($IntegratedSecurity) {
            $connStringBuilder['Integrated Security'] = $true
        }
        else {
            if (-not $Username -or -not $Password) {
                throw "Username and Password required when IntegratedSecurity is false"
            }
            $connStringBuilder['User ID'] = $Username
            $connStringBuilder['Password'] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            )
        }
        while ($attempt -le $MaxRetries) {
            $attempt++
            $connection = $null
            try {
                Write-Verbose "SQL connection attempt $attempt of $($MaxRetries + 1): $ServerInstance\$Database"
                $connection = [System.Data.SqlClient.SqlConnection]::new($connStringBuilder.ConnectionString)
                $connection.Open()
                # Get server version to confirm connection
                $serverVersion = $connection.ServerVersion
                $isConnected = $true
                Write-Verbose "SQL connection succeeded. Server version: $serverVersion"
                break
            }
            catch {
                $lastError = $_
                Write-Verbose "SQL connection attempt $attempt failed: $($_.Exception.Message)"
                # Check for transient SQL errors (error codes: -2, 2, 53, 20, 64, 233, 10053, 10054, 10060)
                $errorNumber = if ($_.Exception.InnerException -is [System.Data.SqlClient.SqlException]) {
                    $_.Exception.InnerException.Number
                } else { 0 }
                $transientErrors = @(-2, 2, 53, 20, 64, 233, 10053, 10054, 10060)
                $isTransient = $errorNumber -in $transientErrors
                if ($attempt -le $MaxRetries -and $isTransient) {
                    Write-Verbose "Transient SQL error $errorNumber detected. Retrying after ${delaySeconds}s delay..."
                    Start-Sleep -Seconds $delaySeconds
                    $delaySeconds *= 2  # Exponential backoff: 1s -> 2s
                }
            }
            finally {
                if ($connection) {
                    $connection.Dispose()
                }
            }
        }
        return [PSCustomObject]@{
            ServerInstance = $ServerInstance
            Database = $Database
            IsConnected = $isConnected
            ServerVersion = $serverVersion
            Attempts = $attempt
            LastError = if ($lastError) { $lastError.Exception.Message } else { $null }
        }
    }
}
#endregion
# Export module members
Export-ModuleMember -Function @(
    'Invoke-PesterWithRetry'
    'Invoke-HealthCheckWithRetry'
    'Test-SqlConnectionWithRetry'
)