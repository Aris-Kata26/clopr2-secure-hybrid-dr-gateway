# DR Automation Scripts

All scripts apply the SSH relay pattern for pg-standby (10.0.96.14) and app-onprem (10.0.96.13) via pg-primary ProxyCommand. CRLF-safe (LF line endings). Tested on Ubuntu WSL → Proxmox → on-prem VMs.

---

## Scripts

| Script | Type | Status | Purpose |
|--------|------|--------|---------|
| `ssh-precheck.sh` | Validated | ✅ Tested 2026-03-16 | Verify SSH connectivity to all on-prem hosts before any DR operation |
| `dr-preflight.sh` | Validated | ✅ Tested 2026-03-16 (10/10 PASS) | Full pre-failover health check — PostgreSQL, Keepalived, replication, WireGuard |
| `onprem-failover.sh` | Validated | ✅ Tested 2026-03-16 | Stop Keepalived on pg-primary → VIP moves to pg-standby (<1s VRRP, <5s app) |
| `onprem-fallback.sh` | Validated | ✅ Tested 2026-03-16 | Start Keepalived on pg-primary → VIP returns, replication resumes |
| `fullsite-failover.sh` | Supporting | ✅ Tested 2026-03-16 | Orchestrate full-site DR — pg-primary stop → Azure DR VM promote → app start |
| `fullsite-fallback.sh` | Supporting | ✅ Tested 2026-03-16 | Full-site fallback — pg_basebackup from DR VM → promote pg-primary → VIP return |
| `evidence-export.sh` | Supporting | ✅ Tested 2026-03-16 | Collect timestamped evidence files from all nodes to local /tmp |
| `classify-vm.sh` | Helper | ✅ Current | Identify VM role (primary/standby/app/dr) from current runtime state |
| `validate-registry.sh` | Helper | ✅ Current | Validate ACR image push and AKS pull — container registry checks |
| `deploy-workbook.sh` | Helper | ✅ Current | Deploy Azure Monitor workbook for DR operational dashboard |
| `clickup-create-tasks.sh` | Helper | Supporting | ClickUp task creation automation for sprint management |

---

## Execution Order for On-Prem HA Failover

```
ssh-precheck.sh → dr-preflight.sh → onprem-failover.sh → [validate] → onprem-fallback.sh
```

## Execution Order for Full-Site DR

```
ssh-precheck.sh → dr-preflight.sh → fullsite-failover.sh → [validate] → fullsite-fallback.sh
```

See `docs/03-operations/dr-validation-runbook.md` for the full validated procedure.
