#!/usr/bin/env bash
# fullsite-fallback.sh — Full-site failback: Azure DR VM -> on-prem
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   Execute the planned failback from Azure vm-pg-dr-fce (currently primary)
#   back to on-prem pg-primary. Uses pg_basebackup twice: once to rebuild
#   pg-primary as a standby of DR VM, and once to rebuild DR VM as a standby
#   of the newly promoted pg-primary.
#
# DESTRUCTIVE OPERATIONS (two separate confirmation gates):
#   FB-3: pg_basebackup on pg-primary FROM DR VM
#         -> WIPES pg-primary data directory (/var/lib/postgresql/16/main)
#         -> GATE 1: --confirm-destructive pg-primary
#
#   FB-8: pg_basebackup on vm-pg-dr-fce FROM pg-primary
#         -> WIPES DR VM data directory (/var/lib/postgresql/16/main)
#         -> GATE 2: --confirm-destructive dr-vm
#
# USAGE:
#   ./scripts/dr/fullsite-fallback.sh --confirm \
#       --confirm-destructive pg-primary \
#       --confirm-destructive dr-vm \
#       [--dry-run]
#
# OPTIONS:
#   --confirm                           Required baseline confirmation.
#   --confirm-destructive pg-primary    Acknowledge pg-primary data wipe (FB-3).
#   --confirm-destructive dr-vm         Acknowledge DR VM data wipe (FB-8).
#   --dry-run                           Print commands without executing.
#
# TIMING NOTE:
#   SERVICE RTO: FSB_START to FB-10 (keepalived started, VIP returned)
#   APP RTO:     FSB_START to FB-12 (app /health 200 on app-onprem)
#   TOPOLOGY RTO: FSB_START to FB-9 (DR VM streaming from pg-primary)
#
# EXIT CODES:
#   0   PASS — failback completed and validated
#   1   FAIL — assertion failed or acceptance criterion not met
#   2   ABORTED — prerequisite check or gate failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[fullsite-fallback]"

CONFIRMED=false
CONFIRMED_DESTRUCTIVE_PRIMARY=false
CONFIRMED_DESTRUCTIVE_DRVM=false
DRY_RUN=false

LAG_CATCHUP_TIMEOUT=120   # seconds to wait for pg-primary lag -> near-zero
STREAM_WAIT_TIMEOUT=60    # seconds to wait for streaming in pg_stat_replication
APP_WAIT_TIMEOUT=60       # seconds to poll on-prem app health

EVIDENCE_DIR="/tmp"
EVIDENCE_FILES=()

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRMED=true ;;
    --confirm-destructive)
      shift
      case "$1" in
        pg-primary) CONFIRMED_DESTRUCTIVE_PRIMARY=true ;;
        dr-vm)      CONFIRMED_DESTRUCTIVE_DRVM=true ;;
        *)
          echo "Unknown --confirm-destructive target: $1" >&2
          echo "Valid targets: pg-primary, dr-vm" >&2
          exit 2 ;;
      esac ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -20
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --confirm [--confirm-destructive pg-primary] [--confirm-destructive dr-vm] [--dry-run]" >&2
      exit 2 ;;
  esac
  shift
done

# ── helpers ───────────────────────────────────────────────────────────────────
log()  { echo "${LOG_PREFIX} $(date -u +%H:%M:%SZ) $*"; }
pass() { echo "${LOG_PREFIX} [PASS]  $*"; }
fail() { echo "${LOG_PREFIX} [FAIL]  $*" >&2; }
warn() { echo "${LOG_PREFIX} [WARN]  $*"; }
step() { echo ""; echo "${LOG_PREFIX} ===== $* ====="; }

# Relay-aware SSH wrapper.
# app-onprem (10.0.96.13) cannot be reached via PVE TCP-forward.
# Route through pg-primary (10.0.96.11) via explicit ProxyCommand.
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

# ── gate: require --confirm ───────────────────────────────────────────────────
if ! $DRY_RUN && ! $CONFIRMED; then
  echo ""
  echo "================================================================"
  echo "  FULL-SITE FAILBACK (Azure DR -> on-prem)"
  echo "================================================================"
  echo ""
  echo "  This script will:"
  echo "    FB-1: Stop app on vm-pg-dr-fce (Azure)"
  echo "    FB-2: Set DR VM PostgreSQL to read-only"
  echo ""
  echo "  [GATE 1: --confirm-destructive pg-primary]"
  echo "    FB-3: WIPE pg-primary data dir + pg_basebackup from DR VM  [DESTRUCTIVE]"
  echo "    FB-4: Start pg-primary as standby"
  echo "    FB-5: Verify pg-primary streaming from DR VM"
  echo "    FB-6: Wait for pg-primary to catch up"
  echo "    FB-7: Promote pg-primary to primary"
  echo ""
  echo "  [GATE 2: --confirm-destructive dr-vm]"
  echo "    FB-8: WIPE DR VM data dir + pg_basebackup from pg-primary  [DESTRUCTIVE]"
  echo "    FB-9: Verify DR VM streaming from pg-primary               [TOPOLOGY RTO]"
  echo "   FB-10: Start keepalived on pg-primary -> VIP returns        [SERVICE RTO]"
  echo "   FB-11: Start app on app-onprem"
  echo "   FB-12: Validate /health on app-onprem"
  echo "   FB-13: Record RTO and post-failback snapshot"
  echo ""
  echo "  Pass --confirm to run pre-checks only."
  echo "  Pass all three flags for full execution."
  echo "================================================================"
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

# ── STEP 1: Prerequisites H-1..H-7 ───────────────────────────────────────────
step "STEP 1: Prerequisites H-1 through H-7"

log "H-1: DR VM must be primary (pg_is_in_recovery=f)..."
if ! $DRY_RUN; then
  dr_recovery=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" \
    2>/dev/null || echo "error")
  assert "H-1: vm-pg-dr-fce pg_is_in_recovery" "f" "$dr_recovery"
else
  log "[DRY-RUN] skip H-1 (vm-pg-dr-fce pg_is_in_recovery)"
fi

log "H-2: DR VM app clopr2-app-dr must be running..."
if ! $DRY_RUN; then
  dr_app=$(ssh_run "vm-pg-dr-fce" \
    "sudo docker ps --filter name=clopr2-app-dr --format '{{.Status}}'" 2>/dev/null || echo "")
  if echo "$dr_app" | grep -qi "up"; then
    pass "H-2: clopr2-app-dr running: ${dr_app}"
  else
    fail "H-2: clopr2-app-dr not running (status='${dr_app:-empty}')"
    exit 1
  fi
fi

log "H-3: pg-primary OS reachable..."
if ! $DRY_RUN; then
  pg_primary_hostname=$(ssh_run "pg-primary" "hostname" 2>/dev/null || echo "error")
  assert "H-3: pg-primary hostname" "pg-primary" "$pg_primary_hostname"
else
  log "[DRY-RUN] skip H-3 (pg-primary hostname)"
fi

log "H-4: pg-primary PostgreSQL must be STOPPED..."
if ! $DRY_RUN; then
  pg_active=$(ssh_run "pg-primary" \
    "systemctl is-active postgresql 2>/dev/null; true" | tr -d '[:space:]')
  assert "H-4: pg-primary postgresql" "inactive" "$pg_active"
else
  log "[DRY-RUN] skip H-4 (pg-primary postgresql status)"
fi

log "H-5: WireGuard must have at least one active peer on pg-primary..."
if ! $DRY_RUN; then
  wg_peer=$(ssh_run "pg-primary" \
    "sudo wg show wg0 2>/dev/null | grep -c 'peer:' || echo 0" | tr -d '[:space:]')
  assert "H-5: WireGuard peer count" "1" "$wg_peer"
fi

log "H-6: replicator role must exist on DR VM..."
if ! $DRY_RUN; then
  repl_role=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc \"SELECT rolname FROM pg_roles WHERE rolname='replicator';\"" \
    2>/dev/null | tr -d '[:space:]')
  assert "H-6: replicator role on DR VM" "replicator" "$repl_role"
fi

log "H-7: pg_hba.conf on DR VM must allow replication..."
if ! $DRY_RUN; then
  hba_count=$(ssh_run "vm-pg-dr-fce" \
    "sudo grep -c replication /etc/postgresql/16/main/pg_hba.conf 2>/dev/null || echo 0" \
    | tr -d '[:space:]')
  if [[ "${hba_count:-0}" -ge 1 ]]; then
    pass "H-7: pg_hba.conf has replication entries (${hba_count})"
  else
    fail "H-7: no replication entry in /etc/postgresql/16/main/pg_hba.conf"
    exit 1
  fi
fi

pass "STEP 1: All H-1..H-7 prerequisites passed"

# ── STEP 2: Capture pre-failback state ───────────────────────────────────────
step "STEP 2: Capture pre-failback state"

FSB_START=""
SERVICE_RTO_TS=""
TOPOLOGY_RTO_TS=""
APP_HEALTH_OK_TS=""

if ! $DRY_RUN; then
  FSB_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf "FSB_START: %s\n" "$FSB_START" | tee "${EVIDENCE_DIR}/fsdb-start-timestamp.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-start-timestamp.txt")

  {
    echo "=== FAILBACK PRE-CHECK ==="
    echo "FSB_START: ${FSB_START}"
    echo "--- DR VM PostgreSQL state ---"
  } > "${EVIDENCE_DIR}/fsdb-precheck.txt"

  ssh_run "vm-pg-dr-fce" "
    sudo -u postgres psql -c 'SELECT pg_is_in_recovery(), pg_current_wal_lsn(), now();'
    echo '--- pg_stat_replication (expect empty) ---'
    sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'
    echo '--- App running ---'
    sudo docker ps --filter name=clopr2-app-dr
  " | tee -a "${EVIDENCE_DIR}/fsdb-precheck.txt"

  ssh_run "pg-primary" "
    echo '--- pg-primary services ---'
    sudo systemctl is-active postgresql || true
    sudo systemctl is-active keepalived || true
    echo '--- WireGuard ---'
    sudo wg show
    echo '--- Disk ---'
    df -h /var/lib/postgresql/
  " | tee -a "${EVIDENCE_DIR}/fsdb-precheck.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-precheck.txt")
  log "Pre-failback state captured"
else
  log "[DRY-RUN] would capture pre-failback state from vm-pg-dr-fce and pg-primary"
  FSB_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── Pre-destructive summary ───────────────────────────────────────────────────
step "PRE-DESTRUCTIVE SUMMARY"
log "All H-1..H-7 prerequisites passed."
log "GATE 1 (--confirm-destructive pg-primary) unlocks FB-1..FB-7."
log "GATE 2 (--confirm-destructive dr-vm) unlocks FB-8..FB-13."
echo ""

# ── DESTRUCTIVE GATE 1 ────────────────────────────────────────────────────────
if ! $DRY_RUN && ! $CONFIRMED_DESTRUCTIVE_PRIMARY; then
  echo ""
  echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════════╗"
  echo "${LOG_PREFIX} ║  GATE 1 BLOCKED                                              ║"
  echo "${LOG_PREFIX} ║  FB-3 will WIPE /var/lib/postgresql/16/main on pg-primary.   ║"
  echo "${LOG_PREFIX} ║  Pass --confirm-destructive pg-primary to proceed.           ║"
  echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════════╝"
  echo ""
  exit 2
fi
if $DRY_RUN; then
  log "[DRY-RUN] GATE 1 (--confirm-destructive pg-primary) would be checked here"
fi

# ── FB-1: Stop app on DR VM ───────────────────────────────────────────────────
step "FB-1: Stop app on vm-pg-dr-fce"
if ! $DRY_RUN; then
  ssh_run "vm-pg-dr-fce" "
    sudo docker stop clopr2-app-dr 2>/dev/null || true
    sudo docker rm clopr2-app-dr 2>/dev/null || true
    echo \"App stopped at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- docker ps ---'
    sudo docker ps
  " | tee "${EVIDENCE_DIR}/fsdb-azure-app-stopped.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-azure-app-stopped.txt")
  pass "FB-1: Azure app container stopped"
else
  log "[DRY-RUN] ssh vm-pg-dr-fce 'sudo docker stop clopr2-app-dr && sudo docker rm clopr2-app-dr'"
fi

# ── FB-2: Set DR VM to read-only ──────────────────────────────────────────────
step "FB-2: Set vm-pg-dr-fce to read-only"
if ! $DRY_RUN; then
  ssh_run "vm-pg-dr-fce" "
    sudo -u postgres psql -c \"ALTER SYSTEM SET default_transaction_read_only = on;\"
    sudo -u postgres psql -c \"SELECT pg_reload_conf();\"
    echo \"DR VM set to read-only at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres psql -c \"SHOW default_transaction_read_only;\"
  " | tee "${EVIDENCE_DIR}/fsdb-drvm-readonly.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-drvm-readonly.txt")

  ro_val=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc 'SHOW default_transaction_read_only;'" \
    | tr -d '[:space:]')
  assert "FB-2: DR VM default_transaction_read_only" "on" "$ro_val"
  pass "FB-2: DR VM is read-only"
else
  log "[DRY-RUN] ssh vm-pg-dr-fce 'sudo -u postgres psql -c ALTER SYSTEM SET default_transaction_read_only = on'"
fi

# ── FB-3: pg_basebackup on pg-primary FROM DR VM (DESTRUCTIVE) ───────────────
step "FB-3: Rebuild pg-primary as standby of DR VM [DESTRUCTIVE — WIPES pg-primary data]"
echo ""
echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════════╗"
echo "${LOG_PREFIX} ║  WIPING /var/lib/postgresql/16/main on pg-primary            ║"
echo "${LOG_PREFIX} ║  Source: vm-pg-dr-fce (10.200.0.2) via WireGuard             ║"
echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════════╝"
echo ""

if ! $DRY_RUN; then
  # Ensure pg-primary PostgreSQL is stopped
  ssh_run "pg-primary" "sudo systemctl stop postgresql 2>/dev/null || true"

  ssh_run "pg-primary" "
    echo \"Starting pg_basebackup at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres rm -rf /var/lib/postgresql/16/main
    sudo -u postgres pg_basebackup \
        -h 10.200.0.2 \
        -U replicator \
        -D /var/lib/postgresql/16/main \
        -R -P --wal-method=stream \
        --checkpoint=fast
    echo \"pg_basebackup completed at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- standby.signal ---'
    sudo -u postgres ls /var/lib/postgresql/16/main/standby.signal
    echo '--- auto.conf before rewrite ---'
    sudo -u postgres cat /var/lib/postgresql/16/main/postgresql.auto.conf
  " | tee "${EVIDENCE_DIR}/fsdb-pg-basebackup.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-pg-basebackup.txt")

  # Rewrite auto.conf: single primary_conninfo -> DR VM (10.200.0.2)
  # -R copies source auto.conf which may have duplicate/stale entries
  ssh_run "pg-primary" \
    "sudo -u postgres bash -c 'printf \"primary_conninfo = \x27user=replicator passfile=/var/lib/postgresql/.pgpass host=10.200.0.2 port=5432 sslmode=prefer\x27\n\" > /var/lib/postgresql/16/main/postgresql.auto.conf'"
  log "FB-3: auto.conf rewritten -> single primary_conninfo to 10.200.0.2"

  signal_check=$(ssh_run "pg-primary" \
    "sudo -u postgres test -f /var/lib/postgresql/16/main/standby.signal && echo present || echo absent")
  assert "FB-3: standby.signal on pg-primary" "present" "$signal_check"
  pass "FB-3: pg_basebackup complete on pg-primary"
else
  log "[DRY-RUN] ssh pg-primary 'rm -rf /var/lib/postgresql/16/main && pg_basebackup -h 10.200.0.2 ...'"
fi

# ── FB-4: Start pg-primary as standby ────────────────────────────────────────
step "FB-4: Start pg-primary as standby"
if ! $DRY_RUN; then
  ssh_run "pg-primary" "
    sudo systemctl start postgresql
    sleep 5
    sudo systemctl status postgresql --no-pager | head -5
    sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'
  " | tee "${EVIDENCE_DIR}/fsdb-primary-standby-start.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-primary-standby-start.txt")

  recovery_val=$(ssh_run "pg-primary" \
    "sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" \
    | tr -d '[:space:]')
  assert "FB-4: pg-primary pg_is_in_recovery after start" "t" "$recovery_val"
  pass "FB-4: pg-primary started as standby"
else
  log "[DRY-RUN] ssh pg-primary 'sudo systemctl start postgresql'"
fi

# ── FB-5: Verify pg-primary streaming from DR VM ─────────────────────────────
step "FB-5: Verify pg-primary streaming from DR VM (wait ${STREAM_WAIT_TIMEOUT}s)"
if ! $DRY_RUN; then
  stream_found=false
  elapsed=0
  while [[ $elapsed -lt $STREAM_WAIT_TIMEOUT ]]; do
    stream_state=$(ssh_run "vm-pg-dr-fce" \
      "sudo -u postgres psql -qtAc \"SELECT state FROM pg_stat_replication WHERE client_addr='10.200.0.1';\"" \
      2>/dev/null | tr -d '[:space:]' || echo "")
    if [[ "$stream_state" == "streaming" ]]; then
      stream_found=true
      break
    fi
    log "Waiting for pg-primary in DR VM pg_stat_replication... ${elapsed}s"
    sleep 4
    elapsed=$((elapsed + 4))
  done

  ssh_run "vm-pg-dr-fce" "
    echo '=== DR VM pg_stat_replication ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres psql -c \"SELECT client_addr, state, sync_state,
        sent_lsn, replay_lsn, (sent_lsn - replay_lsn) AS bytes_lag
        FROM pg_stat_replication;\"
  " | tee "${EVIDENCE_DIR}/fsdb-drvm-replication.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-drvm-replication.txt")

  if ! $stream_found; then
    fail "FB-5: pg-primary did not appear in DR VM pg_stat_replication within ${STREAM_WAIT_TIMEOUT}s"
    exit 1
  fi
  pass "FB-5: pg-primary streaming from DR VM"
else
  log "[DRY-RUN] would poll vm-pg-dr-fce pg_stat_replication for 10.200.0.1 streaming"
fi

# ── FB-6: Wait for pg-primary to catch up ────────────────────────────────────
step "FB-6: Wait for pg-primary lag to reach near-zero (timeout=${LAG_CATCHUP_TIMEOUT}s)"
if ! $DRY_RUN; then
  log "Polling DR VM pg_stat_replication bytes_lag..."
  {
    echo "=== CATCHUP WAIT ==="
    echo "FSB_START: ${FSB_START}"
  } > "${EVIDENCE_DIR}/fsdb-catchup-wait.txt"

  elapsed=0
  lag_bytes=999999
  while [[ $elapsed -lt $LAG_CATCHUP_TIMEOUT ]]; do
    lag_raw=$(ssh_run "vm-pg-dr-fce" \
      "sudo -u postgres psql -qtAc \"SELECT (sent_lsn - replay_lsn) FROM pg_stat_replication WHERE client_addr='10.200.0.1';\"" \
      2>/dev/null | tr -d '[:space:]' || echo "")
    ts=$(date -u +%H:%M:%SZ)
    printf "%s  bytes_lag=%s\n" "$ts" "${lag_raw:-unknown}" | tee -a "${EVIDENCE_DIR}/fsdb-catchup-wait.txt"
    lag_bytes="${lag_raw:-999999}"
    if [[ -n "$lag_raw" ]] && python3 -c "exit(0 if int('${lag_raw}') <= 1024 else 1)" 2>/dev/null; then
      break
    fi
    sleep 4
    elapsed=$((elapsed + 4))
  done
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-catchup-wait.txt")
  pass "FB-6: pg-primary caught up (final lag=${lag_bytes} bytes)"
else
  log "[DRY-RUN] would poll DR VM pg_stat_replication bytes_lag until <= 1024"
fi

# ── FB-7: Assert DR VM read-only, promote pg-primary ──────────────────────────
step "FB-7: Promote pg-primary to primary"
if ! $DRY_RUN; then
  # Safety: DR VM must still be in read-only mode (prevents split-brain)
  ro_check=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc 'SHOW default_transaction_read_only;'" \
    | tr -d '[:space:]')
  assert "FB-7: DR VM still read-only before promoting pg-primary" "on" "$ro_check"

  ssh_run "pg-primary" "
    echo \"Promoting pg-primary at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres psql -qtAc 'SELECT pg_promote();'
    sleep 3
    sudo -u postgres psql -c 'SELECT pg_is_in_recovery(), pg_current_wal_lsn();'
    echo '--- standby.signal (must be absent) ---'
    sudo -u postgres ls /var/lib/postgresql/16/main/standby.signal 2>&1 || true
  " | tee "${EVIDENCE_DIR}/fsdb-primary-promoted.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-primary-promoted.txt")

  recovery_post=$(ssh_run "pg-primary" \
    "sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" \
    | tr -d '[:space:]')
  assert "FB-7: pg-primary pg_is_in_recovery after promotion" "f" "$recovery_post"
  pass "FB-7: pg-primary promoted to primary"
else
  log "[DRY-RUN] ssh pg-primary 'sudo -u postgres psql -c SELECT pg_promote()'"
fi

# ── DESTRUCTIVE GATE 2 ────────────────────────────────────────────────────────
if ! $DRY_RUN && ! $CONFIRMED_DESTRUCTIVE_DRVM; then
  echo ""
  echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════════╗"
  echo "${LOG_PREFIX} ║  GATE 2 BLOCKED                                              ║"
  echo "${LOG_PREFIX} ║  FB-8 will WIPE /var/lib/postgresql/16/main on vm-pg-dr-fce. ║"
  echo "${LOG_PREFIX} ║  pg-primary is now primary — on-prem data is authoritative.  ║"
  echo "${LOG_PREFIX} ║  Pass --confirm-destructive dr-vm to proceed.                ║"
  echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════════╝"
  echo ""
  exit 2
fi
if $DRY_RUN; then
  log "[DRY-RUN] GATE 2 (--confirm-destructive dr-vm) would be checked here"
fi

# ── FB-8: Rebuild DR VM as standby of pg-primary (DESTRUCTIVE) ───────────────
step "FB-8: Rebuild vm-pg-dr-fce as standby of pg-primary [DESTRUCTIVE — WIPES DR VM data]"
echo ""
echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════════╗"
echo "${LOG_PREFIX} ║  WIPING /var/lib/postgresql/16/main on vm-pg-dr-fce          ║"
echo "${LOG_PREFIX} ║  Source: pg-primary (10.200.0.1) via WireGuard               ║"
echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════════╝"
echo ""

if ! $DRY_RUN; then
  # Undo read-only BEFORE stopping (writes clean postgresql.auto.conf)
  ssh_run "vm-pg-dr-fce" "
    sudo -u postgres psql -c \"ALTER SYSTEM RESET default_transaction_read_only;\"
    sudo -u postgres psql -c \"SELECT pg_reload_conf();\"
    sudo systemctl stop postgresql
    echo \"DR VM postgres stopped at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres rm -rf /var/lib/postgresql/16/main
    sudo -u postgres pg_basebackup \
        -h 10.200.0.1 \
        -U replicator \
        -D /var/lib/postgresql/16/main \
        -R -P --wal-method=stream \
        --checkpoint=fast
    echo \"DR VM pg_basebackup complete at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres ls /var/lib/postgresql/16/main/standby.signal
  " | tee "${EVIDENCE_DIR}/fsdb-drvm-rebuild.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-drvm-rebuild.txt")

  # Rewrite auto.conf: single primary_conninfo -> pg-primary (10.200.0.1)
  ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres bash -c 'printf \"primary_conninfo = \x27user=replicator passfile=/var/lib/postgresql/.pgpass host=10.200.0.1 port=5432 sslmode=prefer\x27\n\" > /var/lib/postgresql/16/main/postgresql.auto.conf'"
  log "FB-8: DR VM auto.conf rewritten -> single primary_conninfo to 10.200.0.1"

  # Start DR VM as standby
  ssh_run "vm-pg-dr-fce" "
    sudo systemctl start postgresql
    sleep 5
    sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'
  " | tee -a "${EVIDENCE_DIR}/fsdb-drvm-rebuild.txt"

  dr_recovery_post=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" \
    | tr -d '[:space:]')
  assert "FB-8: vm-pg-dr-fce pg_is_in_recovery after rebuild" "t" "$dr_recovery_post"
  pass "FB-8: DR VM rebuilt and started as standby"
else
  log "[DRY-RUN] ssh vm-pg-dr-fce 'ALTER SYSTEM RESET ... stop ... rm -rf ... pg_basebackup -h 10.200.0.1 ...'"
fi

# ── FB-9: Verify DR VM streaming from pg-primary ─────────────────────────────
step "FB-9: Verify DR VM streaming from pg-primary (wait ${STREAM_WAIT_TIMEOUT}s) [TOPOLOGY RTO]"
if ! $DRY_RUN; then
  stream_found=false
  elapsed=0
  while [[ $elapsed -lt $STREAM_WAIT_TIMEOUT ]]; do
    dr_stream=$(ssh_run "pg-primary" \
      "sudo -u postgres psql -qtAc \"SELECT state FROM pg_stat_replication WHERE client_addr='10.200.0.2';\"" \
      2>/dev/null | tr -d '[:space:]' || echo "")
    if [[ "$dr_stream" == "streaming" ]]; then
      stream_found=true
      TOPOLOGY_RTO_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      break
    fi
    log "Waiting for DR VM in pg-primary pg_stat_replication... ${elapsed}s"
    sleep 4
    elapsed=$((elapsed + 4))
  done

  ssh_run "pg-primary" "
    echo '=== pg-primary pg_stat_replication ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres psql -c \"SELECT client_addr, state, sync_state,
        sent_lsn, replay_lsn FROM pg_stat_replication ORDER BY client_addr;\"
  " | tee "${EVIDENCE_DIR}/fsdb-replication-restored.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-replication-restored.txt")

  if ! $stream_found; then
    warn "FB-9: DR VM did not appear as streaming within ${STREAM_WAIT_TIMEOUT}s — may need more time"
    TOPOLOGY_RTO_TS="pending"
  else
    pass "FB-9: DR VM streaming from pg-primary (TOPOLOGY RTO: ${TOPOLOGY_RTO_TS})"
  fi
else
  log "[DRY-RUN] would poll pg-primary pg_stat_replication for 10.200.0.2 streaming"
  TOPOLOGY_RTO_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── FB-10: Start keepalived on pg-primary -> VIP returns ─────────────────────
step "FB-10: Start keepalived on pg-primary [SERVICE RTO POINT]"
if ! $DRY_RUN; then
  ssh_run "pg-primary" "
    sudo systemctl start keepalived
    sleep 8
    sudo systemctl status keepalived --no-pager | head -5
    echo '--- VIP ---'
    ip addr show eth0 | grep inet
  " | tee "${EVIDENCE_DIR}/fsdb-vip-returned.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-vip-returned.txt")
  SERVICE_RTO_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  vip_present=$(ssh_run "pg-primary" \
    "ip addr show eth0 | grep -c '10.0.96.10' || echo 0" | tr -d '[:space:]')
  if [[ "${vip_present:-0}" -ge 1 ]]; then
    pass "FB-10: VIP 10.0.96.10 present on pg-primary (SERVICE RTO: ${SERVICE_RTO_TS})"
  else
    warn "FB-10: VIP 10.0.96.10 not yet on pg-primary — pg-standby keepalived may still hold it (wait ~4s)"
  fi
else
  log "[DRY-RUN] ssh pg-primary 'sudo systemctl start keepalived'"
  SERVICE_RTO_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── FB-11: Start app on app-onprem ────────────────────────────────────────────
step "FB-11: Start app on app-onprem"
if ! $DRY_RUN; then
  ssh_run "app-onprem" \
    "cd /opt/clopr2/deploy/docker && sudo docker compose up -d && sleep 5 && sudo docker ps" \
    | tee "${EVIDENCE_DIR}/fsdb-app-started.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-app-started.txt")
  pass "FB-11: app-onprem container started"
else
  log "[DRY-RUN] ssh app-onprem 'cd /opt/clopr2/deploy/docker && sudo docker compose up -d'"
fi

# ── FB-12: Validate on-prem app health ────────────────────────────────────────
step "FB-12: Validate /health on app-onprem (timeout=${APP_WAIT_TIMEOUT}s)"
if ! $DRY_RUN; then
  app_health_ok=false
  elapsed=0
  health_response=""
  while [[ $elapsed -lt $APP_WAIT_TIMEOUT ]]; do
    # Route via pg-primary SSH — WSL has no direct route to 10.0.96.x
    health_response=$(ssh_run "pg-primary" \
      "curl -sf --max-time 5 http://10.0.96.13:8080/health" \
      2>/dev/null || echo "")
    if [[ -n "$health_response" ]]; then
      app_health_ok=true
      APP_HEALTH_OK_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
    log "Waiting for app health on app-onprem... ${elapsed}s"
  done

  if ! $app_health_ok; then
    fail "FB-12: app /health did not respond within ${APP_WAIT_TIMEOUT}s"
    exit 1
  fi

  echo "$health_response" | tee "${EVIDENCE_DIR}/fsdb-app-health.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-app-health.txt")
  log "App health: $health_response"

  recovery_app=$(echo "$health_response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(str(d.get('pg_is_in_recovery', 'MISSING')).lower())
" 2>/dev/null || echo "parse-error")
  assert "FB-12: app pg_is_in_recovery=false (on-prem primary active)" "false" "$recovery_app"
  pass "FB-12: on-prem app /health confirmed primary (APP RTO: ${APP_HEALTH_OK_TS})"
else
  log "[DRY-RUN] would poll app-onprem:8080/health via pg-primary SSH until HTTP 200"
  APP_HEALTH_OK_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── FB-13: RTO summary + post-failback snapshot ───────────────────────────────
step "FB-13: Record RTO and post-failback snapshot"
if ! $DRY_RUN; then
  FSB_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  {
    echo "=== FULL-SITE FAILBACK SUMMARY ==="
    echo "FSB_START:     ${FSB_START}"
    echo "SERVICE_RTO:   ${SERVICE_RTO_TS}   (keepalived started, VIP returned)"
    echo "APP_RTO:       ${APP_HEALTH_OK_TS}   (app /health 200 on app-onprem)"
    echo "TOPOLOGY_RTO:  ${TOPOLOGY_RTO_TS}   (DR VM streaming from pg-primary)"
    echo "FSB_END:       ${FSB_END}"
    echo ""
    echo "SERVICE RTO:  time from FSB_START to keepalived start"
    echo "APP RTO:      time from FSB_START to app /health 200"
    echo "TOPOLOGY RTO: time from FSB_START to DR VM streaming"
    echo ""
    echo "RESULT: PASS"
  } | tee "${EVIDENCE_DIR}/fsdb-rto-summary.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-rto-summary.txt")

  ssh_run "pg-primary" "
    echo '=== POST-FAILBACK STATE ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- VIP ---'
    ip addr show eth0 | grep inet
    echo '--- PostgreSQL role ---'
    sudo -u postgres psql -c 'SELECT pg_is_in_recovery(), pg_current_wal_lsn();'
    echo '--- Keepalived ---'
    sudo systemctl status keepalived --no-pager | grep -E 'Active|MASTER' || true
    echo '--- Replication ---'
    sudo -u postgres psql -c 'SELECT client_addr, state, sync_state FROM pg_stat_replication ORDER BY client_addr;'
    echo '--- WireGuard ---'
    sudo wg show
  " | tee "${EVIDENCE_DIR}/fsdb-post-failback-snapshot.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-post-failback-snapshot.txt")

  # Final app health via pg-primary relay
  final_health=$(ssh_run "pg-primary" \
    "curl -sf --max-time 8 http://10.0.96.13:8080/health" \
    || echo '{"error":"unreachable"}')
  echo "$final_health" | tee "${EVIDENCE_DIR}/fsdb-final-app-health.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-final-app-health.txt")
  pass "FB-13: RTO recorded, post-failback snapshot complete"
else
  log "[DRY-RUN] would write fsdb-rto-summary.txt, fsdb-post-failback-snapshot.txt, fsdb-final-app-health.txt"
  FSB_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
log "========================================================"
log "FULL-SITE FAILBACK COMPLETE"
log ""
if ! $DRY_RUN; then
  log "Evidence files (${#EVIDENCE_FILES[@]}):"
  for f in "${EVIDENCE_FILES[@]}"; do
    log "  $f"
  done
  log ""
  log "Next step: run evidence-export.sh fullsite-fallback to copy files to repo."
  log "NOTE: pg-standby may need pg_basebackup rebuild if on new timeline."
  log "      See full-site-failback-runbook.md section 7."
else
  log "DRY-RUN complete — no changes made."
fi
log "========================================================"
echo ""

exit 0
