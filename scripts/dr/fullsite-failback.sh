#!/usr/bin/env bash
# fullsite-failback.sh — Full-site failback: Azure DR VM -> on-prem [SCAFFOLD]
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# STATUS: SCAFFOLD — gates, pre-checks, and two destructive confirmation guards
#         are implemented. Execution steps are marked NOT_IMPLEMENTED.
#         Review carefully before enabling. DO NOT remove NOT_IMPLEMENTED guards
#         without a dedicated review session.
#
# PURPOSE:
#   Execute the planned failback from Azure vm-pg-dr-fce (currently primary) back
#   to the on-prem pg-primary. Uses pg_basebackup twice: once to rebuild pg-primary
#   as a standby of the DR VM, and once to rebuild the DR VM as a standby of the
#   newly promoted pg-primary.
#
# DESTRUCTIVE OPERATIONS (two separate confirmation gates):
#   FB-3: pg_basebackup on pg-primary FROM DR VM
#         -> WIPES pg-primary data directory (rm -rf /var/lib/postgresql/16/main)
#         -> GATE 1: --confirm-destructive pg-primary
#
#   FB-8: pg_basebackup on vm-pg-dr-fce FROM pg-primary
#         -> WIPES DR VM data directory (rm -rf /var/lib/postgresql/16/main)
#         -> GATE 2: --confirm-destructive dr-vm
#
# USAGE:
#   ./scripts/dr/fullsite-failback.sh --confirm \
#       [--confirm-destructive pg-primary] \
#       [--confirm-destructive dr-vm] \
#       [--dry-run]
#
# OPTIONS:
#   --confirm                           Required baseline confirmation.
#   --confirm-destructive pg-primary    Acknowledge pg-primary data wipe (FB-3).
#   --confirm-destructive dr-vm         Acknowledge DR VM data wipe (FB-8).
#   --dry-run                           Print commands without executing.
#
# NOTE ON TIMING:
#   Service restoration RTO (FB-10: keepalived start -> VIP returns) is measured
#   separately from full topology restoration RTO (FB-9: DR VM streaming again).
#   The script records both timestamps independently.
#
# EXIT CODES:
#   0   PASS — failback completed and validated
#   1   FAIL — assertion failed
#   2   ABORTED — prerequisite check or gate failed
#   99  NOT_IMPLEMENTED step reached — scaffold boundary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_PREFIX="[fullsite-failback]"

CONFIRMED=false
CONFIRMED_DESTRUCTIVE_PRIMARY=false
CONFIRMED_DESTRUCTIVE_DRVM=false
DRY_RUN=false

LAG_CATCHUP_TIMEOUT=120    # seconds to wait for pg-primary to catch up to DR VM
APP_WAIT_TIMEOUT=60        # seconds to wait for app-onprem health

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
          exit 2
          ;;
      esac
      ;;
    --dry-run)   DRY_RUN=true ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -40
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

# ── helpers ───────────────────────────────────────────────────────────────────
log()  { echo "${LOG_PREFIX} $(date -u +%H:%M:%SZ) $*"; }
pass() { echo "${LOG_PREFIX} [PASS]  $*"; }
fail() { echo "${LOG_PREFIX} [FAIL]  $*" >&2; }
step() { echo ""; echo "${LOG_PREFIX} ===== $* ====="; }

NOT_IMPLEMENTED() {
  echo ""
  echo "${LOG_PREFIX} !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${LOG_PREFIX} NOT IMPLEMENTED: $*"
  echo "${LOG_PREFIX} This step is scaffolded but not yet safe to run."
  echo "${LOG_PREFIX} Review fullsite-failback.sh before enabling this step."
  echo "${LOG_PREFIX} !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  exit 99
}

DESTRUCTIVE_GATE() {
  local target="$1"
  local description="$2"
  local flag_var="CONFIRMED_DESTRUCTIVE_$(echo "$target" | tr '[:lower:]-' '[:upper:]_')"
  local confirmed="${!flag_var}"

  echo ""
  echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════════╗"
  echo "${LOG_PREFIX} ║  DESTRUCTIVE GATE: ${target}"
  echo "${LOG_PREFIX} ║  ${description}"
  echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════════╝"
  echo ""

  if ! $DRY_RUN && [[ "$confirmed" != "true" ]]; then
    echo "${LOG_PREFIX} BLOCKED: Pass --confirm-destructive ${target} to proceed past this gate."
    exit 2
  fi
  if $DRY_RUN; then
    echo "${LOG_PREFIX} [DRY-RUN] destructive gate '${target}' would be checked here"
  else
    log "Gate '${target}' confirmed. Proceeding."
  fi
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
  echo "================================================================"
  echo "  FULL-SITE FAILBACK (Azure DR -> on-prem)"
  echo "  STATUS: SCAFFOLD — execution steps NOT YET ENABLED"
  echo "================================================================"
  echo ""
  echo "  This script WILL (when fully enabled):"
  echo "    1. Stop app on vm-pg-dr-fce (Azure)"
  echo "    2. Set DR VM PostgreSQL to read-only"
  echo ""
  echo "  [GATE 1: --confirm-destructive pg-primary]"
  echo "    3. Stop postgresql on pg-primary"
  echo "    4. pg_basebackup on pg-primary FROM DR VM  <-- WIPES pg-primary data"
  echo "    5. Start pg-primary as standby"
  echo "    6. Wait for pg-primary to catch up to DR VM"
  echo "    7. Promote pg-primary (SELECT pg_promote())"
  echo ""
  echo "  [GATE 2: --confirm-destructive dr-vm]"
  echo "    8. Stop postgresql on DR VM"
  echo "    9. pg_basebackup on DR VM FROM pg-primary  <-- WIPES DR VM data"
  echo "   10. Start DR VM as standby"
  echo ""
  echo "   11. Start keepalived on pg-primary (VIP returns)  <-- SERVICE RTO"
  echo "   12. Start app on app-onprem"
  echo "   13. Validate /health on app-onprem"
  echo "   14. Verify DR VM streaming from pg-primary  <-- TOPOLOGY RTO"
  echo ""
  echo "  TIMING NOTE: service restoration RTO (step 11) is recorded"
  echo "  separately from full topology restoration RTO (step 14)."
  echo ""
  echo "  CURRENT STATE: Execution steps are NOT_IMPLEMENTED."
  echo ""
  echo "  Pass --confirm to run pre-checks."
  echo "================================================================"
  echo ""
  exit 2
fi

# ── step 0: SSH pre-check (IMPLEMENTED) ──────────────────────────────────────
step "STEP 0: SSH pre-check [MANDATORY — IMPLEMENTED]"
if ! $DRY_RUN; then
  if ! "${SCRIPT_DIR}/ssh-precheck.sh"; then
    fail "SSH pre-check failed. Aborting."
    exit 2
  fi
else
  log "[DRY-RUN] would run ssh-precheck.sh"
fi

# ── step 1: prerequisite checks H-1 through H-7 (IMPLEMENTED) ────────────────
step "STEP 1: Prerequisites H-1 through H-7 [IMPLEMENTED]"

log "H-1: Checking failover completed (DR VM pg_is_in_recovery=f)..."
dr_recovery=$(ssh_run "vm-pg-dr-fce" \
  "sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" || echo "error")
assert "H-1: vm-pg-dr-fce pg_is_in_recovery" "f" "$dr_recovery"

log "H-2: Checking DR VM app is running..."
if ! $DRY_RUN; then
  dr_app=$(ssh_run "vm-pg-dr-fce" \
    "sudo docker ps --filter name=clopr2-app-dr --format '{{.Status}}'" || echo "")
  if echo "$dr_app" | grep -qi "up"; then
    pass "H-2: clopr2-app-dr running: ${dr_app}"
  else
    fail "H-2: clopr2-app-dr not running (status='${dr_app}')"
    exit 1
  fi
fi

log "H-3: Checking pg-primary OS reachable..."
pg_primary_hostname=$(ssh_run "pg-primary" "hostname" || echo "error")
assert "H-3: pg-primary hostname" "pg-primary" "$pg_primary_hostname"

log "H-4: Checking pg-primary PostgreSQL is STOPPED..."
pg_primary_pg=$(ssh_run "pg-primary" "sudo systemctl is-active postgresql || echo inactive")
assert "H-4: pg-primary postgresql" "inactive" "$pg_primary_pg"

log "H-5: Checking WireGuard active on pg-primary..."
if ! $DRY_RUN; then
  wg_peer=$(ssh_run "pg-primary" \
    "sudo wg show wg0 2>/dev/null | grep -c 'peer:' || echo 0")
  assert "H-5: WireGuard peer present" "1" "$wg_peer"
fi

log "H-6: Checking replicator role on DR VM..."
if ! $DRY_RUN; then
  repl_role=$(ssh_run "vm-pg-dr-fce" \
    "sudo -u postgres psql -qtAc \"SELECT rolname FROM pg_roles WHERE rolname='replicator';\"" || echo "")
  repl_role=$(echo "$repl_role" | tr -d '[:space:]')
  assert "H-6: replicator role on DR VM" "replicator" "$repl_role"
fi

log "H-7: Checking pg_hba.conf allows replication from pg-primary..."
if ! $DRY_RUN; then
  hba_check=$(ssh_run "vm-pg-dr-fce" \
    "sudo grep -c 'replication' /etc/postgresql/16/main/pg_hba.conf || echo 0")
  if [[ "${hba_check:-0}" -ge 1 ]]; then
    pass "H-7: pg_hba.conf has replication entry"
  else
    fail "H-7: no replication entry in pg_hba.conf — add manually before proceeding"
    exit 1
  fi
fi

# ── record start time and pre-failback state (IMPLEMENTED) ───────────────────
step "STEP 2: Capture pre-failback state [IMPLEMENTED]"
if ! $DRY_RUN; then
  FSB_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "FSB_START: ${FSB_START}" > "${EVIDENCE_DIR}/fsdb-start-timestamp.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-start-timestamp.txt")
  log "Failback start: ${FSB_START}"

  ssh_run "vm-pg-dr-fce" "
    echo '=== FAILBACK PRE-CHECK ==='
    echo \"Timestamp: \$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    echo '--- DR VM PostgreSQL state ---'
    sudo -u postgres psql -c 'SELECT pg_is_in_recovery(), pg_current_wal_lsn(), now();'
    echo '--- pg_stat_replication (expect empty) ---'
    sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'
    echo '--- App running ---'
    sudo docker ps --filter name=clopr2-app-dr
  " | tee "${EVIDENCE_DIR}/fsdb-precheck.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fsdb-precheck.txt")
fi

# ── confirmation summary before destructive work ─────────────────────────────
step "PRE-DESTRUCTIVE SUMMARY"
log "All H-1..H-7 prerequisites passed."
log ""
log "Destructive steps that follow:"
log "  GATE 1 (--confirm-destructive pg-primary):"
log "    FB-1: Stop app on DR VM"
log "    FB-2: Set DR VM read-only"
log "    FB-3: WIPE pg-primary data dir + pg_basebackup from DR VM  <-- IRREVERSIBLE"
log ""
log "  GATE 2 (--confirm-destructive dr-vm):"
log "    FB-8: WIPE DR VM data dir + pg_basebackup from pg-primary  <-- IRREVERSIBLE"
log ""

# ── FB-1: Stop app on DR VM (NOT IMPLEMENTED — behind GATE 1) ─────────────────
step "FB-1: Stop app on vm-pg-dr-fce [NOT IMPLEMENTED]"
DESTRUCTIVE_GATE "pg-primary" "GATE 1: confirms fb-3 pg-primary data wipe"
NOT_IMPLEMENTED "FB-1: ssh vm-pg-dr-fce 'sudo docker stop clopr2-app-dr && sudo docker rm clopr2-app-dr'"

# ── FB-2: Set DR VM read-only (NOT IMPLEMENTED) ───────────────────────────────
step "FB-2: Set DR VM to read-only [NOT IMPLEMENTED]"
NOT_IMPLEMENTED "FB-2: ssh vm-pg-dr-fce 'sudo -u postgres psql -c ALTER SYSTEM SET default_transaction_read_only = on'"

# ── FB-3: pg_basebackup on pg-primary (DESTRUCTIVE — NOT IMPLEMENTED) ─────────
step "FB-3: pg_basebackup on pg-primary FROM DR VM [DESTRUCTIVE — NOT IMPLEMENTED]"
echo ""
echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════════╗"
echo "${LOG_PREFIX} ║  DESTRUCTIVE: rm -rf /var/lib/postgresql/16/main            ║"
echo "${LOG_PREFIX} ║  on pg-primary (10.0.96.11) then pg_basebackup from DR VM   ║"
echo "${LOG_PREFIX} ║  Source: vm-pg-dr-fce (10.200.0.2) via WireGuard            ║"
echo "${LOG_PREFIX} ║  Flags: -h 10.200.0.2 -U replicator -R -P --wal-method=stream ║"
echo "${LOG_PREFIX} ║  IMPORTANT: postgresql.auto.conf cleanup required after:    ║"
echo "${LOG_PREFIX} ║    Remove duplicate primary_conninfo if present             ║"
echo "${LOG_PREFIX} ║    Remove default_transaction_read_only=on if inherited     ║"
echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════════╝"
echo ""
NOT_IMPLEMENTED "FB-3: pg_basebackup on pg-primary (WIPES DATA DIR)"

# ── FB-4: Start pg-primary as standby (NOT IMPLEMENTED) ──────────────────────
step "FB-4: Start pg-primary as standby [NOT IMPLEMENTED]"
echo "${LOG_PREFIX} When enabled: systemctl start postgresql, assert pg_is_in_recovery=t"
NOT_IMPLEMENTED "FB-4: ssh pg-primary 'sudo systemctl start postgresql'"

# ── FB-5 through FB-7: verify streaming + promote (NOT IMPLEMENTED) ──────────
step "FB-5 to FB-7: Verify streaming and promote pg-primary [NOT IMPLEMENTED]"
echo "${LOG_PREFIX} FB-5: Assert DR VM pg_stat_replication shows 10.200.0.1 streaming"
echo "${LOG_PREFIX} FB-6: Poll catchup lag to near-zero (timeout ${LAG_CATCHUP_TIMEOUT}s)"
echo "${LOG_PREFIX} FB-7: SELECT pg_promote() on pg-primary, assert pg_is_in_recovery=f"
echo "${LOG_PREFIX}       Gate: assert DR VM read-only still set before promoting"
NOT_IMPLEMENTED "FB-5 to FB-7: catchup + promote pg-primary"

# ── FB-8: pg_basebackup on DR VM (DESTRUCTIVE GATE 2 — NOT IMPLEMENTED) ──────
step "FB-8: pg_basebackup on DR VM FROM pg-primary [DESTRUCTIVE GATE 2 — NOT IMPLEMENTED]"
DESTRUCTIVE_GATE "dr-vm" "GATE 2: confirms fb-8 dr-vm data wipe"
echo ""
echo "${LOG_PREFIX} ╔══════════════════════════════════════════════════════════════╗"
echo "${LOG_PREFIX} ║  DESTRUCTIVE: rm -rf /var/lib/postgresql/16/main            ║"
echo "${LOG_PREFIX} ║  on vm-pg-dr-fce (10.200.0.2) then pg_basebackup from        ║"
echo "${LOG_PREFIX} ║  pg-primary (10.200.0.1, WireGuard IP)                      ║"
echo "${LOG_PREFIX} ║  Before wiping: undo read-only: ALTER SYSTEM RESET           ║"
echo "${LOG_PREFIX} ╚══════════════════════════════════════════════════════════════╝"
echo ""
NOT_IMPLEMENTED "FB-8: pg_basebackup on vm-pg-dr-fce (WIPES DATA DIR)"

# ── FB-9 through FB-13: app restore + validation (NOT IMPLEMENTED) ────────────
step "FB-9 to FB-13: Service restore, VIP, app, validation [NOT IMPLEMENTED]"
echo "${LOG_PREFIX} FB-9:  Verify DR VM streaming from pg-primary"
echo "${LOG_PREFIX} FB-10: Start keepalived on pg-primary -> VIP returns  [SERVICE RTO POINT]"
echo "${LOG_PREFIX} FB-11: Start app on app-onprem (SSH multi-hop relay)"
echo "${LOG_PREFIX} FB-12: Validate /health (assert pg_is_in_recovery=false)"
echo "${LOG_PREFIX} FB-13: Record FSB_END timestamps:"
echo "${LOG_PREFIX}          service_rto = time from FSB_START to FB-10 VIP returned"
echo "${LOG_PREFIX}          topology_rto = time from FSB_START to FB-9 DR VM streaming"
NOT_IMPLEMENTED "FB-9 to FB-13: service restore and validation"

echo ""
log "========================================================"
log "SCAFFOLD BOUNDARY REACHED — no destructive steps executed."
log ""
log "Prerequisite checks PASSED (H-1 through H-7)."
log "Pre-failback state captured."
log ""
log "Review and enable execution steps before running again."
log "Each destructive gate requires its own --confirm-destructive flag."
log "========================================================"
echo ""

exit 0
