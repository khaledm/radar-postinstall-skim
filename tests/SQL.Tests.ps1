#Requires -Modules Pester
#Requires -Version 7.5
<#
.SYNOPSIS
    SQL connectivity validation tests for Radar Live Post-Install Skim.
.DESCRIPTION
    Validates SQL DNS resolution, port connectivity, and database connections.
#>
# Initialize script variables for discovery phase
$script:SQLConfig = @{ Servers = @() }
BeforeAll {
    param($Manifest)
    # Import required modules
    Import-Module "$PSScriptRoot\..\modules\ManifestValidation\ManifestValidation.psd1" -Force
    Import-Module "$PSScriptRoot\..\modules\PesterInvocation\PesterInvocation.psd1" -Force
    # Manifest will be passed via -Data parameter in orchestrator
    if ($Manifest) {
        $script:Manifest = $Manifest
        $script:SQLConfig = $script:Manifest.SQLConfig
    }
}
Describe 'SQL Configuration Validation' {
    Context 'SQL Connection Validation' {
        It 'Should validate SQL server <ServerInstance> is reachable' -ForEach $script:SQLConfig.Servers {
            # T801: SQL DNS validation
            $serverInstance = $_.ServerInstance
            # Extract hostname from instance (handle SERVER\INSTANCE format)
            $hostname = if ($serverInstance -match '^([^\\]+)') {
                $matches[1]
            } else {
                $serverInstance
            }
            # Resolve DNS
            $resolved = Resolve-DnsName -Name $hostname -ErrorAction SilentlyContinue
            $resolved | Should -Not -BeNullOrEmpty -Because "SQL server hostname '$hostname' DNS resolution failed. Verify hostname is correct and DNS server is reachable. Run: nslookup $hostname"
            # Validate IP address returned
            $ipAddress = $resolved | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
            $ipAddress.IPAddress | Should -Not -BeNullOrEmpty -Because "SQL server '$hostname' DNS resolution returned no A records. Verify DNS configuration and that host has IPv4 address registered."
        }
    }
    Context 'Port Connectivity Validation' {
        It 'Should validate SQL server <ServerInstance> port <Port> connectivity' -ForEach $script:SQLConfig.Servers {
            # T802: SQL port validation
            $serverInstance = $_.ServerInstance
            $port = $_.Port ?? 1433  # Default SQL Server port
            # Extract hostname from instance
            $hostname = if ($serverInstance -match '^([^\\]+)') {
                $matches[1]
            } else {
                $serverInstance
            }
            # Test TCP connection
            $tcpClient = $null
            try {
                $tcpClient = [System.Net.Sockets.TcpClient]::new()
                $connection = $tcpClient.BeginConnect($hostname, $port, $null, $null)
                $success = $connection.AsyncWaitHandle.WaitOne(5000, $false)  # 5s timeout
                if ($success) {
                    $tcpClient.EndConnect($connection)
                }
                $success | Should -BeTrue -Because "SQL server '$hostname' port $port not reachable (connection timeout after 5s). Verify: 1) SQL Server service running, 2) TCP/IP enabled in SQL Configuration Manager, 3) Firewall allows port $port, 4) Network connectivity. Run: Test-NetConnection -ComputerName $hostname -Port $port"
            }
            finally {
                if ($tcpClient) {
                    $tcpClient.Close()
                    $tcpClient.Dispose()
                }
            }
        }
    }
    Context 'Connection Validation' {
        It 'Should validate SQL database connection to <ServerInstance>\<Database> with gMSA' -ForEach $script:SQLConfig.Servers {
            # T803: SQL connection validation with retry logic
            $serverInstance = $_.ServerInstance
            $database = $_.Database
            $timeoutSeconds = 5
            # Use retry logic from PesterInvocation module
            $result = Test-SqlConnectionWithRetry `
                -ServerInstance $serverInstance `
                -Database $database `
                -IntegratedSecurity $true `
                -TimeoutSeconds $timeoutSeconds
            $result.IsConnected | Should -BeTrue -Because "SQL connection to '$serverInstance\$database' failed with Integrated Security (gMSA). Error: $($result.ErrorMessage). Verify: 1) Database exists, 2) gMSA '$($script:GMSInUse)' has login rights on SQL Server, 3) Database permissions granted. Run: SELECT name FROM sys.databases WHERE name='$database'; SELECT name FROM sys.server_principals WHERE name='$($script:GMSInUse)';"
            $result.ServerVersion | Should -Not -BeNullOrEmpty -Because "SQL server version query failed for '$serverInstance'. Connection succeeded but unable to retrieve metadata. Verify VIEW SERVER STATE permission for gMSA."
        }
    }
}