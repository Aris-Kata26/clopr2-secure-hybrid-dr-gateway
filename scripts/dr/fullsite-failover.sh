#!/usr/bin/env bash
# fullsite-failover.sh — Full-site failover: on-prem -> Azure DR VM [SCAFFOLD]
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# STATUS: SCAFFOLD — gates and checks are implemented, execution steps are marked
#         NOT_IMPLEMENTED. Review carefully before enabling. DO NOT remove the
#         NOT_IMPLEMENTED guards without a full review session.
#
# PURPOSE:
#   Execute the full-site failover from on-prem Proxmox to Azure vm-pg-dr-fce.
#   Stops on-prem PostgreSQL and Keepalived, waits for DR VM WAL replay to catch up,
#   promotes the DR VM PostgreSQL, and starts the app on Azure.
#
# DESTRUCTIVE OPERATIONS:
#   FS-3: Stops postgresql + keepalived on pg-primary
#         -> IRREVERSIBLE in the sense that the DR VM becomes the active primary
#         -> Reversible via fullsite-failback.sh (requires pg_basebackup)
#
# USAGE:
#   ./scripts/dr/fullsite-failover.sh --confirm [--dry-run] [--wal-lag-threshold <bytes>]
#
# OPTIONS:
#   --confirm                  Required. Acknowledges destructive steps.
#   --dry-run                  Print commands without executing.
#   --wal-lag-threshold <n>    Max bytes lag before promotion (default: 1024)
#
# PREREQUISITES (all validated automatically):
#   - SSH pre-check passes (all hosts reachable)
#   - pg-primary is primary (pg_is_in_recovery=f)
#   - DR VM is replica (pg_is_in_recovery=t)
#   - WireGuard handshake < 5 min
#   - DR VM Docker image present
#   - App-onprem /health healthy
#
# EXIT CODES:
#   0   PASS — failover completed and validated
#   1   FAIL — assertion failed
#   2   ABORTED — prerequisite check or gate failed
#   99  NOT_IMPLEMENTED step reached — scaffold boundary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_PREFIX="[fullsite-failover]"
CONFIRMED=false
DRY_RUN=false
WAL_LAG_THRESHOLD=1024   # bytes — promote only when DR VM lag <= this value

WAL_REPLAY_TIMEOUT=120   # seconds to wait for DR VM WAL lag to reach threshold
APP_WAIT_TIMEOUT=60      # seconds to wait for DR VM app health

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)               CONFIRMED=true ;;
    --dry-run)               DRY_RUN=true ;;
    --wal-lag-threshold)     shift; WAL_LAG_THRESHOLD="$1" ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -35
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
log()  { echo "${LOG_PREFIX} $(date -u +%H:%M:%SZ) $*"; }
pass() { echo "${LOG_PREFIX} [PASS]  $*"; }
fail() { echo "${LOG_PREFIX} [FAIL]  $*" >&2; }
warn() { echo "${LOG_PREFIX} [WARN]  $*"; }
step() { echo ""; echo "${LOG_PREFIX} ===== $* ====="; }

NOT_IMPLEMENTED() {
  echo ""
  echo "${LOG_PREFIX} !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${LOG_PREFIX} NOT IMPLEMENTED: $*"
  echo "${LOG_PREFIX} This step is scaffolded but not yet safe to run."
  echo "${LOG_PREFIX} Review fullsite-failover.sh before enabling this step."
  echo "${LOG_PREFIX} !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  exit 99
}

ssh_run() {
  local host="$1"; shift
  local cmd="$*"
  if $DRY_RUN; then
    echo "${LOG_PREFIX} [DRY-RUN] ssh ${host} '${cmd}'"
    return 0
  fi
  ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "$cmd"
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

EVIDENCE_DIR="/tmp"
EVIDENCE_FILES=()

# ── gate: require --confirm ───────────────────────────────────────────────────
if ! $DRY_RUN && ! $CONFIRMED; then
  echo ""
  echo "============================================================"
  echo "  FULL-SITE FAILOVER (on-prem -> Azure DR)"
  echo "  STATUS: SCAFFOLD — execution steps NOT YET ENABLED"
  echo "============================================================"
  echo ""
  echo "  This script WILL (when fully enabled):"
  echo "    1. Stop app on app-onprem"
  echo "    2. Record final LSN on pg-primary"
  echo "    3. Stop PostgreSQL + Keepalived on pg-primary  [DESTRUCTIVE]"
  echo "       -> After this point, failback requires pg_basebackup"
  echo "    4. Wait for DR VM to replay all remaining WAL"
  echo "    5. Promote DR VM to primary (SELECT pg_promote())"
  echo "    6. Start app on DR VM"
  echo "    7. Validate /health on DR VM"
  echo ""
  echo "  CURRENT STATE: Steps FS-1 through FS-10 are NOT_IMPLEMENTED."
  echo "  The gates, pre-checks, and assertions are implemented."
  echo "  Execution steps will be enabled after review."
  echo ""
  echo "  Pass --confirm to run the implemented sections (pre-checks only)."
  echo "============================================================"
  echo ""
  exit 2
fi

# ── step 0: SSH pre-check (IMPLEMENTED) ──────────────────────────────────────
step "STEP 0: SSH pre-check [MANDATORY]"
if ! $DRY_RUN; then
  if ! "${SCRIPT_DIR}/ssh-precheck.sh"; then
    fail "SSH pre-check failed. Aborting."
    exit 2
  fi
else
  log "[DRY-RUN] would run ssh-precheck.sh"
fi

# ── step 1: run preflight (IMPLEMENTED) ──────────────────────────────────────
step "STEP 1: Full preflight check [IMPLEMENTED]"
if ! $DRY_RUN; then
  if ! "${SCRIPT_DIR}/dr-preflight.sh" fullsite; then
    fail "Preflight checks failed. Aborting."
    exit 2
  fi
else
  log "[DRY-RUN] would run dr-preflight.sh fullsite"
fi

# ── step 2: verify DR VM SSH session can be established (IMPLEMENTED) ─────────
step "STEP 2: Verify DR VM SSH access [IMPLEMENTED]"
log "CRITICAL: A persistent SSH session to vm-pg-dr-fce must be established"
log "BEFORE pg-primary is stopped. The script validates this is possible."
log "In the full implementation, the operator must maintain a dedicated terminal"
log "with an open SSH session to vm-pg-dr-fce throughout the failover."
echo ""
log "NSG reminder: vm-pg-dr-fce SSH (port 22) accepts connections from 10.200.0.1 ONLY."
log "The ProxyCommand in ~/.ssh/config routes through pg-primary WireGuard interface."
log "Once pg-primary services are stopped, WireGuard remains active (OS running)."

dr_vm_check=$(ssh_run "vm-pg-dr-fce" "echo DR_VM_OK && sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" || echo "error")
if ! $DRY_RUN; then
  if echo "$dr_vm_check" | grep -q "DR_VM_OK"; then
    recovery=$(echo "$dr_vm_check" | grep -v "DR_VM_OK" | tr -d '[:space:]')
    assert "vm-pg-dr-fce pg_is_in_recovery" "t" "$recovery"
    pass "DR VM SSH session confirmed — safe to proceed"
  else
    fail "Cannot reach vm-pg-dr-fce. Check WireGuard and SSH chain."
    exit 2
  fi
fi

# ── record pre-failover state (IMPLEMENTED) ──────────────────────────────────
step "STEP 3: Capture pre-failover state [IMPLEMENTED]"
if ! $DRY_RUN; then
  FSO_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "FSO_START: ${FSO_START}" > "${EVIDENCE_DIR}/fsdr-start-timestamp.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-start-timestamp.txt")

  ssh_run "pg-primary" "
    echo '=== FULL SITE FAILOVER PRE-CHECK ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- pg_stat_replication ---'
    sudo -u postgres psql -c \"SELECT client_addr, state,
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

  app_health=$(curl -sf --max-time 5 "http://10.0.96.13:8080/health" || echo '{"error":"unreachable"}')
  echo "$app_health" | tee "${EVIDENCE_DIR}/fsdr-precheck-app-health.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-precheck-app-health.txt")

  ssh_run "vm-pg-dr-fce" "
    echo '=== DR VM PRE-CHECK ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    sudo -u postgres psql -c \"SELECT pg_is_in_recovery(), now() - pg_last_xact_replay_timestamp() AS lag;\"
    sudo docker image ls clopr2-app
  " | tee "${EVIDENCE_DIR}/fsdr-precheck-drvm.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdr-precheck-drvm.txt")
fi

# ── confirmation gate (IMPLEMENTED) ──────────────────────────────────────────
step "CONFIRMATION GATE — review then proceed"
echo ""
echo "${LOG_PREFIX} All pre-checks passed. The following DESTRUCTIVE steps are next:"
echo "${LOG_PREFIX}   FS-1: Stop app on app-onprem"
echo "${LOG_PREFIX}   FS-2: Record final LSN"
echo "${LOG_PREFIX}   FS-3: Stop postgresql + keepalived on pg-primary  <-- POINT OF NO EASY RETURN"
echo "${LOG_PREFIX}   FS-4: Wait for WAL replay on DR VM"
echo "${LOG_PREFIX}   FS-5: Promote DR VM"
echo "${LOG_PREFIX}   FS-6: Start app on DR VM"
echo ""

# ── FS-1: Stop app on app-onprem (NOT IMPLEMENTED — enable after review) ─────
step "FS-1: Stop app on app-onprem"
NOT_IMPLEMENTED "FS-1: ssh app-onprem 'cd /opt/clopr2/deploy/docker && sudo docker compose down'"
# When enabled, this should:
# ssh -i ~/.ssh/id_ed25519_dr_onprem -o ProxyJump=pve katar711@10.0.96.13 \
#   'cd /opt/clopr2/deploy/docker && sudo docker compose down; echo "App stopped at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"' \
#   | tee /tmp/fsdr-app-stopped.txt

# ── FS-2: Record final LSN (NOT IMPLEMENTED) ─────────────────────────────────
step "FS-2: Record final LSN on pg-primary"
NOT_IMPLEMENTED "FS-2: ssh pg-primary 'sudo -u postgres psql -c SELECT pg_current_wal_lsn()...'"
# When enabled:
# ssh_run "pg-primary" "sudo -u postgres psql -c \"
#   SELECT pg_current_wal_lsn() AS final_lsn, now() AS captured_at,
#          client_addr, replay_lsn,
#          (pg_current_wal_lsn() - replay_lsn) AS bytes_lag
#   FROM pg_stat_replication WHERE client_addr = '10.200.0.2';\"" | tee /tmp/fsdr-final-lsn.txt

# ── FS-3: Stop pg-primary services (NOT IMPLEMENTED — DESTRUCTIVE) ────────────
step "FS-3: Stop pg-primary services [DESTRUCTIVE — NOT IMPLEMENTED]"
echo ""
echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════╗"
echo "${LOG_PREFIX} ║  DESTRUCTIVE STEP — NOT IMPLEMENTED                     ║"
echo "${LOG_PREFIX} ║  When enabled, this step will:                           ║"
echo "${LOG_PREFIX} ║    sudo systemctl stop postgresql  (on pg-primary)       ║"
echo "${LOG_PREFIX} ║    sudo systemctl stop keepalived  (on pg-primary)       ║"
echo "${LOG_PREFIX} ║                                                           ║"
echo "${LOG_PREFIX} ║  After this step, recovery requires pg_basebackup.       ║"
echo "${LOG_PREFIX} ║  WireGuard is NOT stopped — SSH chain to DR VM stays up. ║"
echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════╝"
echo ""
NOT_IMPLEMENTED "FS-3: ssh pg-primary 'sudo systemctl stop postgresql && sudo systemctl stop keepalived'"

# ── FS-4: Wait for DR VM WAL replay (NOT IMPLEMENTED) ────────────────────────
step "FS-4: Wait for DR VM WAL replay catch-up [NOT IMPLEMENTED]"
echo "${LOG_PREFIX} When enabled: polls DR VM replay_lsn until it stops advancing"
echo "${LOG_PREFIX} WAL lag threshold: ${WAL_LAG_THRESHOLD} bytes"
NOT_IMPLEMENTED "FS-4: poll vm-pg-dr-fce pg_last_wal_replay_lsn until stable"
# When enabled:
# poll until replay_lsn stops advancing AND
# (pg_current_wal_lsn_on_dr_vm_mock - replay_lsn) <= WAL_LAG_THRESHOLD
# Timeout: WAL_REPLAY_TIMEOUT seconds

# ── FS-5: Promote DR VM (NOT IMPLEMENTED) ────────────────────────────────────
step "FS-5: Promote vm-pg-dr-fce [NOT IMPLEMENTED]"
echo "${LOG_PREFIX} When enabled: SELECT pg_promote() on vm-pg-dr-fce"
echo "${LOG_PREFIX} Gate: assert lag <= ${WAL_LAG_THRESHOLD} bytes before promoting"
NOT_IMPLEMENTED "FS-5: ssh vm-pg-dr-fce 'sudo -u postgres psql -c SELECT pg_promote()'"

# ── FS-6: Start app on DR VM (NOT IMPLEMENTED) ───────────────────────────────
step "FS-6: Start app on vm-pg-dr-fce [NOT IMPLEMENTED]"
echo "${LOG_PREFIX} When enabled: docker run --network host clopr2-app:dr"
echo "${LOG_PREFIX} Note: --network host required for DB_HOST=127.0.0.1 to reach host PG"
echo "${LOG_PREFIX} Note: app listens on port 8000 (not 8080) with --network host"
NOT_IMPLEMENTED "FS-6: ssh vm-pg-dr-fce 'sudo docker run -d --name clopr2-app-dr --network host ...'"

# ── FS-7: Validate app health (NOT IMPLEMENTED) ───────────────────────────────
step "FS-7: Validate app health on DR VM [NOT IMPLEMENTED]"
echo "${LOG_PREFIX} When enabled: curl http://localhost:8000/health"
echo "${LOG_PREFIX} Assert: pg_is_in_recovery=false, status=ok, app_env=dr-azure"
NOT_IMPLEMENTED "FS-7: curl vm-pg-dr-fce localhost:8000/health"

# ── FS-8 through FS-10: evidence + RTO (NOT IMPLEMENTED) ─────────────────────
step "FS-8 through FS-10: Evidence capture + RTO record [NOT IMPLEMENTED]"
NOT_IMPLEMENTED "FS-8 to FS-10: capture evidence files and RTO summary"

echo ""
log "========================================================"
log "SCAFFOLD BOUNDARY REACHED — no destructive steps executed."
log ""
log "Pre-checks PASSED. DR environment is in steady state."
log "Review and enable execution steps before running again."
log "========================================================"
echo ""

exit 0
