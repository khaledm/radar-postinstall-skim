#Requires -Version 7.5

<#
.SYNOPSIS
    Secret redaction module for Radar Live Post-Install Skim.

.DESCRIPTION
    Provides functions to redact connection strings and sensitive data from
    logs, reports, and test output. Implements constitution Section IX security requirements.

.NOTES
    Module follows PowerShell 7.5+ best practices.
    Redaction patterns per spec.md Session 2025-12-01 clarifications.
#>

using namespace System.Text.RegularExpressions

#region Private Variables

# Connection string patterns to redact
$script:RedactionPatterns = @(
    # SQL Server connection string components
    [regex]::new('Server\s*=\s*[^;]+', [RegexOptions]::IgnoreCase)
    [regex]::new('Data\s+Source\s*=\s*[^;]+', [RegexOptions]::IgnoreCase)
    [regex]::new('User\s+ID\s*=\s*[^;]+', [RegexOptions]::IgnoreCase)
    [regex]::new('Password\s*=\s*[^;]+', [RegexOptions]::IgnoreCase)
    [regex]::new('Uid\s*=\s*[^;]+', [RegexOptions]::IgnoreCase)
    [regex]::new('Pwd\s*=\s*[^;]+', [RegexOptions]::IgnoreCase)
    [regex]::new('Integrated\s+Security\s*=\s*[^;]+', [RegexOptions]::IgnoreCase)

    # LDAP connection strings
    [regex]::new('LDAP://[^;"\s]+', [RegexOptions]::IgnoreCase)

    # Complete connection strings (catch-all)
    [regex]::new('(Server|Data\s+Source|Host)\s*=[^"]+(?:Password|Pwd)\s*=[^;"]+', [RegexOptions]::IgnoreCase)
)

# Detection patterns (more sensitive - catches potential secrets)
$script:DetectionPatterns = @(
    [regex]::new('(password|pwd|secret|key|token)\s*[:=]\s*\S+', [RegexOptions]::IgnoreCase)
    [regex]::new('Server\s*=\s*[^;]+.*Password\s*=', [RegexOptions]::IgnoreCase)
)

#endregion

#region Public Functions

function Invoke-SecretRedaction {
    <#
    .SYNOPSIS
        Redacts connection strings and secrets from text.

    .DESCRIPTION
        Applies regex patterns to replace connection string components with
        placeholder text. Per spec.md, redacts: Server=, Data Source=, User ID=,
        Password=, Uid=, Pwd=, Integrated Security=, and LDAP connection strings.

    .PARAMETER InputText
        Text to redact. Can be string, array of strings, or objects (converted to string).

    .PARAMETER Placeholder
        Replacement text for redacted values. Default: '***REDACTED***'

    .EXAMPLE
        $log = "Server=sqlserver.local;User ID=sa;Password=Secret123"
        $redacted = Invoke-SecretRedaction -InputText $log
        # Output: "Server=***REDACTED***;User ID=***REDACTED***;Password=***REDACTED***"

    .OUTPUTS
        String or array of strings with secrets redacted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        $InputText,

        [Parameter()]
        [string]$Placeholder = '***REDACTED***'
    )

    process {
        if ($null -eq $InputText) {
            return $null
        }

        # Handle arrays
        if ($InputText -is [array]) {
            return $InputText | ForEach-Object { Invoke-SecretRedaction -InputText $_ -Placeholder $Placeholder }
        }

        # Convert to string if not already
        $text = if ($InputText -is [string]) {
            $InputText
        }
        else {
            $InputText | Out-String
        }

        # Apply redaction patterns
        $redacted = $text
        foreach ($pattern in $script:RedactionPatterns) {
            $redacted = $pattern.Replace($redacted, $Placeholder)
        }

        return $redacted
    }
}

function Test-ContainsSecret {
    <#
    .SYNOPSIS
        Checks if text contains unredacted secrets.

    .DESCRIPTION
        Validates that text does not contain patterns matching connection strings
        or secret values. More sensitive than Invoke-SecretRedaction to catch
        potential leaks. Returns validation result with detected patterns.

    .PARAMETER InputText
        Text to validate.

    .PARAMETER StrictMode
        If true, uses stricter detection patterns that may have false positives.
        Default: false.

    .EXAMPLE
        $output = Get-Content report.txt -Raw
        $validation = Test-ContainsSecret -InputText $output
        if (-not $validation.IsClean) {
            Write-Error "Report contains secrets: $($validation.DetectedPatterns -join ', ')"
        }

    .OUTPUTS
        PSCustomObject with validation results.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$InputText,

        [Parameter()]
        [switch]$StrictMode
    )

    process {
        if ([string]::IsNullOrWhiteSpace($InputText)) {
            return [PSCustomObject]@{
                IsClean = $true
                DetectedPatterns = @()
                MatchCount = 0
            }
        }

        $detectedPatterns = [System.Collections.Generic.List[string]]::new()
        $matchCount = 0

        # Check against detection patterns
        foreach ($pattern in $script:DetectionPatterns) {
            $patternMatches = $pattern.Matches($InputText)
            if ($patternMatches.Count -gt 0) {
                $matchCount += $patternMatches.Count

                # Record pattern description
                $patternDesc = switch -Regex ($pattern.ToString()) {
                    'password' { 'Password/Secret keywords' }
                    'Server.*Password' { 'SQL connection string with password' }
                    default { 'Sensitive data pattern' }
                }

                if ($patternDesc -notin $detectedPatterns) {
                    $detectedPatterns.Add($patternDesc)
                }
            }
        }

        # In strict mode, also check for redaction placeholder absence where expected
        if ($StrictMode) {
            # Check if text contains connection string keywords without redaction
            if ($InputText -match '(?i)(server|data\s+source)\s*=' -and
                $InputText -notmatch '\*\*\*REDACTED\*\*\*') {
                if ('Connection string without redaction' -notin $detectedPatterns) {
                    $detectedPatterns.Add('Connection string without redaction')
                    $matchCount++
                }
            }
        }

        $result = [PSCustomObject]@{
            IsClean = ($matchCount -eq 0)
            DetectedPatterns = $detectedPatterns.ToArray()
            MatchCount = $matchCount
        }

        if ($result.IsClean) {
            Write-Verbose "Secret detection: PASS (no secrets found)"
        }
        else {
            Write-Warning "Secret detection: FAIL ($matchCount potential secrets found)"
        }

        return $result
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Invoke-SecretRedaction'
    'Test-ContainsSecret'
)
