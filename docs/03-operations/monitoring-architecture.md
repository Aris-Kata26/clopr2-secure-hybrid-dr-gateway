# Monitoring Architecture (Sprint 4 S4-01)

## Scope
Onboard on-premises Arc-connected machines to Azure Log Analytics using Azure Monitor Agent (AMA) and Data Collection Rules (DCR).

Target machines:
- `pg-primary`
- `pg-standby`
- `app-onprem`

## Architecture
- Azure Arc (`Microsoft.HybridCompute/machines`) is the control plane for on-prem servers.
- Azure Monitor Agent (`AzureMonitorLinuxAgent`) on each server forwards telemetry.
- Data Collection Rule `dcr-hybrid-monitoring` defines what to collect.
- Log Analytics workspace `log-clopr2-dev-gwc` stores and serves telemetry for Kusto queries.

Flow:
1. Arc machine extension runs AMA.
2. DCR association binds machine to `dcr-hybrid-monitoring`.
3. Syslog + performance counters are routed to Log Analytics.
4. Validation is performed with KQL (`Heartbeat`, `Syslog`).

## DCR Configuration
DCR name: `dcr-hybrid-monitoring`

Configured sources:
- Syslog facilities:
  - `auth`
  - `authpriv`
  - `daemon`
  - `syslog`
- Performance counters:
  - `\\Processor(_Total)\\% Processor Time`
  - `\\Memory\\Available MBytes`

Destination:
- Log Analytics workspace resource:
  - `/subscriptions/94e5704a-b411-402b-a8f3-ef46309fe5fb/resourceGroups/rg-clopr2-katar711-gwc/providers/Microsoft.OperationalInsights/workspaces/log-clopr2-dev-gwc`

Reference artifact:
- `docs/05-evidence/monitoring/dcr-hybrid-monitoring.json`

## Validation Queries
Heartbeat validation:
```kusto
Heartbeat
| where TimeGenerated > ago(5m)
```

Syslog validation:
```kusto
Syslog
| where TimeGenerated > ago(5m)
| take 50
```

Additional per-machine summaries used during troubleshooting:
```kusto
Heartbeat
| where TimeGenerated > ago(60m)
| summarize c=count() by Computer
| order by Computer asc
```

```kusto
Syslog
| where TimeGenerated > ago(60m)
| summarize c=count() by Computer
| order by Computer asc
```

## Current Operational Status
- Arc connectivity: all three target machines report `Connected`.
- DCR exists and has required syslog facilities and perf counters.
- DCR associations were created for all three target machines.
- Log ingestion currently observed from `pg-primary`.
- `pg-standby` and `app-onprem` are blocked by Arc extension lifecycle operations stuck in `Creating/Processing` (`HCRP409`), preventing complete telemetry onboarding.

## Evidence Artifacts
Available in `docs/05-evidence/monitoring/`:
- `dcr-hybrid-monitoring.json`
- `log-analytics-heartbeat-query.txt`
- `log-analytics-syslog-query.txt`
- `monitoring-validation-raw.txt`
- `status-latest.txt`

Pending screenshots to capture in Azure Portal once extension state converges:
- `arc-servers-connected.png`
- `monitor-agent-installed.png`
- `data-collection-rule-association.png`
- `syslog-config.png`
- `log-analytics-heartbeat-query.png`
- `log-analytics-syslog-query.png`
