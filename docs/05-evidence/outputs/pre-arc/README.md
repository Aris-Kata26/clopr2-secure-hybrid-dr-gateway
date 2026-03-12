# Pre-Arc Baseline Evidence

This directory stores terminal output captured BEFORE Azure Arc agent installation.

## Purpose
Establish a verified baseline of the DR stack state before Arc onboarding begins,
to prove that Arc installation caused no disruption.

## Files to capture here

| Filename | Source command | Captured from |
|---|---|---|
| `pre-arc-keepalived-pg-primary-<date>.txt` | `systemctl status keepalived --no-pager` | pg-primary |
| `pre-arc-wg-status-<date>.txt` | `sudo wg show` | pg-primary |
| `pre-arc-pg-stat-replication-<date>.txt` | `psql -c "SELECT client_addr, state, write_lag FROM pg_stat_replication;"` | pg-primary |
| `pre-arc-pg-is-in-recovery-<date>.txt` | `psql -tc "SELECT pg_is_in_recovery();"` | pg-standby |
| `pre-arc-postgresql-status-<date>.txt` | `systemctl status postgresql --no-pager` | pg-primary |

## How to fetch

```bash
# From pg-primary
scp pg-primary:/tmp/pre-arc-*.txt docs/05-evidence/outputs/pre-arc/

# From pg-standby
scp pg-standby:/tmp/pre-arc-pg-is-in-recovery.txt docs/05-evidence/outputs/pre-arc/
```

## Expected values before Arc install

- keepalived: `Active: active (running)`
- WireGuard: peer `10.200.0.2` with recent handshake
- pg_stat_replication: 2 rows — `10.0.96.14` (standby) and `10.200.0.2` (Azure DR)
- pg_is_in_recovery: `t` on pg-standby
