# Implementation Plan: Radar Live Post-Install Skim

**Branch**: `main` | **Date**: 2025-12-01 | **Spec**: [specs/main/spec.md](./spec.md)
**Input**: Feature specification from `specs/main/spec.md`

**Status**: Phase 1 COMPLETE (Phase 0: ✅, Phase 1: ✅, Phase 2+: READY)

## Summary

Stateless PowerShell validation tool that checks Radar Live environment readiness using Pester 5.x tests driven by JSON desired-state manifests. Reports ReadyForUse determination (boolean) based on test results with criticality-aware aggregation. Stores execution artifacts locally with ISO 8601 timestamps. No historical comparison, no stored baselines—each run validates current state independently against manifest.

## Technical Context

**Language/Version**: PowerShell 7.5+
**Primary Dependencies**: Pester 5.0+ (test framework with NUnit3 XML output)
**Storage**: Local file system (structured directories for test-execution and environment-baseline artifacts)
**Testing**: Pester 5.x with NUnit3 XML format, exponential backoff retry (2 retries, 1s/2s delays)
**Target Platform**: Windows Server (IIS, SQL, Event Logs, Windows Services validation)
**Project Type**: Single PowerShell orchestrator + Pester test suites
**Performance Goals**: <300s total runtime, <2s health endpoint response, <5s port connectivity
**Constraints**: Read-only operations, stateless design, graceful degradation on timeout, no secrets in logs
**Scale/Scope**: 3 environments (DEV/UAT/PRD), 10+ components per environment, 12 test categories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Phase 0 Check**: ✅ PASS (all 12 constitutional requirements aligned)
**Phase 1 Re-Check**: ✅ PASS (design artifacts maintain constitutional compliance)

Key alignments:
- Section III: Tests are the Product (Pester tests define validation logic, stateless, idempotent)
- Section IV: PowerShell 7.5+, Pester 5.0+ (explicit version requirements)
- Section V: Test Suite Success vs Environment Readiness separation (Pester pass/fail vs ReadyForUse determination)
- Section VII: Stateless drift detection (no historical comparison, re-run tests each validation)
- Section VIII: Artifact storage with ISO 8601 timestamps, Test Execution vs Environment Baseline categories
- Section IX: Graceful degradation (timeout enforcement, read-only, partial result persistence)
- Section X: Thresholds (health <2s, port 5s, runtime 300s, WARN 3)

See `research.md` Section 6.2 for detailed constitutional compliance verification.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
radar-postinstall-skim/
├── Invoke-PostInstallSkim.ps1         # Main orchestrator script
├── modules/
│   ├── ManifestValidation/
│   │   └── ManifestValidation.psm1   # Schema validation, manifest loading
│   ├── PesterInvocation/
│   │   └── PesterInvocation.psm1     # Pester execution with retry logic
│   ├── ResultAggregation/
│   │   └── ResultAggregation.psm1    # Criticality classification, ReadyForUse calculation
│   ├── ArtifactManagement/
│   │   └── ArtifactManagement.psm1   # Artifact storage, retention cleanup
│   └── SecretRedaction/
│       └── SecretRedaction.psm1      # Connection string redaction
├── tests/
│   ├── Component.Tests.ps1           # Component health validation (services, health endpoints)
│   ├── IIS.Tests.ps1                 # IIS configuration validation (features, sites, app pools)
│   ├── SQL.Tests.ps1                 # SQL connectivity validation (DNS, port, connection)
│   ├── Network.Tests.ps1             # Network validation (DNS resolution, port connectivity)
│   ├── EventLog.Tests.ps1            # Event log validation (error/warning detection)
│   ├── VersionChecks.Tests.ps1       # Version validation (.NET, PowerShell, modules)
│   └── ConfigFileChecks.Tests.ps1    # Config file validation (JSON/XML schema)
├── manifests/
│   ├── desired-state-manifest.dev.json
│   ├── desired-state-manifest.uat.json
│   └── desired-state-manifest.prd.json
└── .specify/
    ├── memory/
    │   ├── constitution.md           # Design principles (v1.5.0)
    │   └── context-copilot.md        # Agent context (updated Phase 1)
    └── scripts/
        └── powershell/
            ├── setup-plan.ps1        # Plan initialization
            └── update-agent-context.ps1  # Agent context updater
```

**Structure Decision**: Single project (PowerShell orchestrator + Pester test suites). No web/mobile components. Test files organized by validation category (Component, IIS, SQL, Network, etc.) matching data model entities. Modules encapsulate cross-cutting concerns (validation, invocation, aggregation, artifacts, security).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**Status**: No constitutional violations requiring justification.

All design decisions align with constitution v1.5.0:
- Stateless validation (no stored baselines, no historical comparison)
- Pester-based tests (tests are the product, no proprietary validation logic)
- Read-only operations (graceful degradation, no system modifications)
- Local file system storage (no cloud dependencies, explicit retention policy)
- Fixed retry strategy (no configurable complexity, 2 retries with exponential backoff)

See Constitution Check section above for detailed alignment verification.
