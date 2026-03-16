# Full Site Failover Runbook — On-Prem to Azure DR
<!-- CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24 -->

## Document status

| Field | Value |
|---|---|
| Version | 1.0 |
| Created | 2026-03-15 |
| Status | EXECUTED — 2026-03-15 — failover PASS |
| Sprint | S5-01 |
| Failover type | Full site failover — DB promotion + Azure-side app activation |
| Prerequisite | S4-03 PASSED (on-prem HA validated, commit db432bb) |
| Companion | `full-site-failback-runbook.md` |
| Evidence checklist | `docs/05-evidence/full-site-dr-evidence-checklist.md` |

---

## 1. Scope and what this test proves

This runbook covers a **controlled, planned full site failover** from the on-prem Proxmox
environment to the Azure France Central DR site.

**What this test proves:**
- PostgreSQL DR replica (vm-pg-dr-fce) can be promoted to a writable primary
- The application can be run in Azure against the promoted DB
- Application health confirms Azure DB is primary (`pg_is_in_recovery: false`)
- RPO and RTO for full site failover are measured and documented

**What this test does NOT include:**
- Automatic failover detection (this is a planned/manual operation)
- Azure Traffic Manager (not deployed — de-scoped for this sprint)
- pg-standby promotion (pg-standby remains idle on-prem during outage)
- Zero RPO guarantee (async replication means lag = potential data loss window)

**What "site outage" means in this test:**
PostgreSQL and Keepalived services are stopped on pg-primary. The pg-primary OS and
WireGuard service remain running so the SSH chain to the DR VM stays intact. This is
sufficient to prove DR promotion without losing access. A full OS shutdown is noted as
an optional variation.

---

## 2. Architecture — before and after failover

### Before failover (steady state)

| Component | IP | Role |
|---|---|---|
| pg-primary | 10.0.96.11 | PostgreSQL 16 primary (R/W), Keepalived MASTER, WireGuard peer 10.200.0.1 |
| pg-standby | 10.0.96.14 | PostgreSQL 16 standby (replica) |
| app-onprem | 10.0.96.13 | FastAPI in Docker, DB_HOST=10.0.96.10 (VIP) |
| VIP | 10.0.96.10 | On pg-primary |
| vm-pg-dr-fce | 10.200.0.2 | PostgreSQL 16 standby, streaming replica via WireGuard |

### After failover

| Component | IP | Role |
|---|---|---|
| pg-primary | 10.0.96.11 | STOPPED (postgres + keepalived) |
| pg-standby | 10.0.96.14 | Running, idle — VIP holder via keepalived MASTER |
| app-onprem | 10.0.96.13 | STOPPED |
| vm-pg-dr-fce | 10.200.0.2 | PostgreSQL 16 PRIMARY (R/W), `pg_is_in_recovery()=f` |
| Azure app | 10.200.0.2:8080 | FastAPI in Docker, DB_HOST=127.0.0.1 (localhost) |

---

## 3. SSH access to vm-pg-dr-fce

The DR VM's NSG allows SSH (port 22) from `10.200.0.1/32` only (pg-primary WireGuard IP).
Access must go through pg-primary as a relay.

```
WSL → PVE (10.0.10.71) [root, id_ed25519_dr_pve]
    → pg-primary (10.0.96.11) [katar711, id_ed25519_dr_onprem]
    → vm-pg-dr-fce (10.200.0.2) [azureuser, id_ed25519_dr]
```

SSH config snippet (add to `~/.ssh/config`):

```sshconfig
Host pve
    HostName 10.0.10.71
    User root
    IdentityFile ~/.ssh/id_ed25519_dr_pve

Host pg-primary
    HostName 10.0.96.11
    User katar711
    IdentityFile ~/.ssh/id_ed25519_dr_onprem
    ProxyJump pve

Host vm-pg-dr-fce
    HostName 10.200.0.2
    User azureuser
    IdentityFile ~/.ssh/id_ed25519_dr
    ProxyCommand ssh -W %h:%p -i ~/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11
```

Test the chain before the test day:
```bash
ssh vm-pg-dr-fce 'hostname && whoami && sudo -u postgres psql -c "SELECT pg_is_in_recovery();"'
# Expected: vm-pg-dr-fce, azureuser, t
```

---

## 4. Prerequisites

### 4.1 Hard prerequisites — STOP if any fail

| # | Check | How to verify | Pass condition |
|---|---|---|---|
| H-1 | vm-pg-dr-fce is running | Azure Portal → vm-pg-dr-fce → Overview | Status = Running |
| H-2 | Auto-shutdown disabled or outside window | Azure Portal → vm-pg-dr-fce → Auto-shutdown | Disabled, or scheduled after test window ends |
| H-3 | WireGuard tunnel active | On pg-primary: `sudo wg show` | peer 20.216.128.32:51820, latest-handshake < 3 min |
| H-4 | DR replica streaming | On pg-primary: `sudo -u postgres psql -c "SELECT client_addr, state FROM pg_stat_replication WHERE client_addr = '10.200.0.2';"` | Row present, state = streaming |
| H-5 | Replication lag | On vm-pg-dr-fce: `sudo -u postgres psql -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"` | lag < 5 minutes |
| H-6 | SSH chain to DR VM works | `ssh vm-pg-dr-fce 'hostname'` | Returns hostname |
| H-7 | Docker installed on DR VM | `ssh vm-pg-dr-fce 'docker --version'` | Docker version printed |
| H-8 | App image built on DR VM | `ssh vm-pg-dr-fce 'sudo docker image ls clopr2-app'` | Image listed |
| H-9 | On-prem baseline healthy | `curl -s http://10.0.96.13:8080/health` | HTTP 200, `pg_is_in_recovery: false` |

### 4.2 Pre-test-day setup — do BEFORE test day (one-time)

Run these steps once, well before the test day. They require an active WireGuard tunnel.

#### A. Start and verify DR VM

```bash
# If vm-pg-dr-fce is deallocated, start it via Azure Portal or az CLI:
az vm start --resource-group rg-clopr2-katar711-fce --name vm-pg-dr-fce

# Wait ~2 min, then verify WireGuard handshake on pg-primary:
ssh pg-primary 'sudo wg show'
# Expected: latest handshake < 3 min for peer 20.216.128.32:51820
```

#### B. Install Docker on vm-pg-dr-fce

```bash
ssh vm-pg-dr-fce 'bash -s' << 'EOF'
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu jammy stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker azureuser
docker --version
EOF
```

#### C. Copy app source to DR VM

Run from WSL workstation (not from inside a VM):

```bash
# Paths assume WSL mount of Windows project directory
scp -r \
    /mnt/c/Users/akata/Documents/Projects/CLOPR2/clopr2-secure-hybrid-dr-gateway/app/ \
    vm-pg-dr-fce:/home/azureuser/clopr2-app/
```

#### D. Write .env for Azure-side app

```bash
# IMPORTANT: DB_HOST=127.0.0.1 — app connects to promoted DB on same VM
# app_db_password = the password configured for appuser during initial deployment
ssh vm-pg-dr-fce 'cat > /home/azureuser/clopr2-app/.env' << 'EOF'
APP_ENV=dr-azure
APP_PORT=8000
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=appdb
DB_USER=appuser
DB_PASSWORD=AppPass2026
EOF
chmod 600 /home/azureuser/clopr2-app/.env
```

Replace `AppPass2026` with the actual password used during `app_db_setup.yml` playbook execution.

#### E. Build app Docker image on DR VM

```bash
ssh vm-pg-dr-fce 'cd /home/azureuser/clopr2-app && sudo docker build -t clopr2-app:dr .'
# Expected: Successfully built <image_id>
# This takes ~3 min on first run; subsequent builds are fast
```

#### F. Verify the image and .env before test day

```bash
ssh vm-pg-dr-fce '
    echo "=== Image ===" && sudo docker image ls clopr2-app
    echo "=== .env ===" && cat /home/azureuser/clopr2-app/.env
    echo "=== DR VM PG status ===" && sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
'
# Expected: image listed, .env shows DB_HOST=127.0.0.1, pg_is_in_recovery = t
```

---

## 5. Pre-checks (run immediately before failover)

Run all pre-checks in sequence. Record all output.

### PC-0: MANDATORY — SSH ControlMaster pre-check

> **THIS STEP IS MANDATORY. DO NOT PROCEED IF IT FAILS.**

The SSH ControlMaster socket for PVE (`~/.ssh/ctl/pve`) goes stale when WSL changes
network context (sleep, VPN reconnect, network switch). A stale socket causes all
subsequent SSH commands to hang silently, adding 45+ minutes to RTO. This was the
sole cause of the 48m 42s RTO observed in S4-09. The actual operation is ~3 minutes.

**Run this before anything else:**

```bash
# Clear the stale socket and verify PVE is reachable
rm -f ~/.ssh/ctl/pve
ssh pve 'echo "PVE OK"'
# Expected: PVE OK within 5 seconds
# If it hangs or errors: STOP. Fix WSL networking or SSH config before continuing.
```

Then verify the full SSH chain is alive:

```bash
ssh pg-primary 'echo "pg-primary OK"'
ssh vm-pg-dr-fce 'echo "DR VM OK"'
# Expected: both return within 10 seconds
# vm-pg-dr-fce requires WireGuard to be active on pg-primary
```

If `vm-pg-dr-fce` check fails, verify WireGuard first:

```bash
ssh pg-primary 'sudo wg show'
# Expected: peer 20.216.128.32:51820, latest-handshake < 3 min
# If stale: ssh pg-primary 'sudo systemctl restart wg-quick@wg0'
```

**Do not continue to PC-1 until all three hosts respond.**

### PC-1: Capture baseline timestamps and replication state

```bash
# On pg-primary — save full pre-check snapshot
{
    echo "=== FULL SITE FAILOVER PRE-CHECK ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "--- pg_stat_replication ---"
    sudo -u postgres psql -c "
        SELECT client_addr, state, sync_state,
               pg_current_wal_lsn() AS primary_lsn,
               sent_lsn, replay_lsn,
               (pg_current_wal_lsn() - replay_lsn) AS bytes_lag
        FROM pg_stat_replication;"
    echo ""
    echo "--- WireGuard ---"
    sudo wg show
    echo ""
    echo "--- Keepalived ---"
    sudo systemctl status keepalived --no-pager
    echo ""
    echo "--- VIP ---"
    ip addr show eth0 | grep 'inet '
} | tee /tmp/fsdr-precheck-primary.txt
```

```bash
# From WSL — app health
curl -s http://10.0.96.13:8080/health | tee /tmp/fsdr-precheck-app-health.txt
# Expected: HTTP 200, pg_is_in_recovery: false
```

```bash
# On vm-pg-dr-fce — DR VM baseline
ssh vm-pg-dr-fce '{
    echo "=== DR VM PRE-CHECK ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sudo -u postgres psql -c "SELECT pg_is_in_recovery(), now() - pg_last_xact_replay_timestamp() AS lag;"
    sudo docker image ls clopr2-app
}' | tee /tmp/fsdr-precheck-drvm.txt
```

### PC-2: Verify all hard prerequisites pass

Work through section 4.1 checklist H-1 through H-9. Do not proceed if any fail.

### PC-3: CRITICAL — Open persistent SSH session to vm-pg-dr-fce NOW

**Do this before stopping pg-primary.** This session is your access path to the DR VM
for the promotion and app start steps. Keep this terminal open throughout the test.

```bash
# Open in a DEDICATED terminal window — do not close
ssh vm-pg-dr-fce
# Verify:
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"  # must be t
```

### PC-4: Record failover start timestamp

```bash
FSO_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "FSO_START: $FSO_START" | tee /tmp/fsdr-start-timestamp.txt
```

---

## 6. Failover steps

### Step FS-1: Stop on-prem application

Stop the app-onprem container cleanly before stopping the DB. This prevents the app
from generating 503 errors and logging confusing noise during the transition.

```bash
# On app-onprem
ssh -i ~/.ssh/id_ed25519_dr_onprem \
    -o ProxyJump=pve \
    katar711@10.0.96.13 \
    'cd /opt/clopr2/deploy/docker && sudo docker compose down; echo "App stopped at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"' \
    | tee /tmp/fsdr-app-stopped.txt
```

### Step FS-2: Record final LSN on pg-primary

```bash
# On pg-primary — capture the last known WAL position before stopping
ssh pg-primary 'sudo -u postgres psql -c "
    SELECT
        pg_current_wal_lsn()   AS final_lsn,
        now()                  AS captured_at,
        client_addr,
        replay_lsn,
        (pg_current_wal_lsn() - replay_lsn) AS bytes_lag
    FROM pg_stat_replication WHERE client_addr = '\''10.200.0.2'\'';"' \
    | tee /tmp/fsdr-final-lsn.txt
```

Save `final_lsn` value — you will compare it against DR VM's replay position in FS-4.

### Step FS-3: Stop pg-primary services (simulate site outage)

```bash
# On pg-primary — stop PostgreSQL and Keepalived
# WireGuard service is NOT stopped — keeps SSH chain to DR VM intact
ssh pg-primary '
    sudo systemctl stop postgresql
    sudo systemctl stop keepalived
    echo "Services stopped at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sudo systemctl status postgresql --no-pager
    sudo systemctl status keepalived --no-pager
' | tee /tmp/fsdr-primary-stopped.txt
# Expected: both services show inactive (dead)
```

> **Note:** pg-standby keepalived will detect the MASTER going silent and take the VIP
> (VRRP election). This is expected and correct — the on-prem VIP floating is not relevant
> to the Azure failover path. pg-standby enters MASTER state for the VIP; pg-standby
> PostgreSQL remains in read-only replica mode (pg_is_in_recovery=t, no writes accepted).

### Step FS-4: Wait for DR VM to apply all remaining WAL

In your **persistent DR VM session**, run:

```bash
# On vm-pg-dr-fce — wait for replay to reach or pass final_lsn from FS-2
# Run until replay_lsn stops advancing (source is now stopped)
for i in $(seq 1 30); do
    REPLAY=$(sudo -u postgres psql -tc "SELECT pg_last_wal_replay_lsn();" | tr -d ' \n')
    echo "$(date +%H:%M:%S) replay_lsn=$REPLAY"
    sleep 2
done | tee /tmp/fsdr-replay-wait.txt

# Compare final replay_lsn against final_lsn from FS-2.
# The difference (bytes) is the RPO window.
```

When the replay_lsn stops advancing, the DR VM has applied all available WAL.

### Step FS-5: Promote vm-pg-dr-fce to primary

In your **persistent DR VM session**:

```bash
# On vm-pg-dr-fce — promote to writable primary
sudo -u postgres psql -c "SELECT pg_promote();"
# Expected output:
#  pg_promote
# ────────────
#  t

sleep 3

# Verify promotion:
{
    echo "=== DR VM PROMOTED ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "--- pg_is_in_recovery ---"
    sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
    # Expected: f

    echo ""
    echo "--- pg_current_wal_lsn (confirms R/W capability) ---"
    sudo -u postgres psql -c "SELECT pg_current_wal_lsn(), now();"

    echo ""
    echo "--- standby.signal (must be absent) ---"
    ls /var/lib/postgresql/16/main/standby.signal 2>&1
    # Expected: No such file or directory
} | tee /tmp/fsdr-promoted.txt
```

**Do not proceed to FS-6 if `pg_is_in_recovery()` is still `t`.**
If promotion failed, see Section 8 (Rollback).

### Step FS-6: Confirm write capability

```bash
# On vm-pg-dr-fce — prove the DB accepts writes
sudo -u postgres psql << 'EOF'
CREATE TABLE IF NOT EXISTS _fsdr_promote_test (ts timestamptz DEFAULT now());
INSERT INTO _fsdr_promote_test VALUES (DEFAULT);
SELECT * FROM _fsdr_promote_test;
DROP TABLE _fsdr_promote_test;
EOF
# Expected: INSERT 0 1, SELECT 1 row, DROP TABLE
```

Save terminal output to `/tmp/fsdr-write-test.txt`.

### Step FS-7: Start app on vm-pg-dr-fce

> **Note (from execution 2026-03-15):** Use `--network host` so that `DB_HOST=127.0.0.1` in the .env resolves to the host's PostgreSQL.
> Without `--network host`, Docker bridge mode isolates the container's loopback from the host, causing `Connection refused` on port 5432.
> With `--network host`, the app port is exposed directly on the host (port 8000, not 8080), so health checks use `localhost:8000`.

```bash
# On vm-pg-dr-fce — start app container
sudo docker run -d \
    --name clopr2-app-dr \
    --restart unless-stopped \
    --network host \
    --env-file /home/azureuser/clopr2-app/.env \
    clopr2-app:dr

sleep 5
sudo docker ps --filter name=clopr2-app-dr
```

### Step FS-8: Validate app health from DR VM

```bash
# On vm-pg-dr-fce
curl -s http://localhost:8000/health | tee /tmp/fsdr-app-health-drvm.txt

# Expected JSON:
# {
#   "status": "ok",
#   "db": "ok",
#   "db_host": "127.0.0.1",
#   "pg_is_in_recovery": false,    <-- KEY PROOF: Azure DB is primary
#   "app_env": "dr-azure",
#   "ts": "..."
# }
```

`pg_is_in_recovery: false` is the critical pass criterion. It confirms the Azure-side
app is connected to a writable primary PostgreSQL instance.

### Step FS-9: Validate from WSL via SSH port-forward

This provides external validation without opening the DR VM's app port in the NSG.

```bash
# Local WSL — forward DR VM port 8080 to local 18080
ssh -L 18000:localhost:8000 -N vm-pg-dr-fce &
PORT_FWD_PID=$!
sleep 2

curl -s http://localhost:18000/health | tee /tmp/fsdr-app-health-local.txt

kill $PORT_FWD_PID
```

### Step FS-10: Record failover completion and RPO/RTO

```bash
FSO_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
    echo "FAILOVER COMPLETE"
    echo "FSO_START: $FSO_START"
    echo "FSO_END:   $FSO_END"
    echo ""
    echo "RTO: time from FS-3 (services stopped) to FS-8 (app /health 200)"
    echo "RPO: bytes_lag recorded in FS-4 (bytes not yet applied at promotion time)"
    echo ""
    echo "See /tmp/fsdr-replay-wait.txt for final replay_lsn vs final_lsn comparison"
} | tee /tmp/fsdr-rto-summary.txt
```

---

## 7. Post-failover state snapshot

```bash
# On vm-pg-dr-fce — full post-failover state
{
    echo "=== POST-FAILOVER STATE ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "--- PostgreSQL role ---"
    sudo -u postgres psql -c "SELECT pg_is_in_recovery(), pg_current_wal_lsn();"
    echo ""
    echo "--- pg_stat_replication (no rows expected — on-prem is down) ---"
    sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
    echo ""
    echo "--- App container ---"
    sudo docker ps --filter name=clopr2-app-dr
    echo ""
    echo "--- App /health ---"
    curl -s http://localhost:8000/health
} | tee /tmp/fsdr-post-failover-snapshot.txt
```

---

## 8. Rollback

### Before app is started (FS-7 not yet done)

If promotion completed (FS-5 passed) but the app has NOT been started:
- Data is at the DR VM — do not restart pg-primary
- Fix the issue (Docker, image, .env) and retry from FS-7

If promotion FAILED (pg_is_in_recovery still `t`):
- DR VM is still a replica — no data at risk
- On-prem data is intact (services stopped but data on disk)
- Restart pg-primary services:
  ```bash
  ssh pg-primary 'sudo systemctl start postgresql && sudo systemctl start keepalived'
  ```
- WireGuard tunnel will resume; DR VM should reconnect as replica automatically
- Investigate promotion failure before retrying

### After app is started (FS-7 done)

Once the Azure-side app is running and writing to the promoted DR VM, there is no
instant rollback. You must proceed through the full failback sequence in
`full-site-failback-runbook.md`.

---

## 9. Evidence files to capture

All files to be exported to `docs/05-evidence/full-site-dr-validation/` in the repo.
See `docs/05-evidence/full-site-dr-evidence-checklist.md` for the complete checklist.

| File | Source | Content |
|---|---|---|
| `fsdr-precheck-primary.txt` | pg-primary | pg_stat_replication, WireGuard, Keepalived, VIP baseline |
| `fsdr-precheck-app-health.txt` | WSL | /health before failover — pg_is_in_recovery: false |
| `fsdr-precheck-drvm.txt` | vm-pg-dr-fce | pg_is_in_recovery=t, lag, image present |
| `fsdr-start-timestamp.txt` | local | ISO timestamp at failover start |
| `fsdr-app-stopped.txt` | app-onprem | Confirmation app container stopped |
| `fsdr-final-lsn.txt` | pg-primary | final pg_current_wal_lsn + bytes_lag before stop |
| `fsdr-primary-stopped.txt` | pg-primary | systemctl status after stop — inactive (dead) |
| `fsdr-replay-wait.txt` | vm-pg-dr-fce | Replay LSN progression after source stopped |
| `fsdr-promoted.txt` | vm-pg-dr-fce | pg_is_in_recovery=f, pg_current_wal_lsn, no standby.signal |
| `fsdr-write-test.txt` | vm-pg-dr-fce | CREATE/INSERT/DROP output |
| `fsdr-app-health-drvm.txt` | vm-pg-dr-fce | /health JSON — pg_is_in_recovery: false |
| `fsdr-app-health-local.txt` | WSL | /health via SSH port-forward |
| `fsdr-rto-summary.txt` | local | Start/end timestamps, RTO/RPO summary |
| `fsdr-post-failover-snapshot.txt` | vm-pg-dr-fce | Full post-failover state |

---

## 10. Acceptance criteria summary

| Criterion | Pass condition |
|---|---|
| Pre-checks | All H-1 through H-9 pass |
| pg-primary stopped | `systemctl status postgresql` = inactive (dead) |
| DR VM promoted | `pg_is_in_recovery()` = **f** |
| standby.signal absent | `ls /var/lib/postgresql/16/main/standby.signal` → No such file |
| Write test | INSERT 0 1 without error |
| App starts | `docker ps` shows running clopr2-app-dr |
| App /health | HTTP 200 |
| App confirms primary | `pg_is_in_recovery: false` in JSON |
| RTO documented | Timestamp delta in fsdr-rto-summary.txt |
| Evidence complete | All 14 files present in repo |
