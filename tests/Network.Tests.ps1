#Requires -Modules Pester
#Requires -Version 7.5

<#
.SYNOPSIS
    Network validation tests for Radar Live Post-Install Skim.

.DESCRIPTION
    Validates DNS resolution, port connectivity, and routing checks.
#>

# Initialize script variables for discovery phase
$script:NetworkConfig = @{ dnsResolution = @(); ExternalServices = @(); routingChecks = @() }

BeforeAll {
    param($Manifest)

    # Import required modules
    Import-Module "$PSScriptRoot\..\modules\ManifestValidation\ManifestValidation.psd1" -Force

    # Manifest will be passed via -Data parameter in orchestrator
    if ($Manifest) {
        $script:Manifest = $Manifest
        $script:NetworkConfig = $script:Manifest.NetworkConfig
    }
}

Describe 'Network Validation' {
    Context 'DNS Resolution Validation' {
        It 'Should resolve DNS for external service <Hostname>' -ForEach $script:NetworkConfig.ExternalServices {
            # T901: DNS resolution validation
            $hostname = $_.Hostname

            $resolved = Resolve-DnsName -Name $hostname -ErrorAction SilentlyContinue
            $resolved | Should -Not -BeNullOrEmpty -Because "External service '$hostname' should resolve via DNS"

            # Validate IP address returned
            $ipAddress = $resolved | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
            $ipAddress.IPAddress | Should -Not -BeNullOrEmpty -Because "External service '$hostname' should have valid IP address"
        }
    }

    Context 'Port Connectivity Validation' {
        It 'Should validate external service <Hostname>:<Port> port connectivity' -ForEach $script:NetworkConfig.ExternalServices {
            # T902: Port connectivity validation
            $hostname = $_.Hostname
            $port = $_.Port

            $tcpClient = $null
            try {
                $tcpClient = [System.Net.Sockets.TcpClient]::new()
                $connection = $tcpClient.BeginConnect($hostname, $port, $null, $null)
                $success = $connection.AsyncWaitHandle.WaitOne(5000, $false)  # 5s timeout

                if ($success) {
                    $tcpClient.EndConnect($connection)
                }

                $success | Should -BeTrue -Because "External service '$hostname' should be reachable on port $port"
            }
            finally {
                if ($tcpClient) {
                    $tcpClient.Close()
                    $tcpClient.Dispose()
                }
            }
        }
    }

    Context 'Routing Checks Validation' {
        It 'Should validate network routing to external service <Hostname>' -ForEach $script:NetworkConfig.ExternalServices {
            # T903: Routing validation (traceroute-style)
            $hostname = $_.Hostname

            # Use Test-NetConnection for basic routing verification
            $result = Test-NetConnection -ComputerName $hostname -ErrorAction SilentlyContinue
            $result | Should -Not -BeNullOrEmpty -Because "Network route to '$hostname' should be testable"
            $result.PingSucceeded | Should -BeTrue -Because "External service '$hostname' should be reachable via network routing"
        }
    }
}
