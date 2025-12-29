# Baseline Artifacts Storage

**Purpose**: Canonical storage location for Post-Install Skim baseline snapshots and historical artifacts per Constitution Section V.

**Created**: 2025-11-30
**Retention Policy**: ≥90 days (Constitution Section VIII)

## Directory Structure

```
.specify/baselines/
├── README.md           # This file
├── <env>/              # Per-environment baseline storage (DEV, UAT, PRD)
│   ├── snapshot-<timestamp>.json   # Baseline snapshot (file hashes, identities, config)
│   └── history/        # Historical skim reports
│       └── report-<timestamp>.json
```

## Baseline Snapshot Schema

Each baseline snapshot contains:

```json
{
  "timestamp": "2025-11-30T12:00:00Z",
  "environment": "DEV|UAT|PRD",
  "gmsaIdentity": "DOMAIN\\gMSA$",
  "fileHashes": {
    "C:\\Path\\To\\File.dll": "SHA256:ABC123...",
    "C:\\Path\\To\\Config.json": "SHA256:DEF456..."
  },
  "appPoolIdentities": {
    "RadarLiveAppPool": "DOMAIN\\gMSA$"
  },
  "configChecksums": {
    "appsettings.json": "SHA256:GHI789..."
  },
  "componentVersions": {
    "ManagementServer": "1.2.3",
    "CalculationService": "1.2.3"
  }
}
```

## Usage

Baseline snapshots are created via `src/Baselines/Snapshot.psm1` (T007) and referenced during drift detection (US3).

## Governance

- **Canonical Path**: Must be `.specify/baselines/` per Constitution Section V
- **Retention**: Artifacts retained ≥90 days
- **Access**: Read-only for auditors, write access for skim execution context
- **Versioning**: Snapshots are immutable; new runs create new timestamped files

## References

- Constitution: `.specify/memory/constitution.md` Sections V, VII, VIII
- Task T006: Create baseline artifacts storage path
- Task T007: Implement baseline snapshot script
- Task T301: Implement artifact retention policy
