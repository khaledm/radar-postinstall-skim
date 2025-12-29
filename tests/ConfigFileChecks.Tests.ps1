#Requires -Modules Pester
#Requires -Version 7.5

<#
.SYNOPSIS
    Config file validation tests for Radar Live Post-Install Skim.

.DESCRIPTION
    Validates config file existence and schema compliance.
#>

# Initialize script variables for discovery phase
$script:ConfigFileChecks = @{ Files = @() }

BeforeAll {
    param($Manifest)

    # Import required modules
    Import-Module "$PSScriptRoot\..\modules\ManifestValidation\ManifestValidation.psd1" -Force

    # Manifest will be passed via -Data parameter in orchestrator
    if ($Manifest) {
        $script:Manifest = $Manifest
        $script:ConfigFileChecks = $script:Manifest.ConfigFileChecks
    }
}

Describe 'Config File Validation' {
    Context 'File Existence Validation' {
        It 'Should validate config file <FilePath> exists and is readable' -ForEach $script:ConfigFileChecks.Files {
            # T1201: Config file existence validation
            $filePath = $_.FilePath

            Test-Path -Path $filePath -PathType Leaf | Should -BeTrue -Because "Config file '$filePath' not found. Verify file path is correct and component deployment completed successfully."

            # Verify file is not empty
            $fileSize = (Get-Item -Path $filePath).Length
            $fileSize | Should -BeGreaterThan 0 -Because "Config file '$filePath' is empty (0 bytes). Verify configuration file was created correctly during deployment."

            # Verify read access
            $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
            $content | Should -Not -BeNullOrEmpty -Because "Config file '$filePath' exists but cannot be read. Verify file permissions for current identity."
        }
    }

    Context 'Schema Validation' {
        It 'Should validate config file <FilePath> against JSON/XML schema' -ForEach $script:ConfigFileChecks.Files {
            # T1202: Config file schema validation
            $filePath = $_.FilePath
            $schemaPath = $_.SchemaPath

            if (-not $schemaPath) {
                Set-ItResult -Skipped -Because "No schema defined for config file '$filePath'"
            }

            # Read config file
            $configContent = Get-Content -Path $filePath -Raw

            # Determine format and validate
            if ($filePath -like '*.json' -and $schemaPath -like '*.json') {
                # JSON schema validation using Test-Json
                $schemaContent = Get-Content -Path $schemaPath -Raw
                try {
                    $isValid = Test-Json -Json $configContent -Schema $schemaContent -ErrorAction Stop
                    $isValid | Should -BeTrue -Because "Config file '$filePath' JSON schema validation failed against '$schemaPath'. Review file for missing required properties, type mismatches, or malformed JSON."
                }
                catch {
                    throw "Config file '$filePath' JSON schema validation failed. Error: $($_.Exception.Message). Verify JSON syntax and schema compliance."
                }
            }
            elseif ($filePath -like '*.xml' -and $schemaPath -like '*.xsd') {
                # XML schema validation
                $xml = [xml]$configContent
                $schemaSet = [System.Xml.Schema.XmlSchemaSet]::new()
                $schemaSet.Add($null, $schemaPath)
                $xml.Schemas = $schemaSet

                $validationErrors = @()
                $xml.Validate({
                    param($sender, $e)
                    $validationErrors += $e.Message
                })

                $validationErrors.Count | Should -Be 0 -Because "Config file '$filePath' XML schema validation failed against '$schemaPath'. Errors: $($validationErrors -join '; '). Review file for missing elements, attribute errors, or malformed XML."
            }
            else {
                Set-ItResult -Skipped -Because "Unsupported schema format for '$filePath'"
            }
        }
    }
}
