# DR Promotion Runbook — Azure France-Central Replica to Primary

> **Version:** 1.0  
> **Date:** 2026-03-10  
> **Status:** READY — execute only under approved change window  
> **Author:** ops / clopr2 team  

---

## Overview

This runbook promotes the Azure DR replica (`vm-pg-dr-fce`, WireGuard IP `10.200.0.2`,
PostgreSQL 16 on Ubuntu 22.04) to a standalone writable primary after an on-prem
pg-primary failure or a planned switchover.

**Replication topology at rest:**

```
pg-primary (10.0.96.11)  ←→  WireGuard tunnel (10.200.0.1 ↔ 10.200.0.2)
                                   │
                           vm-pg-dr-fce (Azure FR)
                           standby.signal present, pg_is_in_recovery()=t
```

---

## Prerequisites / Pre-checks

| Check | Command | Expected |
|---|---|---|
| WireGuard tunnel up | `sudo wg show` (on pg-primary or DR VM) | Latest handshake < 3 min |
| DR replica streaming | `psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"` on pg-primary | Row for `10.200.0.2`, `streaming`, `async` |
| DR replica in recovery | SSH to DR VM → `psql -U postgres -c "SELECT pg_is_in_recovery();"` | `t` |
| Replication lag | `psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;" ` on DR VM | < 5 minutes (data loss window) |
| No ongoing transactions | On pg-primary: `psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE state='active' AND query NOT LIKE '%idle%';"` | 0 or minimal |

**SSH to DR VM (3-hop chain):**

```bash
ssh -F /home/aris/.ssh/dr_tunnel.cfg dr-tunnel
```

---

## Step 1 — Record replication state before promotion

On **pg-primary** (if reachable):

```sql
-- Record LSN and lag for evidence
SELECT
  client_addr,
  pg_current_wal_lsn() AS primary_lsn,
  sent_lsn,
  replay_lsn,
  (pg_current_wal_lsn() - replay_lsn) AS bytes_lag,
  state,
  sync_state
FROM pg_stat_replication
WHERE client_addr = '10.200.0.2';
```

Save the output: `docs/05-evidence/outputs/pg-dr-pre-promote-YYYYMMDD.txt`

---

## Step 2 — Stop writes on pg-primary (if reachable)

> **Skip this step if pg-primary is unreachable (unplanned outage scenario).**

On **pg-primary**, prevent new writes before promoting DR so no data diverges:

```bash
# Option A — put primary into read-only mode
psql -U postgres -c "ALTER SYSTEM SET default_transaction_read_only = on;"
psql -U postgres -c "SELECT pg_reload_conf();"

# Option B — stop the application (cleaner for planned switchover)
# Stop app-onprem service / connection pool first
```

---

## Step 3 — Promote DR replica

SSH to **vm-pg-dr-fce** and run:

```bash
# Method A — SQL function (PG12+, preferred — safe for scripting)
sudo -u postgres psql -c "SELECT pg_promote();"

# Method B — pg_ctlcluster (alternative if Method A fails)
sudo pg_ctlcluster 16 main promote

# Verify standby.signal is removed (it should disappear on successful promotion)
ls /var/lib/postgresql/16/main/standby.signal   # should return: No such file or directory
```

---

## Step 4 — Verify promoted state

On **vm-pg-dr-fce**:

```sql
-- Must return 'f' (not in recovery → writable primary)
SELECT pg_is_in_recovery();

-- Should return a WAL LSN (confirms write activity is possible)
SELECT pg_current_wal_lsn();

-- Try a write (confirms read-write capability)
CREATE TABLE _promote_test (ts timestamptz DEFAULT now());
INSERT INTO _promote_test VALUES (DEFAULT);
SELECT * FROM _promote_test;
DROP TABLE _promote_test;
```

Save output: `docs/05-evidence/outputs/pg-dr-post-promote-YYYYMMDD.txt`

---

## Step 5 — App redirection (post-promotion)

### Constraint

The current NSG rule `allow-postgres` only permits source `10.200.0.1/32` (pg-primary's
WireGuard IP) to reach DR VM port 5432. The app-onprem server (`10.0.96.13`) **cannot**
currently reach the DR VM directly.

### Two-path approach

**Path A — WireGuard IP forwarding via pg-primary (recommended; no Terraform change):**

1. On **pg-primary**, enable IP forwarding and add MASQUERADE so app-onprem traffic routes
   through the tunnel:
   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   sudo iptables -t nat -A POSTROUTING -d 10.200.0.2 -j MASQUERADE
   # Make persistent:
   echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-wg-forward.conf
   sudo iptables-save | sudo tee /etc/iptables/rules.v4
   ```
2. Update app env `DB_HOST=10.200.0.1` (pg-primary WireGuard IP, which now forwards to DR).

**Path B — Extend NSG to on-prem app subnet (requires Terraform apply):**

1. In `infra/terraform/envs/dr-fce/terraform.tfvars` update:
   ```hcl
   pg_dr_onprem_cidrs = ["10.200.0.1/32", "10.0.0.0/16"]
   ```
2. Apply:
   ```bash
   cd infra/terraform/envs/dr-fce
   terraform apply -var-file=terraform.tfvars
   ```
3. Update app env `DB_HOST=10.200.0.2` (direct DR VM IP).

> **Decision log:** Path A is faster and avoids NSG change during an outage. Path B is
> cleaner for longer-term operation. Document decision before executing.

---

## Step 6 — Failback prerequisites (when pg-primary is recovered)

Perform failback **only during a scheduled change window** after pg-primary is fully
repaired and rebuild is validated.

### Failback sequence (high-level)

1. **Confirm pg-primary is healthy** — OS, disk, network all up, PostgreSQL service
   stopped (DO NOT start it yet — old data is stale).
2. **Re-run WireGuard tunnel playbook** (pg-primary must re-establish as WireGuard peer):
   ```bash
   cd infra/ansible
   ANSIBLE_ROLES_PATH="$(pwd)/roles" \
   ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible_vault_pass \
   ANSIBLE_HOST_KEY_CHECKING=False \
   ansible-playbook -i inventories/dev playbooks/wg_tunnel.yml
   ```
3. **Rebuild pg-primary as standby of DR VM** using `pg_basebackup`:
   ```bash
   # On pg-primary (now standby)
   sudo systemctl stop postgresql@16-main
   sudo -u postgres rm -rf /var/lib/postgresql/16/main
   sudo -u postgres pg_basebackup \
     -h 10.200.0.2 -U replicator \
     -D /var/lib/postgresql/16/main \
     -R -P --wal-method=stream
   sudo systemctl start postgresql@16-main
   ```
4. **Verify pg_stat_replication** on DR VM shows pg-primary as `streaming`.
5. **Stop writes on DR VM**, perform planned switchover back:
   - `pg_promote()` on pg-primary.
   - Point DR back as standby.
   - Restore NSG / app `DB_HOST` to original values.
6. **Terraform apply** to restore original `pg_dr_onprem_cidrs` if expanded in Step 5.

---

## Evidence Checklist

Capture and save to `docs/05-evidence/outputs/`:

| File | Content | When |
|---|---|---|
| `pg-dr-pre-promote-YYYYMMDD.txt` | pg_stat_replication before promotion | Before Step 3 |
| `pg-dr-post-promote-YYYYMMDD.txt` | pg_is_in_recovery()=f + write test | After Step 4 |
| `pg-dr-app-redirect-YYYYMMDD.txt` | App connectivity test to DR VM | After Step 5 |
| `pg-dr-failback-YYYYMMDD.txt` | pg_stat_replication on DR showing pg-primary streaming | After failback |

Screenshots:

| File | Content |
|---|---|
| `screenshots/pg-stat-replication-dr.png` | pg_stat_replication on pg-primary before drill |
| `screenshots/pg-is-in-recovery-promoted.png` | pg_is_in_recovery()=f on DR VM after promotion |
| `screenshots/azure-vm-overview.png` | Azure portal vm-pg-dr-fce VM blade |
| `screenshots/nsg-pg-dr-rules.png` | NSG nsg-clopr2-dr-fce rules |

---

## Rollback (undo promotion — only possible before app redirection)

If promotion completed but the app has **not yet** been redirected:

```bash
# Restore pg-primary as primary and rebuild DR as standby
# (same as failback sequence in Step 6 — perform immediately)
```

Once the app has been redirected to DR, there is no instant rollback. Failback
requires the full sequence in Step 6.
