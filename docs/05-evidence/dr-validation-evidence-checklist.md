# DR Validation Evidence Checklist
<!-- CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24 -->

## Status: PENDING — execute dr-validation-runbook.md to populate

Evidence target directory: `docs/05-evidence/dr-validation/`

---

## Pre-checks (baseline state)

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| P-1 | `precheck-timestamp.txt` | pg-primary | ISO timestamp of pre-check run | [ ] |
| P-2 | `precheck-vip.txt` | pg-primary | `ip addr show eth0` — VIP on primary confirmed | [ ] |
| P-3 | `precheck-keepalived-primary.txt` | pg-primary | `systemctl status keepalived` — MASTER | [ ] |
| P-4 | `precheck-postgresql-primary.txt` | pg-primary | `systemctl status postgresql` — active | [ ] |
| P-5 | `precheck-wg.txt` | pg-primary | `wg show` — tunnel up, handshake fresh | [ ] |
| P-6 | `precheck-replication.txt` | pg-primary | `pg_stat_replication` — ≥ 2 rows (standby + DR) | [ ] |
| P-7 | `precheck-keepalived-standby.txt` | pg-standby | `systemctl status keepalived` — BACKUP | [ ] |
| P-8 | `precheck-vip-standby.txt` | pg-standby | `ip addr show eth0` — VIP absent on standby | [ ] |
| P-9 | `precheck-recovery.txt` | pg-standby | `pg_is_in_recovery()` = t | [ ] |
| P-10 | `precheck-app-health.txt` | local/app | `curl /health` HTTP 200, JSON body shows `pg_is_in_recovery: false` (connected to primary) | [ ] |
| P-11 | screenshot: `precheck-pg-stat-replication.png` | pg-primary terminal | Visual of replication table | [ ] |

---

## Failover evidence

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| F-1 | `failover-start-timestamp.txt` | pg-primary | ISO timestamp when postgresql was stopped | [ ] |
| F-2 | `failover-pg-stopped.txt` | pg-primary | `systemctl status postgresql` — inactive | [ ] |
| F-3 | `failover-vip-moved.txt` | pg-standby | `ip addr show eth0` — VIP (10.0.96.10) present + timestamp | [ ] |
| F-4 | `failover-vip-on-primary-post.txt` | pg-primary | `ip addr show eth0` — VIP absent on primary | [ ] |
| F-5 | `failover-keepalived-standby-post.txt` | pg-standby | `systemctl status keepalived` — MASTER state | [ ] |
| F-6 | `failover-pg-recovery-standby.txt` | pg-standby | `pg_is_in_recovery()` = t (standby still in recovery) | [ ] |
| F-7 | `failover-app-health-recovery.txt` | local/app | Poll loop showing app returning HTTP 200 after VIP move; JSON body shows `pg_is_in_recovery: true` confirming connection to pg-standby | [ ] |
| F-8 | `failover-rto.txt` | pg-primary | FAILOVER_START, FAILOVER_END, RTO delta in seconds | [ ] |
| F-9 | `failover-wg-status.txt` | pg-primary | `wg show` — WireGuard tunnel unaffected | [ ] |
| F-10 | `failover-full-snapshot.txt` | pg-primary | Combined post-failover state | [ ] |
| F-11 | `failover-standby-snapshot.txt` | pg-standby | Combined post-failover state on standby | [ ] |
| F-12 | screenshot: `failover-vip-on-standby.png` | pg-standby terminal | Visual of VIP on standby eth0 | [ ] |
| F-13 | screenshot: `failover-app-health-200.png` | curl output | App /health HTTP 200; JSON shows `pg_is_in_recovery: true` | [ ] |

---

## Fallback evidence

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| B-1 | `fallback-start-timestamp.txt` | pg-primary | ISO timestamp when fallback started | [ ] |
| B-2 | `fallback-pg-restarted.txt` | pg-primary | `systemctl status postgresql` — active + pg_isready OK | [ ] |
| B-3 | `fallback-keepalived-primary-post.txt` | pg-primary | `systemctl status keepalived` — priority restored | [ ] |
| B-4 | `fallback-vip-on-standby-post.txt` | pg-standby | `ip addr show eth0` — VIP absent after keepalived restart | [ ] |
| B-5 | `fallback-vip-returned.txt` | pg-primary | `ip addr show eth0` — VIP (10.0.96.10) back on primary + timestamp | [ ] |
| B-6 | `fallback-replication-wait.txt` | pg-primary | Poll loop showing standby reconnect | [ ] |
| B-7 | `fallback-replication-restored.txt` | pg-primary | `pg_stat_replication` — ≥ 2 rows restored | [ ] |
| B-8 | `fallback-recovery-standby.txt` | pg-standby | `pg_is_in_recovery()` = t (standby back in replica mode) | [ ] |
| B-9 | `fallback-app-health.txt` | local/app | `curl /health` HTTP 200; JSON body shows `pg_is_in_recovery: false` confirming VIP back on primary | [ ] |
| B-10 | `fallback-rto.txt` | pg-primary | FALLBACK_START, FALLBACK_END, delta in seconds | [ ] |
| B-11 | `fallback-full-snapshot.txt` | pg-primary | Combined post-fallback state (VIP, PG, KA, WG, replication) | [ ] |
| B-12 | screenshot: `fallback-vip-on-primary.png` | pg-primary terminal | Visual of VIP returned to primary | [ ] |
| B-13 | screenshot: `fallback-replication-restored.png` | pg-primary terminal | Visual of pg_stat_replication with both replicas | [ ] |
| B-14 | screenshot: `fallback-app-health-200.png` | curl output | App /health HTTP 200; JSON shows `pg_is_in_recovery: false` | [ ] |

---

## Post-test final state

| # | File | Source host | Content | Status |
|---|---|---|---|---|
| Z-1 | `post-test-final.txt` | pg-primary | Full system state — all services, VIP, replication, WireGuard | [ ] |
| Z-2 | screenshot: `post-test-pg-stat-replication.png` | pg-primary terminal | Replication healthy, 2 rows | [ ] |

---

## Summary table (fill in after test)

| Metric | Value |
|---|---|
| Failover RTO | ___ seconds |
| VIP move time | ___ seconds |
| App recovery time | ___ seconds |
| Fallback total time | ___ seconds |
| Replication reconnect time | ___ seconds |
| Test date | ___ |
| Tested by | KATAR711 |
| Environment | dev (Proxmox + Azure germanywestcentral) |
| Arc dependency | None — direct operational evidence |

---

## Notes / issues during test

<!-- Record any anomalies, retries, or deviations from the runbook here -->
