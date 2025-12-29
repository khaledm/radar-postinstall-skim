# Testing Guide for Radar Live Post-Install Skim

This guide provides comprehensive instructions for running tests locally to verify implementations.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Running Specific Test Suites](#running-specific-test-suites)
- [Test Organization](#test-organization)
- [Understanding Test Results](#understanding-test-results)
- [Troubleshooting](#troubleshooting)
- [CI/CD Integration](#cicd-integration)

---

## Prerequisites

### Required Software
- **PowerShell 7.5+**: Download from [PowerShell GitHub](https://github.com/PowerShell/PowerShell/releases)
- **Pester 5.0+**: PowerShell testing framework
- **PSScriptAnalyzer**: PowerShell linting tool

### Installation

```powershell
# Install Pester (if not already installed)
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser

# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser

# Verify installations
Get-Module -Name Pester -ListAvailable
Get-Module -Name PSScriptAnalyzer -ListAvailable
```

### Verify PowerShell Version
```powershell
$PSVersionTable.PSVersion
# Should show 7.5.0 or higher
```

---

## Quick Start

### Run All Unit Tests
```powershell
# Navigate to repository root
cd C:\path\to\radar-postinstall-skim

# Run all unit tests
Invoke-Pester -Path ./tests/unit -Output Detailed
```

### Run Tests with Coverage Report
```powershell
$config = New-PesterConfiguration
$config.Run.Path = './tests/unit'
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = './test-results.xml'

Invoke-Pester -Configuration $config
```

---

## Running Specific Test Suites

### Core Module Tests
```powershell
# Test RuntimeGuard, RetryPolicy, ResultAggregator, Snapshot
Invoke-Pester -Path ./tests/unit/Foundational.Tests.ps1 -Output Detailed
```

### Security and Validation Tests
```powershell
# WARN acknowledgment tests
Invoke-Pester -Path ./tests/unit/WarnAck.Tests.ps1 -Output Detailed

# Output semantics tests
Invoke-Pester -Path ./tests/unit/OutputSemantics.Tests.ps1 -Output Detailed
```

### Environment Readiness Tests (US1)
```powershell
# All US1 checks (IIS, SQL, Network, EventLog)
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1 -Output Detailed

# Routing check description tests
Invoke-Pester -Path ./tests/unit/RoutingCheck.Tests.ps1 -Output Detailed
```

### Artifact Retention Tests (US2)
```powershell
# Artifact storage, retention, and review
Invoke-Pester -Path ./tests/unit/Artifact.Tests.ps1 -Output Detailed
```

### Drift Detection Tests (US3)
```powershell
# Drift detection and re-scan
Invoke-Pester -Path ./tests/unit/Drift.Tests.ps1 -Output Detailed
```

### Run Specific Test Cases
```powershell
# Run only tests matching a specific name
Invoke-Pester -Path ./tests/unit -FullNameFilter "*FAIL > WARN > PASS*" -Output Detailed

# Run tests in a specific Describe block
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1 -FullNameFilter "IIS Checks*" -Output Detailed
```

---

## Test Organization

### Directory Structure
```
tests/
└── unit/
    ├── Foundational.Tests.ps1      # Core modules (RuntimeGuard, RetryPolicy, etc.)
    ├── WarnAck.Tests.ps1           # WARN acknowledgment tracking
    ├── OutputSemantics.Tests.ps1   # PASS/FAIL/WARN semantics
    ├── Checks.Tests.ps1            # US1 environment checks
    ├── RoutingCheck.Tests.ps1      # Routing description validation
    ├── Artifact.Tests.ps1          # US2 artifact retention
    └── Drift.Tests.ps1             # US3 drift detection
```

### Test Naming Convention
- **File**: `<Module>.Tests.ps1`
- **Describe**: High-level module or feature
- **Context**: Specific scenario or category
- **It**: Individual test case

Example:
```powershell
Describe 'Artifact Storage - Save-SkimArtifact' {
    Context 'Artifact creation' {
        It 'Saves artifact with timestamp and environment' {
            # Test implementation
        }
    }
}
```

---

## Understanding Test Results

### Test Output Interpretation

#### Success Output
```
Describing Artifact Storage - Save-SkimArtifact
  Context Artifact creation
    [+] Saves artifact with timestamp and environment 45ms (44ms|1ms)
    [+] Enriches artifact with metadata 32ms (31ms|1ms)

Tests completed in 2.1s
Tests Passed: 2, Failed: 0, Skipped: 0, NotRun: 0
```

#### Failure Output
```
Describing IIS Checks
  Context AppPool validation
    [-] Detects gMSA identity mismatch 123ms (120ms|3ms)
      Expected 'FAIL', but got 'PASS'
      at line: 45 in IIS.Tests.ps1

Tests completed in 3.4s
Tests Passed: 5, Failed: 1, Skipped: 0, NotRun: 0
```

### Test Status Indicators
- `[+]` - Test passed
- `[-]` - Test failed
- `[!]` - Test skipped
- `[?]` - Test not run

---

## Troubleshooting

### Common Issues

#### Issue: "Module not found"
**Solution**: Ensure modules are imported before tests run
```powershell
# Check module path
Get-Module -Name <ModuleName> -ListAvailable

# Import manually if needed
Import-Module ./src/Core/ResultAggregator.psm1 -Force
```

#### Issue: "Pester version mismatch"
**Solution**: Update Pester to version 5.0+
```powershell
# Uninstall old versions
Get-Module -Name Pester -ListAvailable | Uninstall-Module -Force

# Install latest
Install-Module -Name Pester -Force -Scope CurrentUser
```

#### Issue: "Test discovery fails"
**Solution**: Verify test file naming convention
```powershell
# Test files must end with .Tests.ps1
Get-ChildItem -Path ./tests/unit -Filter "*.Tests.ps1"
```

#### Issue: "Mock not working"
**Solution**: Ensure BeforeAll block imports modules
```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../../src/Checks/IIS.psm1" -Force
}
```

### Debugging Tests

#### Run with Verbose Output
```powershell
$config = New-PesterConfiguration
$config.Run.Path = './tests/unit/Checks.Tests.ps1'
$config.Output.Verbosity = 'Diagnostic'
Invoke-Pester -Configuration $config
```

#### Run Single Test
```powershell
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1 -FullNameFilter "IIS Checks AppPool validation Detects gMSA identity mismatch"
```

#### Enable Debug Output
```powershell
$DebugPreference = 'Continue'
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1
```

---

## Test Development Workflow

### 1. Run Existing Tests
```powershell
# Verify current state
Invoke-Pester -Path ./tests/unit -Output Detailed
```

### 2. Implement Module Logic
```powershell
# Edit module file (e.g., src/Checks/IIS.psm1)
# Implement function logic
```

### 3. Update Test Stubs
```powershell
# Edit test file (e.g., tests/unit/Checks.Tests.ps1)
# Replace TODO stubs with actual test logic
```

### 4. Run Updated Tests
```powershell
# Test specific file
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1 -Output Detailed
```

### 5. Validate with Linting
```powershell
# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

---

## Linting and Code Quality

### Run PSScriptAnalyzer
```powershell
# Analyze all PowerShell files
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .vscode/PSScriptAnalyzerSettings.psd1

# Analyze specific module
Invoke-ScriptAnalyzer -Path ./src/Checks/IIS.psm1

# Exclude specific rules
Invoke-ScriptAnalyzer -Path ./src -Recurse -ExcludeRule PSAvoidUsingWriteHost
```

### Common Linting Rules
- **PSAvoidUsingWriteHost**: Use Write-Output or Write-Verbose
- **PSUseShouldProcessForStateChangingFunctions**: Add ShouldProcess support
- **PSAvoidUsingCmdletAliases**: Use full cmdlet names
- **PSUseDeclaredVarsMoreThanAssignments**: Remove unused variables

---

## CI/CD Integration

### GitHub Actions Workflows

#### Lint Workflow (`.github/workflows/lint.yml`)
Runs on every push/PR:
- PSScriptAnalyzer checks
- Trailing whitespace detection
- File encoding validation

#### Test Workflow (`.github/workflows/test.yml`)
Runs on every push/PR:
- All Pester unit tests
- Test result upload
- Test summary reporting

#### Block on Fail Workflow (`.github/workflows/block-on-fail.yml`)
Validates:
- FAIL status detection
- WARN threshold enforcement
- ReadyForUse logic

#### Runtime Budget Workflow (`.github/workflows/runtime-budget.yml`)
Enforces:
- 5-minute total runtime budget
- 30-second per-check budget
- Constitutional compliance

### Local CI Simulation
```powershell
# Run all CI checks locally
.\scripts\run-ci-checks.ps1

# Or run individually:
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-Pester -Path ./tests/unit
```

---

## Performance Testing

### Measure Test Execution Time
```powershell
Measure-Command {
    Invoke-Pester -Path ./tests/unit -Output Quiet
}
```

### Profile Specific Tests
```powershell
$config = New-PesterConfiguration
$config.Run.Path = './tests/unit/Checks.Tests.ps1'
$config.Debug.ShowNavigationMarkers = $true

Invoke-Pester -Configuration $config
```

---

## Best Practices

### Writing Tests
1. **Arrange-Act-Assert**: Structure tests clearly
2. **One assertion per test**: Keep tests focused
3. **Mock external dependencies**: No integration tests
4. **Use descriptive names**: Test names should explain intent
5. **Test edge cases**: Include error scenarios

### Running Tests
1. **Run frequently**: After every change
2. **Run full suite**: Before commits
3. **Check coverage**: Ensure all paths tested
4. **Review failures**: Fix immediately

### Maintaining Tests
1. **Update stubs**: Convert TODOs to real tests
2. **Refactor duplication**: Use BeforeEach/AfterEach
3. **Document complex logic**: Add comments
4. **Version control**: Commit test changes with code

---

## Additional Resources

### Documentation
- [Pester Documentation](https://pester.dev/)
- [PSScriptAnalyzer Rules](https://github.com/PowerShell/PSScriptAnalyzer)
- [PowerShell Testing Best Practices](https://docs.microsoft.com/powershell/scripting/test/testing-guidelines)

### Project-Specific Docs
- `specs/main/constitution.md` - Testing requirements
- `specs/main/spec.md` - Feature specifications
- `CONTRIBUTING.md` - Contribution guidelines

---

## Quick Reference

### Essential Commands
```powershell
# Run all tests
Invoke-Pester -Path ./tests/unit

# Run specific test file
Invoke-Pester -Path ./tests/unit/Checks.Tests.ps1

# Run with detailed output
Invoke-Pester -Path ./tests/unit -Output Detailed

# Run linting
Invoke-ScriptAnalyzer -Path . -Recurse

# Generate test report
$config = New-PesterConfiguration
$config.Run.Path = './tests/unit'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = './test-results.xml'
Invoke-Pester -Configuration $config
```

### Test Execution Matrix

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `Invoke-Pester -Path ./tests/unit` | Run all unit tests | Before commits |
| `Invoke-Pester -Path <file>` | Run specific test file | During development |
| `Invoke-Pester -FullNameFilter <pattern>` | Run matching tests | Debugging specific feature |
| `Invoke-ScriptAnalyzer -Path .` | Lint all code | Before commits |
| `Invoke-ScriptAnalyzer -Path <file>` | Lint specific file | During development |

---

## Getting Help

### Test Failures
1. Read error message carefully
2. Check test expectations vs actual output
3. Verify module imports in BeforeAll
4. Run with `-Output Detailed` for more info

### Linting Errors
1. Review PSScriptAnalyzer output
2. Check rule documentation
3. Apply suggested fixes
4. Re-run to verify

### General Questions
- Review constitution.md for requirements
- Check spec.md for feature details
- Consult Pester documentation
- Ask in project discussions

---

**Last Updated**: November 30, 2025
**Version**: 1.0.0
