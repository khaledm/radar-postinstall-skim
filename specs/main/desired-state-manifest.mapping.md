| Field | Example Value | Why It Matters |
|-------|--------------|---------------|
| EnvironmentName | DEV | Target environment for the skim (DEV/UAT/PRD) |
| GMSInUse | TEST\\SVRPPRRDRLDEV01$ | gMSA identity in use for this environment (AppPool/SQL) |
| Components | [ ... ] | List of all Radar Live components and their expected state |
| displayName | "Settings Manager" | Human-readable name for the component |
| expectedServiceName | "dpo-qaa-sttgsmngr" | Windows service name to check for presence/running |
| expectedInstallPath | "D:/Program Files/Radar/dpo-qaa-sttgsmngr" | Path where the component must be installed |
| expectedHealthUrl | "http://localhost:8084/" | Health endpoint to check for liveness |
| expectedAppPool | "dpo-qaa-sttgsMgrAppPool" | IIS AppPool name for the component |
| runtimeDependencies | [ ... ] | Other components this one depends on (for dependency chain checks) |
| IIS.requiredWindowsFeatures | [ ... ] | Windows features required for IIS hosting |
| IIS.expectedSites | [ ... ] | IIS sites that must exist |
| IIS.expectedAppPools | [ ... ] | AppPools and their expected gMSA identities |
| SQL.sqlServers | [ ... ] | SQL Server host(s) and DBs to check |
| SQL.connectionTest | true | Indicates a live DB connection test is required |
| SQL.dnsResolutionTimeoutSeconds | 3 | DNS resolution timeout for SQL host |
| SQL.portConnectionTimeoutSeconds | 5 | Port open timeout for SQL host |
| Network.dnsResolution | true | DNS must resolve for all hosts |
| Network.portOpen | [1433, 8081, 8082, 8083, 8084, 8085] | Ports that must be open (SQL, HTTP) |
| Network.routingChecks | true | Validate outbound routing to SQL |
| Network.routingCheckDescription | "Validate default gateway and interface for outbound SQL connectivity" | What the routing check must validate |
| EventLog.lookbackHours | 12 | How far back to scan event logs |
| EventLog.filterSources | [ ... ] | Event log sources to filter on |
| EventLog.severityLevels | [ ... ] | Which event severities to flag |
| VersionChecks.dotnetHostingBundle | ">=7.0.0" | Minimum .NET Hosting Bundle version |
| VersionChecks.powershellMinimumVersion | ">=7.2.0" | Minimum PowerShell version |
| VersionChecks.wtwManagementModule | {name, minVersion} | Required PowerShell module and version |
| ConfigFileChecks.filePaths | [ ... ] | Config files to validate (updated to match manifest paths) |
| ConfigFileChecks.expectedJsonOrXmlSchema | true | Validate config files against schema |
| ConfigFileChecks.fileHashComparison | true | Store and compare file hashes for drift |
| HealthAndTiming.healthHttpTimeoutSeconds | 5 | Timeout for health endpoint checks |
| HealthAndTiming.healthSuccessCodes | [200] | HTTP codes considered healthy |
| HealthAndTiming.maxTotalSkimDurationSeconds | 300 | Max allowed total runtime |
| Reporting.outputFormat | ["json", "md", "table"] | Supported output formats (updated to match manifest) |
| Reporting.storeHistory | true | Whether to store historical reports |
| Reporting.historyStoragePath | "D:/Logs/RadarSkim/History" | Where to store history (updated to match manifest) |
| Reporting.failOnCritical | true | Block on critical FAILs |
| Reporting.warnThreshold | 3 | Max WARNs allowed before blocking |
| SecretsAndSecurity.noSecretsInLogs | true | Ensure no secrets are written to logs |
| SecretsAndSecurity.logPlaceholderForSecrets | "[REDACTED]" | Placeholder for any secret value |
| AcceptanceTestSpec | { ... } | Minimal acceptance test for a component |
