# Monitoring Evidence Notes (S4-01)

## Current status
- Arc connectivity is confirmed for `pg-primary`, `pg-standby`, and `app-onprem`.
- DCR `dcr-hybrid-monitoring` exists and is associated with all three Arc machines.
- Recovery is focused only on `pg-standby` (smallest safe path).
- `pg-standby` extensions are currently `Creating` for both `AzureMonitorLinuxAgent` and `DependencyAgentLinux` after a 30-minute time-box retry.
- S4-01 remains open until all three machines are visible in both Heartbeat and Syslog.

Latest validation timestamp (UTC): `2026-03-13T15:43:21Z`

## Evidence files generated
- `dcr-hybrid-monitoring.json`
- `log-analytics-heartbeat-query.txt`
- `log-analytics-syslog-query.txt`
- `monitoring-validation-raw.txt`
- `status-latest.txt`
- `pg-standby-poll-timeline.txt`
- `pg-standby-state-now.txt`
- `pg-standby-extension-detail.json`
- `pg-standby-dcr-association.txt`

## Required screenshots pending
- `arc-servers-connected.png`
- `monitor-agent-installed.png`
- `data-collection-rule-association.png`
- `syslog-config.png`
- `log-analytics-heartbeat-query.png`
- `log-analytics-syslog-query.png`

## Current limitation
- Azure Arc extension control-plane convergence is still in progress for `pg-standby`; this prevents final S4-01 completion criteria.

## Blocker recommendation
- Keep task `86c8b2bb6` open.
- Retry `pg-standby` extension convergence at the next 30-minute checkpoint.
- If still `Creating`, run one controlled recreate cycle for `pg-standby` only and revalidate Heartbeat/Syslog.
- Continue Sprint 4 execution on another task while S4-01 remains blocked by Azure backend convergence.
