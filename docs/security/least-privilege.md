# Least Privilege Criteria for Radar Live Post-Install Skim
**Version**: 1.0.0
**Date**: 2025-11-30
**Status**: Draft
**Constitutional Reference**: `.specify/memory/constitution.md` Section III (Non-Functional Requirements)
## Purpose
This document defines measurable least privilege criteria for all PowerShell checks and modules in the Radar Live Post-Install Skim. All implementation must comply with these criteria to ensure minimal security exposure during validation operations.
## Principle
The skim must run with the **minimum permissions required** to perform its validation checks. Execution contexts requesting or possessing excessive privileges constitute a security violation and must result in a FAIL.
## Disallowed Roles and Privileges
### Windows Roles (Must NOT Run As)
The skim **MUST NOT** execute under any of the following elevated contexts:
- `BUILTIN\Administrators` (local admin group membership)
- `Domain Admins`
- `Enterprise Admins`
- `Schema Admins`
- Any custom administrative role with `SeDebugPrivilege`, `SeTakeOwnershipPrivilege`, or `SeLoadDriverPrivilege`
### Disallowed PowerShell Cmdlets
The following cmdlets are **prohibited** in skim modules unless explicitly documented with a security exception approval:
#### System Modification (Always Prohibited)
- `Set-*` cmdlets that modify system state (e.g., `Set-Service`, `Set-ItemProperty`, `Set-ExecutionPolicy`)
- `New-*` cmdlets that create resources (e.g., `New-Service`, `New-LocalUser`, `New-Item` in protected paths)
- `Remove-*` cmdlets (e.g., `Remove-Item`, `Remove-Service`)
- `Stop-*` / `Start-*` / `Restart-*` (service/process manipulation)
- `Enable-*` / `Disable-*` (feature/configuration changes)
- `Install-*` / `Uninstall-*` (software installation)
#### Credential/Secrets Access (Always Prohibited)
- `Get-Credential` (interactive credential prompt)
- `ConvertFrom-SecureString` without encryption
- `Export-Clixml` / `Import-Clixml` for credential objects
- Any cmdlet accessing DPAPI user keys without explicit justification
#### Dangerous Operations (Always Prohibited)
- `Invoke-Expression` (arbitrary code execution)
- `Invoke-Command` with `-ScriptBlock` from untrusted sources
- `Add-Type` with unsafe C# code
- Direct COM object manipulation (`New-Object -ComObject`) without security review
### Allowed Read-Only Cmdlets
The skim **SHOULD** limit operations to read-only information gathering:
#### Approved for General Use
- `Get-*` cmdlets for querying state (e.g., `Get-Service`, `Get-Process`, `Get-Item`, `Get-Content`)
- `Test-*` cmdlets for validation (e.g., `Test-Path`, `Test-Connection`, `Test-NetConnection`)
- `Resolve-DnsName` (DNS queries)
- `Invoke-WebRequest` with `-Method Get` (health endpoint checks)
- `Get-WindowsFeature` (IIS feature validation)
- `Get-IISAppPool`, `Get-IISSite` (IIS configuration queries)
- `Invoke-Sqlcmd` with **read-only** SELECT queries (requires validation; see below)
#### SQL Access Constraints
- SQL queries **MUST** be SELECT-only (no INSERT, UPDATE, DELETE, DROP, ALTER, EXEC, or stored procedure calls)
- Connection strings **MUST** use application intent `ReadOnly` where supported
- SQL login used **SHOULD** have `db_datareader` role only (no `db_owner`, `db_ddladmin`, or `sysadmin`)
#### IIS Access Constraints
- IIS queries **MUST** be read-only via `Get-*` cmdlets
- No AppPool recycling, site start/stop, or configuration changes permitted
## Required Execution Context
### Minimum Required Permissions
The skim execution account **MUST** have:
1. **Local Read Access**:
   - Read access to IIS configuration (`IIS:\AppPools`, `IIS:\Sites`)
   - Read access to event logs (Security, Application, System)
   - Read access to registry keys for version detection (`HKLM:\SOFTWARE\Microsoft`)
   - Read access to file system paths specified in manifest (`expectedInstallPath`, config files)
2. **Network Access**:
   - DNS resolution capability (no firewall block)
   - Outbound TCP access to SQL Server ports (default 1433)
   - Outbound HTTP/HTTPS to health endpoints
3. **SQL Server Access**:
   - SQL login with `CONNECT` permission
   - `db_datareader` role on target databases (or equivalent SELECT-only permissions)
   - No `sysadmin`, `securityadmin`, or `db_owner` required
### Recommended Execution Identity
- **gMSA (Group Managed Service Account)** with minimal permissions (preferred)
- Standard domain user account with read-only access (acceptable)
- **NEVER** use accounts with administrative privileges
## Validation Strategy
### Automated Scan (T117)
The `modules/SecretRedaction/SecretRedaction.psm1 (contains security validation)` module implements automated detection:
1. **Context Check**: Verify current execution context is not in disallowed roles
2. **Script Analysis**: Parse all `.psm1` and `.ps1` files for disallowed cmdlets
3. **AST Inspection**: Use PowerShell AST to detect dynamic command construction
### Code Review Checklist (T110)
All pull requests introducing new checks **MUST** complete this checklist:
- [ ] No cmdlets from disallowed list are used
- [ ] All operations are idempotent (can run multiple times safely)
- [ ] No system state modification occurs
- [ ] SQL queries (if any) are SELECT-only
- [ ] IIS access (if any) is read-only via `Get-*` cmdlets
- [ ] Secrets/credentials are never logged or persisted
- [ ] Execution context requirements documented in module header
## Security Exceptions
Any deviation from these criteria **MUST**:
1. Be documented in a `SECURITY_EXCEPTION.md` file in the module directory
2. Include explicit justification and risk assessment
3. Be approved by project lead and security reviewer
4. Reference the specific constitution or compliance requirement necessitating the exception
## Enforcement
- **Pre-commit**: Linters and static analysis (T501) scan for disallowed cmdlets
- **CI Pipeline**: Automated least privilege scan (T117) runs on every commit (T502)
- **Runtime**: Skim validates its own execution context at startup and FAILs if excessive privileges detected
## References
- Constitution: `.specify/memory/constitution.md` Section III (Non-Functional Requirements)
- Task T110: Implement least privilege validation
- Task T116: This document (least privilege criteria definition)
- Task T117: Automated least privilege scan logic
- Task T601: Terminology standardization
## Revision History
| Version | Date       | Author | Changes                          |
|---------|------------|--------|----------------------------------|
| 1.0.0   | 2025-11-30 | Team   | Initial least privilege criteria |