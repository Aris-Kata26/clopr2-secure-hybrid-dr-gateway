# DR Validation Evidence Checklist
<!-- CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24 -->

## Status: COMPLETE — executed 2026-03-14, commit 12a6374

Evidence directory: `docs/05-evidence/dr-validation/`
Runbook: `docs/03-operations/dr-validation-runbook.md` v1.2

---

## Pre-checks (baseline state)

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| P-1 | `precheck-timestamp.txt` | pg-primary | ISO timestamp of pre-check run | [x] |
| P-2 | `precheck-vip.txt` | pg-primary | `ip addr show eth0` — VIP 10.0.96.10 confirmed on primary | [x] |
| P-3 | `precheck-keepalived-primary.txt` | pg-primary | `systemctl status keepalived` — MASTER, active (running) | [x] |
| P-4 | `precheck-postgresql-primary.txt` | pg-primary | `systemctl status postgresql` — active (exited, Ubuntu wrapper) | [x] |
| P-5 | `precheck-wg.txt` | pg-primary | `wg show` — config present, no handshake (Azure VM deallocated — deviation noted) | [x] |
| P-6 | `precheck-replication.txt` | pg-primary | `pg_stat_replication` — 1 row (Azure DR absent — deviation noted) | [x] |
| P-7 | `precheck-keepalived-standby.txt` | pg-standby | `systemctl status keepalived` — BACKUP, active (running) | [x] |
| P-8 | `precheck-vip-standby.txt` | pg-standby | `ip addr show eth0` — VIP absent on standby | [x] |
| P-9 | `precheck-recovery.txt` | pg-standby | `pg_is_in_recovery()` = t | [x] |
| P-10 | `precheck-app-health.txt` | app-onprem | `/health` HTTP 200, `pg_is_in_recovery: false` | [x] |
| P-11 | screenshot N/A | — | Captured via automated script; terminal screenshots not taken | [N/A] |

---

## Failover evidence

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| F-1 | `failover-start-timestamp.txt` | local | ISO timestamp when failover was initiated | [x] |
| F-2 | `failover-keepalived-primary.txt` | pg-primary | `systemctl status keepalived` — inactive (dead) at 14:39:13 UTC | [x] |
| F-3 | `failover-vip-moved.txt` | pg-standby | `ip addr show eth0` — VIP 10.0.96.10 present on standby | [x] |
| F-4 | `failover-vip-primary-lost.txt` | pg-primary | `ip addr show eth0` — VIP absent from primary | [x] |
| F-5 | `failover-keepalived-standby.txt` | pg-standby | `systemctl status keepalived` — MASTER STATE at 14:39:13 UTC | [x] |
| F-6 | `failover-recovery-standby.txt` | pg-standby | `pg_is_in_recovery()` = t (standby still in replica mode, no promotion) | [x] |
| F-7 | `failover-app-health.txt` | app-onprem | `/health` HTTP 200, `pg_is_in_recovery: true` — VIP on standby confirmed | [x] |
| F-8 | `failover-rto-timestamp.txt` | local | ISO timestamp at evidence capture — RTO < 1s VRRP, < 5s app-confirmed | [x] |
| F-9 | WireGuard N/A | — | Azure DR VM deallocated; tunnel down pre-test (deviation, not failover-caused) | [N/A] |
| F-10 | `posttest-final-snapshot.txt` | pg-primary | Combined post-test state — covers F-10/F-11 | [x] |
| F-11 | see F-5 + F-6 | pg-standby | Standby state captured in failover-keepalived-standby.txt + failover-recovery-standby.txt | [x] |
| F-12 | screenshot N/A | — | Captured via automated script | [N/A] |
| F-13 | screenshot N/A | — | Captured via automated script | [N/A] |

---

## Fallback evidence

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| B-1 | `fallback-start-timestamp.txt` | local | ISO timestamp: 15:52:15 UTC | [x] |
| B-2 | `fallback-postgresql-started.txt` | pg-primary | `systemctl status postgresql` — active (exited) | [x] |
| B-3 | `fallback-keepalived-primary.txt` | pg-primary | `systemctl status keepalived` — MASTER STATE at 15:52:29 UTC | [x] |
| B-4 | `fallback-vip-standby.txt` | pg-standby | `ip addr show eth0` — VIP absent from standby | [x] |
| B-5 | `fallback-vip-returned.txt` | pg-primary | `ip addr show eth0` — VIP 10.0.96.10 back on primary | [x] |
| B-6 | see fallback-replication.txt | pg-primary | Replication reconnected automatically — no wait loop needed | [x] |
| B-7 | `fallback-replication.txt` | pg-primary | `pg_stat_replication` — 10.0.96.14 streaming, lag ~11ms | [x] |
| B-8 | `fallback-recovery-standby.txt` | pg-standby | `pg_is_in_recovery()` = t | [x] |
| B-9 | `fallback-app-health.txt` | app-onprem | `/health` HTTP 200, `pg_is_in_recovery: false` — VIP back on primary | [x] |
| B-10 | `fallback-complete-timestamp.txt` | local | ISO timestamp: 15:52:39 UTC — elapsed 24 seconds | [x] |
| B-11 | `posttest-final-snapshot.txt` | pg-primary | Full post-fallback system state | [x] |
| B-12 | screenshot N/A | — | Captured via automated script | [N/A] |
| B-13 | screenshot N/A | — | Captured via automated script | [N/A] |
| B-14 | screenshot N/A | — | Captured via automated script | [N/A] |

---

## Post-test final state

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| Z-1 | `posttest-final-snapshot.txt` | pg-primary | Full system state — VIP, PG, keepalived, replication, all nominal | [x] |
| Z-2 | screenshot N/A | — | Captured via automated script | [N/A] |

---

## Summary table

| Metric | Value |
|---|---|
| Failover RTO (VRRP election) | < 1 second |
| Failover RTO (app-confirmed) | < 5 seconds |
| VIP move time | 14:39:13 UTC (same second as keepalived stop) |
| Fallback total time | 24 seconds (15:52:15 → 15:52:39 UTC) |
| Replication reconnect time | Automatic — resumed within fallback window |
| Test date | 2026-03-14 |
| Tested by | KATAR711 |
| Environment | dev (Proxmox on-prem + Azure germanywestcentral) |
| Arc dependency | None — direct operational evidence |
| Commit | 12a6374 (branch: main) |

---

## Notes / deviations

**Pre-test deviation — Azure DR VM deallocated:**
Azure DR VM auto-shutdown fired overnight. WireGuard tunnel had no active handshake; Azure DR VM absent from `pg_stat_replication` (1 row instead of expected 2). Documented and scoped out — on-prem HA test proceeded independently and is unaffected by this deviation.

**Key finding — `nopreempt` failover trigger:**
The correct failover trigger is `systemctl stop keepalived` on pg-primary, not `systemctl stop postgresql`. Stopping only postgresql drops keepalived priority 100→80 but the BACKUP does not preempt a still-advertising MASTER with `nopreempt` active. Runbook updated to v1.2 with this finding in sections 2, 3A, 5, and 9.

**Fallback behaviour:**
Starting keepalived on pg-primary (after postgresql is running) is sufficient to return the VIP. No action on pg-standby required — pg-primary wins the VRRP election naturally at priority 100 vs pg-standby's 90.
