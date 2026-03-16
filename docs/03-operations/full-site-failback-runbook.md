# Full Site Failback Runbook — Azure DR to On-Prem
<!-- CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24 -->

## Document status

| Field | Value |
|---|---|
| Version | 1.0 |
| Created | 2026-03-15 |
| Status | EXECUTED — 2026-03-15 — failback PASS |
| Sprint | S5-01 |
| Prerequisite | Full site failover completed and validated (full-site-failover-runbook.md) |
| Companion | `full-site-failover-runbook.md` |
| Evidence checklist | `docs/05-evidence/full-site-dr-evidence-checklist.md` |

---

## 1. Scope and what this test proves

This runbook covers the **controlled, planned failback** from Azure DR (vm-pg-dr-fce as
primary) back to the on-prem Proxmox environment (pg-primary restored to primary).

**Starting state (post-failover):**
- vm-pg-dr-fce: PostgreSQL primary (R/W), app running in Azure
- pg-primary: PostgreSQL and Keepalived stopped; OS running; WireGuard active
- pg-standby: Running, holding VIP (Keepalived MASTER after pg-primary services stopped)

**What this test proves:**
- pg-primary can be rebuilt from the Azure DR VM via pg_basebackup
- A planned switchover can restore pg-primary to primary role without data loss
- vm-pg-dr-fce can be restored to standby/replica role
- On-prem application resumes serving traffic via the VIP
- End-to-end replication topology is restored to steady state

**What this test does NOT do:**
- Automatic failback (this is always planned and manual)
- Force-restore pg-standby to the new timeline (pg-standby may need separate pg_basebackup
  after failback — documented as post-test cleanup, not a gate for pass/fail)

---

## 2. Architecture — during failback sequence

```
Phase 1: pg-primary rebuilt as standby of Azure VM
  vm-pg-dr-fce (10.200.0.2)  ← replication →  pg-primary (10.0.96.11)
  [primary, R/W]                               [standby, pg_is_in_recovery=t]

Phase 2: Planned switchover back to on-prem
  pg-primary promoted → primary (pg_is_in_recovery=f)
  vm-pg-dr-fce stopped → rebuilt as standby via pg_basebackup

Phase 3: On-prem app path restored
  pg-primary: Keepalived started → VIP 10.0.96.10 returns
  app-onprem: docker compose up → DB_HOST=VIP → pg_is_in_recovery: false

Phase 4: Azure DR restored to replica role
  vm-pg-dr-fce streaming from pg-primary — steady state restored
```

---

## 3. Prerequisites

### 3.1 Hard prerequisites — STOP if any fail

| # | Check | How to verify | Pass condition |
|---|---|---|---|
| H-1 | Failover fully completed | fsdr-app-health-drvm.txt shows pg_is_in_recovery: false | File exists, value is false |
| H-2 | vm-pg-dr-fce app is running | `ssh vm-pg-dr-fce 'sudo docker ps --filter name=clopr2-app-dr'` | Container shown |
| H-3 | pg-primary OS is reachable | `ssh pg-primary 'hostname'` | Returns hostname |
| H-4 | pg-primary PostgreSQL is STOPPED | `ssh pg-primary 'sudo systemctl is-active postgresql'` | inactive |
| H-5 | WireGuard active on pg-primary | `ssh pg-primary 'sudo wg show'` | Peer 10.200.0.2, handshake < 10 min |
| H-6 | Replication user exists on DR VM | `ssh vm-pg-dr-fce 'sudo -u postgres psql -c "SELECT rolname FROM pg_roles WHERE rolname='\''replicator'\'';"'` | replicator row returned |
| H-7 | pg_hba.conf on DR VM allows replication | `ssh vm-pg-dr-fce 'sudo grep replication /etc/postgresql/16/main/pg_hba.conf'` | Entry for replicator / replication |

### 3.2 WireGuard check and recovery

If WireGuard handshake is stale or missing:

```bash
# On pg-primary — restart WireGuard
ssh pg-primary 'sudo systemctl restart wg-quick@wg0 && sudo wg show'
# Alternatively:
ssh pg-primary 'sudo wg-quick down wg0 && sudo wg-quick up wg0 && sudo wg show'
# Expected: peer 20.216.128.32:51820, handshake updates within ~30s
```

### 3.3 Verify pg_hba.conf on DR VM allows pg_basebackup

pg_basebackup requires a replication-capable connection from pg-primary to DR VM.

```bash
ssh vm-pg-dr-fce 'sudo -u postgres psql -c "SELECT pg_reload_conf();" && \
    sudo grep replication /etc/postgresql/16/main/pg_hba.conf'
# Should include a line allowing replicator from 10.200.0.1/32 for replication
```

If missing, add it:

```bash
ssh vm-pg-dr-fce "echo 'host replication replicator 10.200.0.1/32 scram-sha-256' \
    | sudo tee -a /etc/postgresql/16/main/pg_hba.conf && \
    sudo -u postgres psql -c 'SELECT pg_reload_conf();'"
```

---

## 4. Pre-failback checks

### PB-0: MANDATORY — SSH ControlMaster pre-check

> **THIS STEP IS MANDATORY. DO NOT PROCEED IF IT FAILS.**

Clear any stale ControlMaster socket and verify the full SSH chain before touching
any infrastructure. A stale socket on the PVE mux will silently hang all subsequent
SSH commands, corrupting the operation mid-execution.

```bash
# Clear stale socket and verify PVE is reachable
rm -f ~/.ssh/ctl/pve
ssh pve 'echo "PVE OK"'
# Expected: PVE OK within 5 seconds
# If it hangs or errors: STOP. Fix WSL networking or SSH config before continuing.
```

Verify the full chain:

```bash
ssh pg-primary 'echo "pg-primary OK"'
ssh vm-pg-dr-fce 'echo "DR VM OK"'
# Expected: both return within 10 seconds
# vm-pg-dr-fce requires WireGuard active on pg-primary (pg-primary OS must be running)
```

If `vm-pg-dr-fce` is unreachable, check WireGuard:

```bash
ssh pg-primary 'sudo wg show'
# Expected: peer 20.216.128.32:51820, latest-handshake < 3 min
# If stale: ssh pg-primary 'sudo systemctl restart wg-quick@wg0'
```

**Do not continue to PB-1 until all three hosts respond.**

### PB-1: Confirm Azure primary state before starting

```bash
{
    echo "=== FAILBACK PRE-CHECK ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} | tee /tmp/fsdb-precheck.txt

ssh vm-pg-dr-fce '{
    echo "--- DR VM PostgreSQL state ---"
    sudo -u postgres psql -c "SELECT pg_is_in_recovery(), pg_current_wal_lsn(), now();"
    echo "--- DR VM pg_stat_replication (should be empty — no replicas yet) ---"
    sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
    echo "--- App running ---"
    sudo docker ps --filter name=clopr2-app-dr
}' | tee -a /tmp/fsdb-precheck.txt
```

### PB-2: Confirm pg-primary state

```bash
ssh pg-primary '{
    echo "--- pg-primary services ---"
    sudo systemctl is-active postgresql
    sudo systemctl is-active keepalived
    echo "--- WireGuard ---"
    sudo wg show
    echo "--- Disk check ---"
    df -h /var/lib/postgresql/
}' | tee -a /tmp/fsdb-precheck.txt
```

### PB-3: Record failback start timestamp

```bash
FSB_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "FSB_START: $FSB_START" | tee /tmp/fsdb-start-timestamp.txt
```

---

## 5. Failback steps

### Step FB-1: Stop app on vm-pg-dr-fce

Stop writes at the application layer first.

```bash
ssh vm-pg-dr-fce '
    sudo docker stop clopr2-app-dr
    sudo docker rm clopr2-app-dr
    echo "App stopped at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sudo docker ps
' | tee /tmp/fsdb-azure-app-stopped.txt
```

### Step FB-2: Put DR VM PostgreSQL into read-only mode

Prevent any writes during the transition window while pg-primary rebuilds.

```bash
ssh vm-pg-dr-fce '
    sudo -u postgres psql -c "ALTER SYSTEM SET default_transaction_read_only = on;"
    sudo -u postgres psql -c "SELECT pg_reload_conf();"
    echo "DR VM set to read-only at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sudo -u postgres psql -c "SHOW default_transaction_read_only;"
' | tee /tmp/fsdb-drvm-readonly.txt
# Expected: default_transaction_read_only = on
```

### Step FB-3: Rebuild pg-primary as standby of DR VM via pg_basebackup

This wipes pg-primary's current data directory and replaces it with a clean copy
from the DR VM. **This is irreversible on pg-primary.** Proceed only when FB-1 and FB-2
are confirmed.

```bash
# On pg-primary — ensure PostgreSQL is stopped
ssh pg-primary 'sudo systemctl stop postgresql; sudo systemctl is-active postgresql'
# Expected: inactive

# On pg-primary — run pg_basebackup from DR VM
ssh pg-primary '
    echo "Starting pg_basebackup at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Remove old data directory (IRREVERSIBLE — confirm FB-1 and FB-2 done first)
    sudo -u postgres rm -rf /var/lib/postgresql/16/main

    # Pull fresh base backup from DR VM via WireGuard tunnel
    # -R writes recovery configuration (standby.signal + postgresql.auto.conf)
    sudo -u postgres pg_basebackup \
        -h 10.200.0.2 \
        -U replicator \
        -D /var/lib/postgresql/16/main \
        -R -P --wal-method=stream \
        --checkpoint=fast

    echo "pg_basebackup completed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ls /var/lib/postgresql/16/main/standby.signal
    cat /var/lib/postgresql/16/main/postgresql.auto.conf
' | tee /tmp/fsdb-pg-basebackup.txt
# pg_basebackup may take 1-5 min depending on data volume
# Expected: standby.signal present, postgresql.auto.conf contains primary_conninfo
```

If pg_basebackup fails (authentication, connectivity), check:
- WireGuard tunnel is up (`sudo wg show` on pg-primary)
- pg_hba.conf on DR VM (step 3.3)
- Replication password in primary_conninfo matches `pg-replication-password` in Key Vault

### Step FB-4: Start pg-primary as standby

```bash
ssh pg-primary '
    sudo systemctl start postgresql
    sleep 5
    sudo systemctl status postgresql --no-pager
    sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
' | tee /tmp/fsdb-primary-standby-start.txt
# Expected: active, pg_is_in_recovery = t
```

### Step FB-5: Verify pg-primary is streaming from DR VM

```bash
# On vm-pg-dr-fce — check pg_stat_replication
ssh vm-pg-dr-fce '
    echo "pg_stat_replication on DR VM:"
    sudo -u postgres psql -c "
        SELECT client_addr, state, sync_state,
               sent_lsn, replay_lsn,
               (sent_lsn - replay_lsn) AS bytes_lag
        FROM pg_stat_replication;"
' | tee /tmp/fsdb-drvm-replication.txt
# Expected: row with 10.200.0.1 (pg-primary WireGuard IP), state=streaming
# Wait up to 60s for connection to appear
```

### Step FB-6: Wait for pg-primary to fully catch up

```bash
# On vm-pg-dr-fce — monitor lag until it reaches near-zero
for i in $(seq 1 30); do
    ssh vm-pg-dr-fce 'sudo -u postgres psql -tc "
        SELECT client_addr,
               (sent_lsn - replay_lsn) AS bytes_lag
        FROM pg_stat_replication WHERE client_addr = '\''10.200.0.1'\'';" | tr -d " "'
    echo " at $(date +%H:%M:%S)"
    sleep 3
done | tee /tmp/fsdb-catchup-wait.txt
# Proceed when bytes_lag is 0 or single digits (near-zero)
```

### Step FB-7: Execute planned switchover — promote pg-primary

Sequence: stop writes on DR VM → promote pg-primary → pg-primary becomes new primary.

```bash
# STEP 1: Confirm DR VM is read-only (should already be from FB-2)
ssh vm-pg-dr-fce 'sudo -u postgres psql -c "SHOW default_transaction_read_only;"'
# Expected: on

# STEP 2: Promote pg-primary to primary role
ssh pg-primary '
    echo "Promoting pg-primary at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sudo -u postgres psql -c "SELECT pg_promote();"
    sleep 3
    sudo -u postgres psql -c "SELECT pg_is_in_recovery(), pg_current_wal_lsn();"
    ls /var/lib/postgresql/16/main/standby.signal 2>&1
' | tee /tmp/fsdb-primary-promoted.txt
# Expected: pg_promote()=t, pg_is_in_recovery=f, standby.signal: No such file
```

### Step FB-8: Stop and rebuild vm-pg-dr-fce as standby of pg-primary

```bash
# On vm-pg-dr-fce — stop PostgreSQL (it was primary, now must become standby)
ssh vm-pg-dr-fce '
    # Undo read-only setting first (clean config)
    sudo -u postgres psql -c "ALTER SYSTEM RESET default_transaction_read_only;"
    sudo -u postgres psql -c "SELECT pg_reload_conf();"

    sudo systemctl stop postgresql
    echo "DR VM postgres stopped at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Rebuild DR VM as standby of pg-primary
    sudo -u postgres rm -rf /var/lib/postgresql/16/main

    sudo -u postgres pg_basebackup \
        -h 10.200.0.1 \
        -U replicator \
        -D /var/lib/postgresql/16/main \
        -R -P --wal-method=stream \
        --checkpoint=fast

    echo "DR VM pg_basebackup complete at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ls /var/lib/postgresql/16/main/standby.signal
' | tee /tmp/fsdb-drvm-rebuild.txt
```

```bash
# On vm-pg-dr-fce — start as standby
ssh vm-pg-dr-fce '
    sudo systemctl start postgresql
    sleep 5
    sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
' | tee -a /tmp/fsdb-drvm-rebuild.txt
# Expected: t — DR VM is now a replica of pg-primary again
```

### Step FB-9: Verify replication restored on pg-primary

```bash
ssh pg-primary '
    echo "pg_stat_replication on pg-primary:"
    sudo -u postgres psql -c "
        SELECT client_addr, state, sync_state,
               sent_lsn, replay_lsn
        FROM pg_stat_replication;"
' | tee /tmp/fsdb-replication-restored.txt
# Expected: row with 10.200.0.2 (DR VM), state=streaming
```

### Step FB-10: Start Keepalived on pg-primary — VIP returns

```bash
ssh pg-primary '
    sudo systemctl start keepalived
    sleep 8
    sudo systemctl status keepalived --no-pager
    ip addr show eth0 | grep inet
' | tee /tmp/fsdb-vip-returned.txt
# Expected: Keepalived MASTER state, inet 10.0.96.10/16 on eth0
```

> pg-standby will automatically return to BACKUP state after the dead interval (~4s).
> No action needed on pg-standby keepalived.

### Step FB-11: Start app on app-onprem

```bash
ssh -i ~/.ssh/id_ed25519_dr_onprem \
    -o ProxyJump=pve \
    katar711@10.0.96.13 \
    'cd /opt/clopr2/deploy/docker && sudo docker compose up -d && \
     sleep 5 && sudo docker ps' \
    | tee /tmp/fsdb-app-started.txt
```

### Step FB-12: Validate on-prem app health

```bash
# From WSL
curl -s http://10.0.96.13:8080/health | tee /tmp/fsdb-app-health.txt
# Expected:
# {
#   "status": "ok",
#   "db": "ok",
#   "db_host": "10.0.96.10",
#   "pg_is_in_recovery": false,    <-- KEY PROOF: on-prem primary active
#   "app_env": "dev",
#   "ts": "..."
# }
```

### Step FB-13: Record failback completion timestamp

```bash
FSB_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
    echo "FAILBACK COMPLETE"
    echo "FSB_START: $FSB_START"
    echo "FSB_END:   $FSB_END"
    echo "Failback RTO: time from FSB_START to FB-12 (/health 200 on app-onprem)"
} | tee /tmp/fsdb-rto-summary.txt
```

---

## 6. Post-failback state snapshot

```bash
# On pg-primary — full post-failback state
{
    echo "=== POST-FAILBACK STATE ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "--- VIP on pg-primary ---"
    ip addr show eth0 | grep inet
    echo ""
    echo "--- PostgreSQL role ---"
    sudo -u postgres psql -c "SELECT pg_is_in_recovery(), pg_current_wal_lsn();"
    echo ""
    echo "--- Keepalived ---"
    sudo systemctl status keepalived --no-pager | grep -E 'Active|MASTER'
    echo ""
    echo "--- Replication (expect DR VM 10.200.0.2 + standby 10.0.96.14 if reconnected) ---"
    sudo -u postgres psql -c "SELECT client_addr, state, sync_state FROM pg_stat_replication ORDER BY client_addr;"
    echo ""
    echo "--- WireGuard ---"
    sudo wg show
} | tee /tmp/fsdb-post-failback-snapshot.txt

# From WSL:
curl -s http://10.0.96.13:8080/health | tee /tmp/fsdb-final-app-health.txt
```

---

## 7. pg-standby status after failback

pg-standby (10.0.96.14) was following pg-primary's original timeline. After pg-primary
was rebuilt from the DR VM (new timeline), pg-standby cannot automatically reconnect —
it is on the old timeline divergence point.

**Check pg-standby status:**

```bash
ssh -i ~/.ssh/id_ed25519_dr_onprem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11" \
    katar711@10.0.96.14 '
    sudo systemctl status postgresql --no-pager
    sudo -u postgres psql -c "SELECT pg_is_in_recovery();" 2>&1 || echo "PostgreSQL not running or error"
'
```

If pg-standby cannot reconnect, rebuild it from pg-primary:

```bash
ssh -i ~/.ssh/id_ed25519_dr_onprem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11" \
    katar711@10.0.96.14 '
    sudo systemctl stop postgresql
    sudo -u postgres rm -rf /var/lib/postgresql/16/main
    sudo -u postgres pg_basebackup \
        -h 10.0.96.11 -U replicator \
        -D /var/lib/postgresql/16/main \
        -R -P --wal-method=stream --checkpoint=fast
    sudo systemctl start postgresql
    sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
'
# Expected: t — pg-standby is now streaming from restored pg-primary
```

> This step is desirable but NOT a gate for the failback pass/fail verdict.
> Full HA with both replicas streaming can be restored in a follow-up step.

---

## 8. Rollback considerations

### If FB-3 (pg_basebackup on pg-primary) fails mid-way

Data directory on pg-primary may be partially wiped. Do NOT panic.
- The authoritative data is on vm-pg-dr-fce (still primary, still R/W if DB not stopped)
- If DR VM postgres is running: data is safe. Retry pg_basebackup.
- Do not start pg-primary PostgreSQL until pg_basebackup completes successfully.

### If FB-7 (promote pg-primary) fails

- pg-primary stays as standby of DR VM — no data at risk
- DR VM remains primary (the app should be stopped — FB-1 — so no new writes)
- Investigate error, retry promotion
- DR VM read-only setting (FB-2) can be reversed: `ALTER SYSTEM RESET default_transaction_read_only;`

### If FB-8 (rebuild DR VM as standby) fails

- pg-primary is now primary (FB-7 succeeded)
- DR VM may be in a partially wiped state — retry pg_basebackup
- This is safe to retry as many times as needed

---

## 9. Evidence files to capture

All files to be exported to `docs/05-evidence/full-site-dr-validation/` in the repo.

| File | Source | Content |
|---|---|---|
| `fsdb-precheck.txt` | vm-pg-dr-fce + pg-primary | Pre-failback state of both systems |
| `fsdb-start-timestamp.txt` | local | ISO timestamp at failback start |
| `fsdb-azure-app-stopped.txt` | vm-pg-dr-fce | App container stopped confirmation |
| `fsdb-drvm-readonly.txt` | vm-pg-dr-fce | Read-only mode confirmed |
| `fsdb-pg-basebackup.txt` | pg-primary | pg_basebackup output — completion + standby.signal |
| `fsdb-primary-standby-start.txt` | pg-primary | pg_is_in_recovery=t after basebackup start |
| `fsdb-drvm-replication.txt` | vm-pg-dr-fce | pg_stat_replication showing pg-primary streaming |
| `fsdb-catchup-wait.txt` | vm-pg-dr-fce | Bytes lag progression to near-zero |
| `fsdb-primary-promoted.txt` | pg-primary | pg_promote()=t, pg_is_in_recovery=f |
| `fsdb-drvm-rebuild.txt` | vm-pg-dr-fce | DR VM rebuilt as standby |
| `fsdb-replication-restored.txt` | pg-primary | pg_stat_replication showing DR VM streaming |
| `fsdb-vip-returned.txt` | pg-primary | Keepalived MASTER, VIP 10.0.96.10 on eth0 |
| `fsdb-app-started.txt` | app-onprem | docker compose up confirmation |
| `fsdb-app-health.txt` | WSL | /health — pg_is_in_recovery: false |
| `fsdb-rto-summary.txt` | local | Start/end timestamps, RTO summary |
| `fsdb-post-failback-snapshot.txt` | pg-primary | Full post-failback system state |
| `fsdb-final-app-health.txt` | WSL | Final /health confirmation |

---

## 10. Acceptance criteria summary

| Criterion | Pass condition |
|---|---|
| Pre-checks | All H-1 through H-7 pass |
| Azure app stopped | docker ps shows no clopr2-app-dr container |
| pg_basebackup completes | No errors; standby.signal present on pg-primary |
| pg-primary starts as standby | `pg_is_in_recovery()` = t |
| DR VM replication shows pg-primary | `pg_stat_replication` has 10.200.0.1, streaming |
| pg-primary promoted | `pg_is_in_recovery()` = **f** |
| VIP returns to pg-primary | `ip addr show eth0` shows 10.0.96.10 |
| On-prem app healthy | `curl http://10.0.96.13:8080/health` → 200 |
| App confirms on-prem primary | `pg_is_in_recovery: false` in JSON |
| DR VM restored as replica | `pg_is_in_recovery()` = t on vm-pg-dr-fce |
| Replication to DR VM | `pg_stat_replication` on pg-primary shows 10.200.0.2 streaming |
| Failback RTO documented | Timestamp delta in fsdb-rto-summary.txt |
| Evidence complete | All 17 files present in repo |
