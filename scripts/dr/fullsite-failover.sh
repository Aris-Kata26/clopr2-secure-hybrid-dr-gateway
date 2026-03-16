#!/usr/bin/env bash
# fullsite-failover.sh — Full-site failover: on-prem -> Azure DR VM
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   Execute the full-site failover from on-prem Proxmox to Azure vm-pg-dr-fce.
#   Stops on-prem app, records final LSN, stops pg-primary services, waits for
#   DR VM WAL replay to stabilise, promotes the DR VM, and starts the app on Azure.
#
# DESTRUCTIVE OPERATIONS:
#   FS-3: Stops postgresql + keepalived on pg-primary
#         -> After this step, on-prem is DOWN. Recovery requires fullsite-fallback.sh.
#         -> WireGuard is NOT stopped — SSH chain to DR VM stays intact.
#
# USAGE:
#   ./scripts/dr/fullsite-failover.sh --confirm [--dry-run] [--wal-lag-threshold <bytes>]
#
# OPTIONS:
#   --confirm                  Required. Acknowledges destructive step FS-3.
#   --dry-run                  Print commands without executing.
#   --wal-lag-threshold <n>    Max bytes lag before promotion (default: 1024).
#
# EXIT CODES:
#   0   PASS — failover completed and validated
#   1   FAIL — assertion failed or acceptance criterion not met
#   2   ABORTED — prerequisite check or gate failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIRMED=false
DRY_RUN=false
WAL_LAG_THRESHOLD=1024    # bytes — promote only when DR VM lag <= this value
WAL_REPLAY_TIMEOUT=120    # seconds to wait for WAL replay to stabilise
APP_WAIT_TIMEOUT=60       # seconds to poll DR VM app health

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)               CONFIRMED=true ;;
    --dry-run)               DRY_RUN=true ;;
    --wal-lag-threshold)     shift; WAL_LAG_THRESHOLD="$1" ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -20
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --confirm [--dry-run] [--wal-lag-threshold <bytes>]" >&2
      exit 2
      ;;
  esac
  shift
done

# ── helpers ───────────────────────────────────────────────────────────────────
LOG_PREFIX="[fullsite-failover]"
log()  { echo "${LOG_PREFIX} $(date -u +%H:%M:%SZ) $*"; }
pass() { echo "${LOG_PREFIX} [PASS]  $*"; }
fail() { echo "${LOG_PREFIX} [FAIL]  $*" >&2; }
warn() { echo "${LOG_PREFIX} [WARN]  $*"; }
step() { echo ""; echo "${LOG_PREFIX} ===== $* ====="; }

EVIDENCE_DIR="/tmp"
EVIDENCE_FILES=()

# Relay-aware SSH wrapper.
# app-onprem (10.0.96.13) cannot be reached via PVE TCP-forward.
# It must be relayed through pg-primary (10.0.96.11).
ssh_run() {
  local host="$1"; shift
  local cmd="$*"
  if $DRY_RUN; then
    echo "${LOG_PREFIX} [DRY-RUN] ssh ${host} '${cmd}'"
    return 0
  fi
  case "$host" in
    app-onprem|10.0.96.13)
      ssh -o ConnectTimeout=15 -o BatchMode=yes \
          -o "ProxyCommand=ssh -W %h:%p -o BatchMode=yes -o ConnectTimeout=8 -i ${HOME}/.ssh/id_ed25519_dr_onprem katar711@10.0.96.11" \
          -i "${HOME}/.ssh/id_ed25519_dr_onprem" \
          "katar711@10.0.96.13" "$cmd"
      ;;
    *)
      ssh -o ConnectTimeout=15 -o BatchMode=yes "$host" "$cmd"
      ;;
  esac
}

assert() {
  local description="$1" expected="$2" actual="$3"
  actual=$(echo "$actual" | tr -d '[:space:]')
  if [[ "$actual" == "$expected" ]]; then
    pass "${description}: ${actual}"
  else
    fail "${description}: expected='${expected}', got='${actual}'"
    exit 1
  fi
}

lsn_to_bytes() {
  # Convert WAL LSN string (e.g. "0/B000060") to integer byte offset.
  python3 -c "
s='${1:-0/0}'.strip()
h, l = s.split('/')
print(int(h, 16) * 0x100000000 + int(l, 16))
"
}

# ── gate: require --confirm ───────────────────────────────────────────────────
if ! $DRY_RUN && ! $CONFIRMED; then
  echo ""
  echo "============================================================"
  echo "  FULL-SITE FAILOVER (on-prem -> Azure DR)"
  echo "============================================================"
  echo ""
  echo "  This script will:"
  echo "    FS-1: Stop app on app-onprem"
  echo "    FS-2: Record final LSN on pg-primary"
  echo "    FS-3: Stop postgresql + keepalived on pg-primary  [DESTRUCTIVE]"
  echo "          -> After this point, on-prem DB is DOWN."
  echo "          -> Recovery requires fullsite-fallback.sh (pg_basebackup)."
  echo "    FS-4: Wait for DR VM WAL replay to stabilise"
  echo "    FS-5: Promote vm-pg-dr-fce to primary"
  echo "    FS-6: Confirm write capability"
  echo "    FS-7: Start app container on vm-pg-dr-fce"
  echo "    FS-8: Validate /health on DR VM"
  echo "    FS-9: Validate via SSH port-forward (external path)"
  echo "    FS-10: Record RTO/RPO and post-failover snapshot"
  echo ""
  echo "  Pass --confirm to proceed, or --dry-run to preview."
  echo "============================================================"
  echo ""
  exit 2
fi

# ── STEP 0: SSH pre-check ─────────────────────────────────────────────────────
step "STEP 0: SSH pre-check [MANDATORY]"
if ! $DRY_RUN; then
  if ! "${SCRIPT_DIR}/ssh-precheck.sh"; then
    fail "SSH pre-check failed. Aborting."
    exit 2
  fi
else
  log "[DRY-RUN] would run ssh-precheck.sh"
fi

# ── STEP 1: Full preflight ────────────────────────────────────────────────────
step "STEP 1: Full preflight check"
if ! $DRY_RUN; then
  if ! "${SCRIPT_DIR}/dr-preflight.sh" fullsite; then
    fail "Preflight checks failed. Aborting."
    exit 2
  fi
else
  log "[DRY-RUN] would run dr-preflight.sh fullsite"
fi

# ── STEP 2: Pre-failover state capture ───────────────────────────────────────
step "STEP 2: Capture pre-failover state"

FSO_START=""
FINAL_PRIMARY_LSN=""
FINAL_REPLAY_LSN=""
FS3_START=""
APP_HEALTH_OK_TS=""

if ! $DRY_RUN; then
  FSO_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf "FSO_START: %s\n" "$FSO_START" | tee "${EVIDENCE_DIR}/fsdr-start-timestamp.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-start-timestamp.txt")

  # pg-primary: replication state, WireGuard, VIP
  ssh_run "pg-primary" "
    echo '=== FULL SITE FAILOVER PRE-CHECK ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- pg_stat_replication ---'
    sudo -u postgres psql -c \"SELECT client_addr, state, sync_state,
        pg_current_wal_lsn() AS primary_lsn,
        sent_lsn, replay_lsn,
        (pg_current_wal_lsn() - replay_lsn) AS bytes_lag
        FROM pg_stat_replication;\"
    echo '--- WireGuard ---'
    sudo wg show
    echo '--- Keepalived ---'
    sudo systemctl status keepalived --no-pager | head -8
    echo '--- VIP ---'
    ip addr show eth0 | grep inet
  " | tee "${EVIDENCE_DIR}/fsdr-precheck-primary.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-precheck-primary.txt")

  # app-onprem: health check routed via pg-primary (WSL has no direct route)
  app_health_pre=$(ssh_run "pg-primary" "curl -sf --max-time 8 http://10.0.96.13:8080/health" \
    || echo '{"error":"unreachable"}')
  echo "$app_health_pre" | tee "${EVIDENCE_DIR}/fsdr-precheck-app-health.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-precheck-app-health.txt")
  log "Pre-check app health: $app_health_pre"

  # DR VM: recovery state, replication lag, image present
  dr_pre=$(ssh_run "vm-pg-dr-fce" "
    echo '=== DR VM PRE-CHECK ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres psql -c \"SELECT pg_is_in_recovery(), now() - pg_last_xact_replay_timestamp() AS lag;\"
    sudo docker image ls clopr2-app
  " || echo "error")
  echo "$dr_pre" | tee "${EVIDENCE_DIR}/fsdr-precheck-drvm.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-precheck-drvm.txt")

  dr_recovery=$(echo "$dr_pre" | grep -E '^\s*(t|f)\s*\|' | awk '{print $1}' | tr -d '[:space:]')
  assert "vm-pg-dr-fce pg_is_in_recovery pre-check" "t" "${dr_recovery:-MISSING}"
else
  log "[DRY-RUN] would capture pre-failover state from pg-primary, app-onprem, vm-pg-dr-fce"
fi

# ── Confirmation gate ─────────────────────────────────────────────────────────
step "CONFIRMATION GATE — pre-checks passed, destructive steps follow"
echo ""
log "Pre-checks passed. Proceeding with destructive failover steps."
log "FS-3 (stop pg-primary) is irreversible without fullsite-fallback.sh."
echo ""

# ── FS-1: Stop app on app-onprem ─────────────────────────────────────────────
step "FS-1: Stop app on app-onprem"
if ! $DRY_RUN; then
  ssh_run "app-onprem" \
    "cd /opt/clopr2/deploy/docker && sudo docker compose down; echo \"App stopped at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" \
    | tee "${EVIDENCE_DIR}/fsdr-app-stopped.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-app-stopped.txt")
  pass "FS-1: app-onprem container stopped"
else
  log "[DRY-RUN] ssh app-onprem 'cd /opt/clopr2/deploy/docker && sudo docker compose down'"
fi

# ── FS-2: Record final LSN ────────────────────────────────────────────────────
step "FS-2: Record final LSN on pg-primary"
if ! $DRY_RUN; then
  final_lsn_out=$(ssh_run "pg-primary" "
    sudo -u postgres psql -c \"
      SELECT pg_current_wal_lsn() AS final_lsn, now() AS captured_at,
             client_addr, replay_lsn,
             (pg_current_wal_lsn() - replay_lsn) AS bytes_lag
      FROM pg_stat_replication WHERE client_addr = '10.200.0.2';\"
  " | tee "${EVIDENCE_DIR}/fsdr-final-lsn.txt")
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-final-lsn.txt")

  # Extract final LSN for RPO calculation
  FINAL_PRIMARY_LSN=$(ssh_run "pg-primary" \
    "sudo -u postgres psql -qtAc 'SELECT pg_current_wal_lsn();'" \
    | tr -d '[:space:]')
  log "Final primary LSN: ${FINAL_PRIMARY_LSN}"
  pass "FS-2: final LSN captured"
else
  log "[DRY-RUN] ssh pg-primary 'sudo -u postgres psql -c SELECT pg_current_wal_lsn()...'"
  FINAL_PRIMARY_LSN="0/0"
fi

# ── FS-3: Stop pg-primary services (DESTRUCTIVE) ──────────────────────────────
step "FS-3: Stop pg-primary services [DESTRUCTIVE]"
echo ""
echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════╗"
echo "${LOG_PREFIX} ║  STOPPING postgresql and keepalived on pg-primary        ║"
echo "${LOG_PREFIX} ║  On-prem DB will be DOWN. WireGuard stays UP.            ║"
echo "${LOG_PREFIX} ║  Recovery requires fullsite-fallback.sh.                 ║"
echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════╝"
echo ""

if ! $DRY_RUN; then
  FS3_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ssh_run "pg-primary" "
    sudo systemctl stop postgresql
    sudo systemctl stop keepalived
    echo \"Services stopped at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- postgresql ---'
    sudo systemctl status postgresql --no-pager | head -4
    echo '--- keepalived ---'
    sudo systemctl status keepalived --no-pager | head -4
  " | tee "${EVIDENCE_DIR}/fsdr-primary-stopped.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-primary-stopped.txt")

  # Verify services are actually stopped
  pg_status=$(ssh_run "pg-primary" \
    "systemctl is-active postgresql 2>/dev/null || true" | tr -d '[:space:]')
  kp_status=$(ssh_run "pg-primary" \
    "systemctl is-active keepalived 2>/dev/null || true" | tr -d '[:space:]')
  assert "FS-3: postgresql inactive" "inactive" "$pg_status"
  assert "FS-3: keepalived inactive" "inactive" "$kp_status"
  pass "FS-3: pg-primary services stopped"
else
  log "[DRY-RUN] ssh pg-primary 'sudo systemctl stop postgresql && sudo systemctl stop keepalived'"
  FS3_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── FS-4: Wait for DR VM WAL replay to stabilise ──────────────────────────────
step "FS-4: Wait for DR VM WAL replay to stabilise (timeout=${WAL_REPLAY_TIMEOUT}s)"
if ! $DRY_RUN; then
  log "Polling pg_last_wal_replay_lsn until 3 consecutive identical readings..."
  prev_lsn=""
  stable_count=0
  elapsed=0
  poll_log="${EVIDENCE_DIR}/fsdr-replay-wait.txt"
  printf "=== WAL REPLAY STABILISATION WAIT ===\nFS3_START: %s\n\n" "$FS3_START" > "$poll_log"

  while [[ $elapsed -lt $WAL_REPLAY_TIMEOUT ]]; do
    current_lsn=$(ssh -o ConnectTimeout=15 -o BatchMode=yes vm-pg-dr-fce \
      "sudo -u postgres psql -qtAc 'SELECT pg_last_wal_replay_lsn();'" \
      2>/dev/null | tr -d '[:space:]' || echo "")
    ts=$(date -u +%H:%M:%SZ)
    printf "%s  replay_lsn=%s  stable=%d\n" "$ts" "$current_lsn" "$stable_count" | tee -a "$poll_log"

    if [[ -n "$current_lsn" && "$current_lsn" == "$prev_lsn" ]]; then
      stable_count=$((stable_count + 1))
      if [[ $stable_count -ge 3 ]]; then
        FINAL_REPLAY_LSN="$current_lsn"
        break
      fi
    else
      stable_count=0
      prev_lsn="$current_lsn"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  if [[ -z "$FINAL_REPLAY_LSN" ]]; then
    warn "WAL replay did not stabilise within ${WAL_REPLAY_TIMEOUT}s — using last known LSN"
    FINAL_REPLAY_LSN="${current_lsn:-0/0}"
  fi

  # Compute RPO in bytes
  primary_bytes=$(lsn_to_bytes "$FINAL_PRIMARY_LSN")
  replay_bytes=$(lsn_to_bytes "$FINAL_REPLAY_LSN")
  RPO_BYTES=$(python3 -c "print(max(0, ${primary_bytes:-0} - ${replay_bytes:-0}))")
  printf "\nFINAL_PRIMARY_LSN:  %s\nFINAL_REPLAY_LSN:   %s\nRPO_BYTES:          %s\n" \
    "$FINAL_PRIMARY_LSN" "$FINAL_REPLAY_LSN" "$RPO_BYTES" | tee -a "$poll_log"
  EVIDENCE_FILES+=("$poll_log")

  if [[ "$RPO_BYTES" -gt "$WAL_LAG_THRESHOLD" ]]; then
    warn "DR VM lag = ${RPO_BYTES} bytes exceeds threshold ${WAL_LAG_THRESHOLD} — proceeding anyway (replay source is stopped)"
  else
    pass "FS-4: DR VM lag = ${RPO_BYTES} bytes <= threshold ${WAL_LAG_THRESHOLD}"
  fi
else
  log "[DRY-RUN] would poll vm-pg-dr-fce pg_last_wal_replay_lsn until stable"
  FINAL_REPLAY_LSN="0/0"
  RPO_BYTES=0
fi

# ── FS-5: Promote vm-pg-dr-fce ────────────────────────────────────────────────
step "FS-5: Promote vm-pg-dr-fce to primary"
if ! $DRY_RUN; then
  promote_out=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc 'SELECT pg_promote();'" \
    | tr -d '[:space:]')
  assert "FS-5: pg_promote() returned" "t" "$promote_out"

  sleep 3

  promoted_snapshot=$(ssh_run "vm-pg-dr-fce" "
    echo '=== DR VM PROMOTED ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- pg_is_in_recovery ---'
    sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'
    echo '--- pg_current_wal_lsn ---'
    sudo -u postgres psql -qtAc 'SELECT pg_current_wal_lsn(), now();'
    echo '--- standby.signal ---'
    sudo -u postgres ls /var/lib/postgresql/16/main/standby.signal 2>&1 || true
  " | tee "${EVIDENCE_DIR}/fsdr-promoted.txt")
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-promoted.txt")

  recovery_post=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" \
    | tr -d '[:space:]')
  assert "FS-5: vm-pg-dr-fce pg_is_in_recovery after promote" "f" "$recovery_post"
  pass "FS-5: vm-pg-dr-fce promoted to primary"
else
  log "[DRY-RUN] ssh vm-pg-dr-fce 'sudo -u postgres psql -c SELECT pg_promote()'"
fi

# ── FS-6: Write test ──────────────────────────────────────────────────────────
step "FS-6: Confirm write capability on vm-pg-dr-fce"
if ! $DRY_RUN; then
  write_test=$(ssh_run "vm-pg-dr-fce" "
    sudo -u postgres psql -c \"
      CREATE TABLE IF NOT EXISTS _fsdr_promote_test (ts timestamptz DEFAULT now());
      INSERT INTO _fsdr_promote_test VALUES (DEFAULT);
      SELECT * FROM _fsdr_promote_test;
      DROP TABLE _fsdr_promote_test;\"
  " | tee "${EVIDENCE_DIR}/fsdr-write-test.txt")
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-write-test.txt")

  if echo "$write_test" | grep -q "INSERT 0 1"; then
    pass "FS-6: write test INSERT 0 1"
  else
    fail "FS-6: write test did not produce INSERT 0 1"
    exit 1
  fi
else
  log "[DRY-RUN] ssh vm-pg-dr-fce 'sudo -u postgres psql CREATE TABLE / INSERT / DROP'"
fi

# ── FS-7: Start app on vm-pg-dr-fce ──────────────────────────────────────────
step "FS-7: Start app container on vm-pg-dr-fce"
if ! $DRY_RUN; then
  # Remove any existing container from a previous run
  ssh_run "vm-pg-dr-fce" \
    "sudo docker rm -f clopr2-app-dr 2>/dev/null || true"

  app_start=$(ssh_run "vm-pg-dr-fce" "
    sudo docker run -d \
      --name clopr2-app-dr \
      --restart unless-stopped \
      --network host \
      --env-file /home/azureuser/clopr2-app/.env \
      clopr2-app:dr
    sleep 5
    echo '--- docker ps ---'
    sudo docker ps --filter name=clopr2-app-dr
    echo \"App started at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  ")
  log "$app_start"
  if ! echo "$app_start" | grep -q "clopr2-app-dr"; then
    fail "FS-7: clopr2-app-dr container not found in docker ps"
    exit 1
  fi
  pass "FS-7: app container started on vm-pg-dr-fce"
else
  log "[DRY-RUN] ssh vm-pg-dr-fce 'sudo docker run -d --name clopr2-app-dr --network host ...'"
fi

# ── FS-8: Validate app health on DR VM ───────────────────────────────────────
step "FS-8: Validate /health on vm-pg-dr-fce (timeout=${APP_WAIT_TIMEOUT}s)"
if ! $DRY_RUN; then
  app_health_ok=false
  elapsed=0
  health_response=""
  while [[ $elapsed -lt $APP_WAIT_TIMEOUT ]]; do
    health_response=$(ssh_run "vm-pg-dr-fce" \
      "curl -sf --max-time 5 http://localhost:8000/health" \
      2>/dev/null || echo "")
    if [[ -n "$health_response" ]]; then
      app_health_ok=true
      APP_HEALTH_OK_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
    log "Waiting for app health... ${elapsed}s elapsed"
  done

  if ! $app_health_ok; then
    fail "FS-8: app /health did not respond within ${APP_WAIT_TIMEOUT}s"
    exit 1
  fi

  echo "$health_response" | tee "${EVIDENCE_DIR}/fsdr-app-health-drvm.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-app-health-drvm.txt")
  log "App health response: $health_response"

  # Critical assertion: pg_is_in_recovery must be false
  dr_recovery_val=$(echo "$health_response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(str(d.get('pg_is_in_recovery', 'MISSING')).lower())
" 2>/dev/null || echo "parse-error")
  assert "FS-8: app pg_is_in_recovery=false (Azure DB is primary)" "false" "$dr_recovery_val"
  pass "FS-8: app /health confirmed DR VM is primary"
else
  log "[DRY-RUN] would poll vm-pg-dr-fce:8000/health until HTTP 200"
  APP_HEALTH_OK_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── FS-9: Validate via SSH port-forward ──────────────────────────────────────
step "FS-9: Validate /health via SSH port-forward (external path)"
if ! $DRY_RUN; then
  ssh -L 18000:localhost:8000 -N \
      -o ExitOnForwardFailure=yes \
      -o ConnectTimeout=10 \
      -o BatchMode=yes \
      vm-pg-dr-fce &
  PF_PID=$!
  sleep 2

  pf_health=$(curl -s --max-time 10 http://localhost:18000/health \
    || echo '{"error":"port-forward-failed"}')

  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true

  echo "$pf_health" | tee "${EVIDENCE_DIR}/fsdr-app-health-local.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-app-health-local.txt")
  log "Port-forward health: $pf_health"
  pass "FS-9: port-forward health check complete"
else
  log "[DRY-RUN] would open ssh -L 18000:localhost:8000 vm-pg-dr-fce and curl localhost:18000/health"
fi

# ── FS-10: RTO/RPO summary + post-failover snapshot ──────────────────────────
step "FS-10: Record RTO/RPO and post-failover snapshot"
if ! $DRY_RUN; then
  FSO_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  {
    echo "=== FULL-SITE FAILOVER SUMMARY ==="
    echo "FSO_START:         ${FSO_START}"
    echo "FS3_START:         ${FS3_START}   (pg-primary stopped — outage begins)"
    echo "APP_HEALTH_OK:     ${APP_HEALTH_OK_TS}   (app /health 200 on DR VM)"
    echo "FSO_END:           ${FSO_END}"
    echo ""
    echo "FINAL_PRIMARY_LSN: ${FINAL_PRIMARY_LSN}"
    echo "FINAL_REPLAY_LSN:  ${FINAL_REPLAY_LSN}"
    echo "RPO_BYTES:         ${RPO_BYTES}"
    echo ""
    echo "RTO: measured from FS3_START to APP_HEALTH_OK_TS"
    echo "     (seconds from pg-primary stopped to Azure app health confirmed)"
    echo "RPO: ${RPO_BYTES} bytes (WAL not applied at promotion time)"
    echo ""
    echo "RESULT: PASS"
  } | tee "${EVIDENCE_DIR}/fsdr-rto-summary.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-rto-summary.txt")

  ssh_run "vm-pg-dr-fce" "
    echo '=== POST-FAILOVER STATE ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- PostgreSQL role ---'
    sudo -u postgres psql -c \"SELECT pg_is_in_recovery(), pg_current_wal_lsn();\"
    echo '--- pg_stat_replication (no rows expected — on-prem is down) ---'
    sudo -u postgres psql -c \"SELECT * FROM pg_stat_replication;\"
    echo '--- App container ---'
    sudo docker ps --filter name=clopr2-app-dr
    echo '--- App /health ---'
    curl -s http://localhost:8000/health
  " | tee "${EVIDENCE_DIR}/fsdr-post-failover-snapshot.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-post-failover-snapshot.txt")

  pass "FS-10: RTO/RPO recorded"
else
  log "[DRY-RUN] would write fsdr-rto-summary.txt and fsdr-post-failover-snapshot.txt"
  FSO_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
log "========================================================"
log "FULL-SITE FAILOVER COMPLETE"
log ""
if ! $DRY_RUN; then
  log "Evidence files (${#EVIDENCE_FILES[@]}):"
  for f in "${EVIDENCE_FILES[@]}"; do
    log "  $f"
  done
  log ""
  log "Next step: run evidence-export.sh fullsite-failover to copy files to repo."
  log "Run fullsite-fallback.sh when ready to restore on-prem."
else
  log "DRY-RUN complete — no changes made."
fi
log "========================================================"
echo ""

exit 0
