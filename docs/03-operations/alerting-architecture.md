# Alerting Architecture — CLOPR2 Secure Hybrid DR Gateway

**Owner:** KATAR711 | **Team:** BCLC24
**Implemented:** 2026-03-18 (architecture hardening phase)
**Status:** Production-active — 5 alert rules + 1 operational dashboard deployed

---

## Overview

CLOPR2 monitoring is split across two Azure Log Analytics workspaces that mirror the dual-environment Terraform layout. Alert rules are defined as Terraform-managed resources under IaC; the workbook is deployed via Azure CLI (ARM API) because `azurerm_monitor_workbook` is not available in the azurerm ~4.0 provider.

| Workspace | ID | Hosts |
|-----------|-----|-------|
| `log-clopr2-dev-gwc` (dev, germanywestcentral) | `ad36192c-ac77-40dc-878d-0f8e74cd3638` | pg-primary, app-onprem |
| `log-clopr2-dr-fce` (dr-fce, francecentral) | `7d25b9ec-b9aa-4a5b-a8f6-065f26dc630d` | vm-pg-dr-fce |

**Known gap:** pg-standby is not represented in either workspace. Arc extension convergence (HCRP409) is blocked. Manual PostgreSQL health checks are required for pg-standby. See `docs/03-operations/monitoring-architecture.md`.

---

## Alert Rules

### Alert 1 — `alert-onprem-heartbeat-silence`

| Field | Value |
|-------|-------|
| Severity | 1 (Critical) |
| Workspace | dev (ad36192c) |
| Evaluation frequency | PT5M |
| Window | PT10M |
| Signal | `Heartbeat` table |
| Action group | ag-clopr2-ops |

**Trigger:** Either `pg-primary` or `app-onprem` has not sent a Heartbeat in the last 10 minutes.

**What it means:** Arc-connected VMs send a Heartbeat record every ~60 seconds via the AMA/gc_linux_service agent. A 10-minute silence means one of:
- The VM itself is down or unreachable
- The Arc agent has crashed and cannot send telemetry
- A network partition between the on-prem host and Azure Monitor

**Response:**
1. Check VM status: `ssh pg-primary 'uptime'` / `ssh app-onprem 'uptime'` via relay
2. Check Arc agent: `systemctl status azuremonitoragent gc_linux_service`
3. If VM unreachable, escalate to Proxmox console and physical checks

---

### Alert 2 — `alert-keepalived-priority-drop`

| Field | Value |
|-------|-------|
| Severity | 2 (High) |
| Workspace | dev (ad36192c) |
| Evaluation frequency | PT5M |
| Window | PT5M |
| Signal | `Syslog` (ProcessName=Keepalived_vrrp) |
| Action group | ag-clopr2-ops |

**Trigger:** Keepalived on `pg-primary` logs `Changing effective priority from 100 to 80` — indicating that `pg_isready` has failed 3 consecutive health checks (3 × 2s = 6 seconds).

**What it means:** PostgreSQL on pg-primary is not responding to `pg_isready`. Possible causes:
- PostgreSQL startup/shutdown in progress
- PostgreSQL crashed and is not restarting
- Disk or memory pressure causing query stall

**Important:** With `nopreempt` configured, a priority drop alone does **not** move the VIP. Keepalived continues advertising at reduced priority. The VIP only moves if pg-primary's Keepalived process stops entirely.

**Response:**
1. Check PostgreSQL status: `ssh pg-primary 'systemctl status postgresql'`
2. Check PostgreSQL logs: `ssh pg-primary 'sudo journalctl -u postgresql --since "5 minutes ago"'`
3. If PostgreSQL is stopped/crashed: attempt restart; monitor for Alert 3 (VIP state change)
4. If Alert 3 fires simultaneously, begin failback procedure per `dr-validation-runbook.md`

---

### Alert 3 — `alert-keepalived-vip-state-change`

| Field | Value |
|-------|-------|
| Severity | 1 (Critical) |
| Workspace | dev (ad36192c) |
| Evaluation frequency | PT5M |
| Window | PT5M |
| Signal | `Syslog` (ProcessName=Keepalived_vrrp) |
| Action group | ag-clopr2-ops |

**Trigger:** pg-primary Keepalived logs any of:
- `Entering BACKUP STATE`
- `Going to BACKUP`
- `New primary elected`

**What it means:** The VIP `10.0.96.10` has moved from pg-primary to pg-standby. PostgreSQL traffic is now served by the standby. **This is the observable marker of an on-prem HA failover.**

**Validated signal:** The VRRP syslog query was confirmed against live data during S4-03 DR validation (2026-03-14), where 2 priority drop/restore cycles were recorded.

**Response:**
1. **Confirm whether failover was planned.** If unplanned, treat as incident.
2. Verify pg-standby is serving traffic: check application `/health` endpoint
3. Verify replication is NOT running (pg-standby is now primary — it should not be replicating)
4. Begin failback per `docs/03-operations/dr-validation-runbook.md § Fallback`
5. Root-cause the pg-primary failure before returning VIP

---

### Alert 4 — `alert-app-docker-failure`

| Field | Value |
|-------|-------|
| Severity | 2 (High) |
| Workspace | dev (ad36192c) |
| Evaluation frequency | PT5M |
| Window | PT10M |
| Signal | `Syslog` (ProcessName=systemd, Computer=app-onprem) |
| Action group | ag-clopr2-ops |

**Trigger:** systemd on `app-onprem` logs messages matching `docker.service` or `docker` combined with `failed`, `Stopped`, `Failed to start`, or `deactivating`.

**What it means:** Docker has stopped or failed on app-onprem. The FastAPI application container is down. Users cannot reach the `/health` endpoint.

**Response:**
1. Check Docker status: `ssh app-onprem 'systemctl status docker'`
2. Check container: `ssh app-onprem 'docker ps'`
3. Restart Docker if stopped: `ssh app-onprem 'sudo systemctl restart docker && docker start <container>'`
4. Verify `/health` returns 200: `ssh pg-primary 'curl http://10.0.96.13:8080/health'`

---

### Alert 5 — `alert-pgdr-heartbeat-silence`

| Field | Value |
|-------|-------|
| Severity | 1 (Critical) |
| Workspace | dr-fce (7d25b9ec) |
| Evaluation frequency | PT5M |
| Window | PT10M |
| Signal | `Heartbeat` table |
| Action group | ag-clopr2-ops-dr |

**Trigger:** `vm-pg-dr-fce` has not sent a Heartbeat in the last 10 minutes.

**Dual purpose:**
- **VM/agent health:** Azure DR replica may be down or AMA agent has failed
- **WireGuard tunnel proxy:** WireGuard handshakes are not continuously logged. A silent Azure DR VM is the strongest available proxy for tunnel health — if the tunnel between pg-primary and vm-pg-dr-fce is broken, the VM cannot replicate or phone home reliably.

**Response:**
1. Check VM status via Azure Portal (Metrics > CPU, Network)
2. Check WireGuard on pg-primary: `ssh pg-primary 'sudo wg show'` — look for last handshake time
3. If tunnel is down: `ssh pg-primary 'sudo systemctl restart wg-quick@wg0'`
4. If VM is down: check auto-shutdown schedule, restart via `az vm start`
5. If replication is broken, begin DR failover assessment per `dr-validation-runbook.md`

---

## Action Groups

| Resource | Environment | Email |
|----------|-------------|-------|
| `ag-clopr2-ops` | dev (rg-clopr2-katar711-gwc) | katar711@school.lu |
| `ag-clopr2-ops-dr` | dr-fce (rg-clopr2-katar711-fce) | katar711@school.lu |

Both use `use_common_alert_schema = true` for structured alert payloads compatible with future webhook/Logic App routing.

---

## Operational Dashboard

**Name:** CLOPR2 DR Operational Dashboard (`wb-clopr2-dr-ops`)
**Resource group:** rg-clopr2-katar711-gwc
**Workbook GUID:** `e8e108e4-0468-4959-a3b9-6aa3c90c9d8c`
**Definition:** `infra/terraform/envs/dev/workbook-dr-ops.json`
**Deploy script:** `scripts/dr/deploy-workbook.sh`

**Dashboard tiles:**

| Tile | Query scope | Purpose |
|------|-------------|---------|
| Host Availability | Heartbeat, last 10m | ONLINE/SILENT status for pg-primary, app-onprem |
| Keepalived VRRP Events | Syslog, last 1h | Raw VRRP event log from pg-primary |
| Keepalived HA Summary | Syslog, last 24h | Priority drop/restore counts + current MASTER/BACKUP state |
| App Service Health | Syslog, last 24h | Docker events on app-onprem |
| Syslog Error Trend | Syslog, last 6h | Error/warning/crit message trend (area chart) |
| Coverage Summary | Static | Alert rule inventory + monitoring gap documentation |

**Deployment note:** `azurerm_monitor_workbook` is not available in azurerm ~4.0. The workbook is deployed via Azure CLI using the ARM `microsoft.insights/workbooks` resource type. Re-deployment: run `scripts/dr/deploy-workbook.sh` (creates a new GUID; delete the old resource first if replacing).

---

## IaC Layout

```
infra/terraform/envs/
├── dev/
│   ├── alerting.tf              # Alert rules 1-4 + action group
│   └── workbook-dr-ops.json     # Workbook definition (deployed via CLI)
└── dr-fce/
    └── alerting.tf              # Alert rule 5 + action group
```

All alert rules are `azurerm_monitor_scheduled_query_rules_alert_v2` resources. State is managed in Azure Blob Storage (see `docs/03-operations/tf-state-governance.md`).

---

## Evidence

Deployment and validation evidence is in `docs/05-evidence/alerting/`:

| File | Contents |
|------|----------|
| `01-alert-rules-dev.json` | 4 alert rules in rg-clopr2-katar711-gwc (az CLI output) |
| `02-alert-rules-dr-fce.json` | 1 alert rule in rg-clopr2-katar711-fce |
| `03-action-groups-dev.json` | ag-clopr2-ops action group |
| `04-action-groups-dr-fce.json` | ag-clopr2-ops-dr action group |
| `05-workbook-deployed.json` | Workbook resource in Azure |
| `06-kql-heartbeat-validation.json` | Live heartbeat query — pg-primary + app-onprem ONLINE |
| `07-kql-keepalived-validation.json` | Live VRRP query — 2 drops/2 restores from S4-03 test |
