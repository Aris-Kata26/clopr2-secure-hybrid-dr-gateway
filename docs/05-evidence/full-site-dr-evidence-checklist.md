# Full Site DR Validation — Evidence Checklist
<!-- CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24 -->

## Status: PENDING — not yet executed

Evidence directory: `docs/05-evidence/full-site-dr-validation/`
Failover runbook: `docs/03-operations/full-site-failover-runbook.md` v1.0
Failback runbook: `docs/03-operations/full-site-failback-runbook.md` v1.0

---

## Pre-deployment checks (before test day)

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| D-1 | `predeployment-drvm-docker.txt` | vm-pg-dr-fce | `docker --version` — Docker CE installed | [ ] |
| D-2 | `predeployment-app-image.txt` | vm-pg-dr-fce | `docker image ls clopr2-app:dr` — image present | [ ] |
| D-3 | `predeployment-app-env.txt` | vm-pg-dr-fce | `cat /home/azureuser/clopr2-app/.env` — DB_HOST=127.0.0.1 | [ ] |
| D-4 | `predeployment-ssh-chain.txt` | local | `ssh vm-pg-dr-fce 'hostname && whoami'` — chain works | [ ] |
| D-5 | `predeployment-wg-active.txt` | pg-primary | `sudo wg show` — peer handshake < 3 min | [ ] |
| D-6 | `predeployment-replication.txt` | pg-primary | `pg_stat_replication` — 10.200.0.2 streaming | [ ] |

---

## Failover pre-checks

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| P-1 | `fsdr-precheck-primary.txt` | pg-primary | pg_stat_replication, WireGuard show, Keepalived status, VIP on eth0 | [ ] |
| P-2 | `fsdr-precheck-app-health.txt` | WSL | `/health` HTTP 200, `pg_is_in_recovery: false` (on-prem primary active) | [ ] |
| P-3 | `fsdr-precheck-drvm.txt` | vm-pg-dr-fce | `pg_is_in_recovery()=t`, replication lag < 5 min, Docker image listed | [ ] |
| P-4 | `fsdr-start-timestamp.txt` | local | ISO timestamp at failover start | [ ] |

---

## Failover evidence

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| F-1 | `fsdr-app-stopped.txt` | app-onprem | `docker compose down` — app container stopped | [ ] |
| F-2 | `fsdr-final-lsn.txt` | pg-primary | `pg_current_wal_lsn()` + bytes_lag to DR VM — final WAL position before stop | [ ] |
| F-3 | `fsdr-primary-stopped.txt` | pg-primary | `systemctl status postgresql` and keepalived — both inactive (dead) | [ ] |
| F-4 | `fsdr-replay-wait.txt` | vm-pg-dr-fce | Replay LSN progression loop — shows DR VM consuming remaining WAL | [ ] |
| F-5 | `fsdr-promoted.txt` | vm-pg-dr-fce | `pg_is_in_recovery()=f`, `pg_current_wal_lsn()` returned, standby.signal absent | [ ] |
| F-6 | `fsdr-write-test.txt` | vm-pg-dr-fce | CREATE/INSERT/DROP on promoted DB — INSERT 0 1 without error | [ ] |
| F-7 | `fsdr-app-health-drvm.txt` | vm-pg-dr-fce | `/health` HTTP 200, `pg_is_in_recovery: false`, `app_env: dr-azure` | [ ] |
| F-8 | `fsdr-app-health-local.txt` | WSL | `/health` via SSH port-forward — same result confirmed externally | [ ] |
| F-9 | `fsdr-rto-summary.txt` | local | FSO_START, FSO_END timestamps; RTO delta; RPO bytes at promotion | [ ] |
| F-10 | `fsdr-post-failover-snapshot.txt` | vm-pg-dr-fce | Full post-failover state: PG role, pg_stat_replication, container, /health | [ ] |

---

## Failback pre-checks

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| B-P1 | `fsdb-precheck.txt` | vm-pg-dr-fce + pg-primary | DR VM pg_is_in_recovery=f, pg-primary services inactive, WireGuard up | [ ] |
| B-P2 | `fsdb-start-timestamp.txt` | local | ISO timestamp at failback start | [ ] |

---

## Failback evidence

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| B-1 | `fsdb-azure-app-stopped.txt` | vm-pg-dr-fce | `docker stop/rm clopr2-app-dr` — container removed | [ ] |
| B-2 | `fsdb-drvm-readonly.txt` | vm-pg-dr-fce | `SHOW default_transaction_read_only` = on | [ ] |
| B-3 | `fsdb-pg-basebackup.txt` | pg-primary | pg_basebackup output — completed without error; standby.signal present | [ ] |
| B-4 | `fsdb-primary-standby-start.txt` | pg-primary | postgresql active; `pg_is_in_recovery()=t` | [ ] |
| B-5 | `fsdb-drvm-replication.txt` | vm-pg-dr-fce | `pg_stat_replication` shows 10.200.0.1 (pg-primary), state=streaming | [ ] |
| B-6 | `fsdb-catchup-wait.txt` | vm-pg-dr-fce | Lag monitoring loop — bytes_lag approaches 0 | [ ] |
| B-7 | `fsdb-primary-promoted.txt` | pg-primary | `pg_promote()=t`; `pg_is_in_recovery()=f`; standby.signal absent | [ ] |
| B-8 | `fsdb-drvm-rebuild.txt` | vm-pg-dr-fce | pg_basebackup on DR VM from pg-primary; standby.signal present; PG started; pg_is_in_recovery=t | [ ] |
| B-9 | `fsdb-replication-restored.txt` | pg-primary | `pg_stat_replication` shows 10.200.0.2 (DR VM) streaming | [ ] |
| B-10 | `fsdb-vip-returned.txt` | pg-primary | Keepalived MASTER; `inet 10.0.96.10/16` on eth0 | [ ] |
| B-11 | `fsdb-app-started.txt` | app-onprem | `docker compose up -d`; container running | [ ] |
| B-12 | `fsdb-app-health.txt` | WSL | `/health` HTTP 200, `pg_is_in_recovery: false`, `app_env: dev` | [ ] |
| B-13 | `fsdb-rto-summary.txt` | local | FSB_START, FSB_END timestamps; failback RTO delta | [ ] |
| B-14 | `fsdb-post-failback-snapshot.txt` | pg-primary | Full post-failback state: VIP, PG role, Keepalived, replication, WireGuard | [ ] |
| B-15 | `fsdb-final-app-health.txt` | WSL | Final /health — confirms complete end-to-end restoration | [ ] |

---

## Post-test optional: pg-standby reintegration

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| S-1 | `fsdb-standby-reconnect.txt` | pg-standby | `pg_is_in_recovery()=t` after pg_basebackup from restored pg-primary (if needed) | [N/A or done] |

---

## Summary table

| Metric | Value |
|---|---|
| Failover RTO (stop → Azure app healthy) | TBD |
| Failback RTO (stop Azure app → on-prem app healthy) | TBD |
| RPO at promotion (bytes not applied) | TBD |
| Test date | TBD |
| Tested by | KATAR711 |
| Environment | dev (Proxmox on-prem + Azure francecentral) |
| DR VM | vm-pg-dr-fce (10.200.0.2, Standard_B2ats_v2) |
| Failover runbook version | 1.0 |
| Failback runbook version | 1.0 |

---

## Notes / deviations

*(to be filled in post-execution)*

---

## Evidence export command

Run from WSL after test completion to collect all files from the VMs:

```bash
EV=/mnt/c/Users/akata/Documents/Projects/CLOPR2/clopr2-secure-hybrid-dr-gateway/docs/05-evidence/full-site-dr-validation
mkdir -p "$EV"

# From pg-primary
scp -o ProxyJump=pve \
    -i ~/.ssh/id_ed25519_dr_onprem \
    katar711@10.0.96.11:/tmp/fsdr-*.txt \
    katar711@10.0.96.11:/tmp/fsdb-*.txt \
    "$EV/"

# From vm-pg-dr-fce
scp -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11" \
    -i ~/.ssh/id_ed25519_dr \
    azureuser@10.200.0.2:/tmp/fsdr-*.txt \
    azureuser@10.200.0.2:/tmp/fsdb-*.txt \
    "$EV/" 2>/dev/null || true

# Local files (already in /tmp on WSL)
cp /tmp/fsdr-*.txt /tmp/fsdb-*.txt "$EV/" 2>/dev/null || true

echo "Evidence files in $EV:"
ls -la "$EV/"
```
