# Post-Arc Validation Evidence

This directory stores terminal output captured AFTER Azure Arc agent installation and connect.

## Purpose
Prove that Arc onboarding caused zero disruption to the DR stack — PostgreSQL HA,
Keepalived VIP, WireGuard tunnel, and streaming replication all remain intact.

## Files to capture here

| Filename | Source command | Captured from |
|---|---|---|
| `post-arc-agentshow-pg-primary-<date>.txt` | `sudo azcmagent show` | pg-primary |
| `post-arc-agentshow-pg-standby-<date>.txt` | `sudo azcmagent show` | pg-standby |
| `post-arc-agentshow-app-onprem-<date>.txt` | `sudo azcmagent show` | app-onprem |
| `post-arc-keepalived-<date>.txt` | `systemctl status keepalived --no-pager` | pg-primary |
| `post-arc-wg-status-<date>.txt` | `sudo wg show` | pg-primary |
| `post-arc-pg-stat-replication-<date>.txt` | `psql -c "SELECT client_addr, state, write_lag FROM pg_stat_replication;"` | pg-primary |
| `post-arc-pg-is-in-recovery-<date>.txt` | `psql -tc "SELECT pg_is_in_recovery();"` | pg-standby |
| `post-arc-arc-machine-list-<date>.txt` | `az connectedmachine list -g rg-clopr2-katar711-gwc -o table` | local terminal |

## Expected values post-Arc install

- `azcmagent show` → `Status: Connected` on all 3 machines
- keepalived: `Active: active (running)` — unchanged
- WireGuard: peer `10.200.0.2` with recent handshake — unchanged
- pg_stat_replication: 2 rows — `10.0.96.14` + `10.200.0.2` streaming — unchanged
- pg_is_in_recovery: `t` on pg-standby — unchanged
- VIP `10.0.96.10` still on pg-primary: confirmed by `ip addr show | grep 10.0.96.10`

## Comparison check
Cross-reference with pre-arc/ files. All DR-related values must be identical.
The only change between pre-arc and post-arc files should be:
- presence of `azcmagent show` output (new)
- Arc appears in Azure portal (new)
- no change to any existing service state
