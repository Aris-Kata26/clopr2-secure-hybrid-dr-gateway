# S4-01 Blocker Note (2026-03-13T15:43:21Z)

## Summary
S4-01 remains blocked by Azure Arc extension convergence on `pg-standby`.

## Evidence
- `pg-standby` extension states remained in `Creating` through the 30-minute retry window.
- Previous retries showed `HCRP409` lock conditions (marked for deletion / still processing).
- DCR association for `pg-standby` remains healthy and points to `dcr-hybrid-monitoring`.
- Telemetry currently confirms only partial coverage in latest 15-minute window:
  - Heartbeat: `pg-primary` only
  - Syslog: `pg-primary` only

## Polling timeline reference
- See `docs/05-evidence/monitoring/pg-standby-poll-timeline.txt`

## Recommendation
1. Keep ClickUp task `86c8b2bb6` open.
2. Retry at next 30-minute checkpoint (pg-standby only).
3. If still `Creating`, execute one controlled recreate cycle for `pg-standby` extensions only.
4. Re-run Heartbeat/Syslog immediately after convergence.
