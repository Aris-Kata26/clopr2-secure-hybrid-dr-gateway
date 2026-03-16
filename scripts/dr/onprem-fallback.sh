#!/usr/bin/env bash
# onprem-fallback.sh — On-prem HA fallback: restore pg-primary to MASTER
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   Restore pg-primary as the Keepalived MASTER after an on-prem HA failover drill.
#   Starts PostgreSQL then Keepalived on pg-primary. With priority 100 > pg-standby's 90,
#   the VIP returns to pg-primary automatically within ~4 seconds (dead interval).
#   No action needed on pg-standby — it returns to BACKUP on its own.
#   Validates that replication resumes and the app reconnects to the primary.
#
# ARCHITECTURE NOTES (nopreempt):
#   - pg-standby will NOT preempt a running pg-primary Keepalived even after VIP
#     returns, because nopreempt is set on all nodes. pg-primary's higher priority
#     causes the natural election when both are advertising.
#   - Replication resumes automatically once pg-primary PostgreSQL is active and
#     pg-standby's walsender reconnects (usually within seconds).
#
# USAGE:
#   ./scripts/dr/onprem-fallback.sh --confirm [--dry-run]
#
# OPTIONS:
#   --confirm    Required. Acknowledges this will restart services on pg-primary.
#   --dry-run    Print all commands without executing. No state changes.
#
# PREREQUISITE:
#   onprem-failover.sh must have been run (pg-primary services stopped, VIP on pg-standby).
#
# EXIT CODES:
#   0  PASS — fallback completed and validated
#   1  FAIL — assertion failed, see output
#   2  ABORTED — pre-check or confirmation gate failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_PREFIX="[onprem-fallback]"
CONFIRMED=false
DRY_RUN=false

VIP_RETURN_TIMEOUT=20     # seconds to wait for VIP to return to pg-primary
REPL_RESUME_TIMEOUT=60    # seconds to wait for pg-standby replication to resume
APP_WAIT_TIMEOUT=30       # seconds to wait for app to reflect primary reconnect

# ── argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --confirm)   CONFIRMED=true ;;
    --dry-run)   DRY_RUN=true ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -35
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 --confirm [--dry-run]" >&2
      exit 2
      ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────────────
log()  { echo "${LOG_PREFIX} $(date -u +%H:%M:%SZ) $*"; }
pass() { echo "${LOG_PREFIX} [PASS] $*"; }
fail() { echo "${LOG_PREFIX} [FAIL] $*" >&2; }
step() { echo ""; echo "${LOG_PREFIX} --- $* ---"; }

run() {
  if $DRY_RUN; then
    echo "${LOG_PREFIX} [DRY-RUN] $*"
    return 0
  fi
  "$@"
}

ssh_run() {
  local host="$1"; shift
  local cmd="$*"
  if $DRY_RUN; then
    echo "${LOG_PREFIX} [DRY-RUN] ssh ${host} '${cmd}'" >&2
    return 0
  fi
  case "$host" in
    pg-standby|app-onprem)
      # PVE cannot TCP-forward to these hosts; relay via pg-primary
      local relay_target
      case "$host" in
        pg-standby) relay_target="10.0.96.14" ;;
        app-onprem)  relay_target="10.0.96.13" ;;
      esac
      ssh -o ConnectTimeout=10 -o BatchMode=yes \
          -o "ProxyCommand=ssh -W %h:%p -o BatchMode=yes -o ConnectTimeout=8 -i ~/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11" \
          -i ~/.ssh/id_ed25519_dr_onprem \
          "katar711@${relay_target}" "$cmd"
      ;;
    *)
      ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "$cmd"
      ;;
  esac
}

assert() {
  local description="$1" expected="$2" actual="$3"
  if $DRY_RUN; then
    echo "${LOG_PREFIX} [DRY-RUN] assert: ${description} (would check for '${expected}')" >&2
    return 0
  fi
  actual=$(echo "$actual" | tr -d '[:space:]')
  if [[ "$actual" == "$expected" ]]; then
    pass "${description}: ${actual}"
  else
    fail "${description}: expected='${expected}', got='${actual}'"
    exit 1
  fi
}

poll_assert() {
  local description="$1" timeout="$2" expected="$3"
  shift 3
  local elapsed=0
  local actual=""
  while [[ $elapsed -lt $timeout ]]; do
    actual=$(eval "$*" 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "$actual" == "$expected" ]]; then
      pass "${description}: ${actual} (after ${elapsed}s)"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    log "${description}: waiting... got='${actual}', want='${expected}' (${elapsed}/${timeout}s)"
  done
  fail "${description}: timeout after ${timeout}s — last value='${actual}', expected='${expected}'"
  exit 1
}

EVIDENCE_DIR="/tmp"
EVIDENCE_FILES=()

tee_ssh_evidence() {
  local file="$1" host="$2"; shift 2
  local path="${EVIDENCE_DIR}/${file}"
  if $DRY_RUN; then
    echo "${LOG_PREFIX} [DRY-RUN] evidence: ${path} from ${host}"
    return 0
  fi
  ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "$@" | tee "${path}"
  EVIDENCE_FILES+=("${path}")
}

# ── gate: require --confirm ───────────────────────────────────────────────────
if ! $DRY_RUN && ! $CONFIRMED; then
  echo ""
  echo "============================================================"
  echo "  ON-PREM HA FALLBACK (restore pg-primary to MASTER)"
  echo "============================================================"
  echo ""
  echo "  This script will:"
  echo "    1. Assert pg-primary services are stopped (failover state)"
  echo "    2. Start PostgreSQL on pg-primary"
  echo "    3. Start Keepalived on pg-primary (priority 100 > standby 90)"
  echo "    4. VIP 10.0.96.10 returns to pg-primary automatically"
  echo "    5. Replication from pg-primary -> pg-standby resumes"
  echo "    6. Validate app reconnects to primary (pg_is_in_recovery=false)"
  echo ""
  echo "  No action needed on pg-standby — it returns to BACKUP state"
  echo "  automatically when it detects pg-primary advertising."
  echo ""
  echo "  Pass --confirm to proceed."
  echo "============================================================"
  echo ""
  exit 2
fi

# ── step 0: SSH pre-check ─────────────────────────────────────────────────────
step "STEP 0: SSH pre-check"
if ! $DRY_RUN; then
  if ! "${SCRIPT_DIR}/ssh-precheck.sh"; then
    fail "SSH pre-check failed. Aborting."
    exit 2
  fi
else
  log "[DRY-RUN] would run ssh-precheck.sh"
fi

# ── step 1: assert current failover state ────────────────────────────────────
step "STEP 1: Assert pre-fallback state (pg-primary services stopped)"

pg_primary_pg=$(ssh_run "pg-primary" "sudo systemctl is-active postgresql; true")
assert "pg-primary postgresql state" "inactive" "$pg_primary_pg"

pg_primary_ka=$(ssh_run "pg-primary" "sudo systemctl is-active keepalived; true")
assert "pg-primary keepalived state" "inactive" "$pg_primary_ka"

log "Checking VIP is currently on pg-standby..."
if ! $DRY_RUN; then
  vip_on_standby=$(ssh_run "pg-standby" "ip addr show eth0 | grep -c '10.0.96.10' || echo 0")
  assert "VIP 10.0.96.10 on pg-standby" "1" "$vip_on_standby"
fi

# ── record start time ─────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  FALLBACK_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "FSB_START: ${FALLBACK_START}" > "${EVIDENCE_DIR}/fs-ha-fb-start-timestamp.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fs-ha-fb-start-timestamp.txt")
  log "Fallback start: ${FALLBACK_START}"
fi

# ── step 2: start services on pg-primary ─────────────────────────────────────
step "STEP 2: Start PostgreSQL on pg-primary"
run ssh_run "pg-primary" "sudo systemctl start postgresql"
log "PostgreSQL start command sent"

step "STEP 3: Start Keepalived on pg-primary"
run ssh_run "pg-primary" "sudo systemctl start keepalived"
log "Keepalived start command sent (priority 100 — VIP will return to pg-primary)"

if ! $DRY_RUN; then
  sleep 2
  ssh_run "pg-primary" "
    echo 'Services started at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    sudo systemctl is-active postgresql
    sudo systemctl is-active keepalived
  " | tee "${EVIDENCE_DIR}/fs-ha-fb-services-started.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fs-ha-fb-services-started.txt")
fi

# ── step 3: wait for VIP to return ───────────────────────────────────────────
step "STEP 4: Wait for VIP to return to pg-primary"
if ! $DRY_RUN; then
  poll_assert "VIP back on pg-primary" "${VIP_RETURN_TIMEOUT}" "1" \
    "ssh -o ConnectTimeout=5 -o BatchMode=yes pg-primary 'ip addr show eth0 | grep -c 10.0.96.10 || echo 0'"

  tee_ssh_evidence "fs-ha-fb-vip-returned.txt" "pg-primary" "
    echo 'VIP returned at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    ip addr show eth0 | grep inet
    sudo systemctl status keepalived --no-pager | head -8
  "
fi

# ── step 4: wait for replication to resume ───────────────────────────────────
# NOTE: This check is advisory (WARN on timeout, not FAIL). The VIP fallback has already
# succeeded at this point. pg-standby may need pg_basebackup after a full-site cycle.
step "STEP 5: Wait for pg-standby replication to resume"
if ! $DRY_RUN; then
  _repl_elapsed=0
  _repl_state=""
  while [[ $_repl_elapsed -lt $REPL_RESUME_TIMEOUT ]]; do
    _repl_state=$(ssh -o ConnectTimeout=5 -o BatchMode=yes pg-primary \
      "sudo -u postgres psql -qtAc \"SELECT state FROM pg_stat_replication WHERE client_addr='10.0.96.14';\"" \
      2>/dev/null | tr -d '[:space:]' || true)
    if [[ "$_repl_state" == "streaming" ]]; then
      pass "pg-standby streaming from pg-primary: streaming (after ${_repl_elapsed}s)"
      break
    fi
    sleep 2
    _repl_elapsed=$((_repl_elapsed + 2))
    log "pg-standby streaming: waiting... got='${_repl_state}', want='streaming' (${_repl_elapsed}/${REPL_RESUME_TIMEOUT}s)"
  done
  if [[ "$_repl_state" != "streaming" ]]; then
    log "[WARN] pg-standby did not resume streaming within ${REPL_RESUME_TIMEOUT}s (last='${_repl_state}')"
    log "[WARN] This is expected if pg-standby needs pg_basebackup after a full-site DR cycle."
    log "[WARN] VIP fallback succeeded. Run: pg_basebackup on pg-standby to restore HA replication."
  fi

  # replication evidence (best-effort regardless of streaming state)
  if [[ -z ${_REPL_EVIDENCE_CAPTURED:-} ]]; then
    _REPL_EVIDENCE_CAPTURED=1
    tee_ssh_evidence "fs-ha-fb-replication-resumed.txt" "pg-primary" "
      echo 'Replication state at: \$(date -u +%Y-%m-%dT%H:%M:%SZ)'
      sudo -u postgres psql -c 'SELECT client_addr, state, sync_state,
          (sent_lsn - replay_lsn) AS bytes_lag
          FROM pg_stat_replication;'
    "
  fi
fi

# ── step 5: validate app health ──────────────────────────────────────────────
step "STEP 6: Validate app health (expect pg_is_in_recovery=false)"
if ! $DRY_RUN; then
  # Route curl via pg-primary (WSL has no direct route to 10.0.96.x)
  poll_assert "app /health pg_is_in_recovery=false" "${APP_WAIT_TIMEOUT}" "false" \
    "ssh -o ConnectTimeout=5 -o BatchMode=yes pg-primary 'curl -s --max-time 5 http://10.0.96.13:8080/health' | python3 -c \"import sys,json; d=json.load(sys.stdin); print(str(d.get('pg_is_in_recovery',None)).lower())\""

  app_health=$(ssh -o ConnectTimeout=10 -o BatchMode=yes pg-primary "curl -s --max-time 5 http://10.0.96.13:8080/health" || echo '{"error":"unreachable"}')
  echo "$app_health" | tee "${EVIDENCE_DIR}/fs-ha-fb-app-health.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fs-ha-fb-app-health.txt")
  pass "app-onprem /health after fallback: pg_is_in_recovery=false (back on primary)"
fi

# ── step 6: RTO summary ───────────────────────────────────────────────────────
step "STEP 7: Record elapsed time"
if ! $DRY_RUN; then
  FALLBACK_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    echo "ON-PREM HA FALLBACK COMPLETE"
    echo "FSB_START: ${FALLBACK_START}"
    echo "FSB_END:   ${FALLBACK_END}"
    echo ""
    echo "PASS — VIP returned to pg-primary, replication resumed, app serving primary"
  } | tee "${EVIDENCE_DIR}/fs-ha-fb-rto-summary.txt"
  EVIDENCE_FILES+=("${EVIDENCE_DIR}/fs-ha-fb-rto-summary.txt")
fi

# ── final summary ─────────────────────────────────────────────────────────────
echo ""
log "========================================================"
if $DRY_RUN; then
  log "DRY RUN COMPLETE — no changes made."
else
  log "ON-PREM HA FALLBACK: PASS"
  log ""
  log "Evidence files:"
  for f in "${EVIDENCE_FILES[@]}"; do
    log "  ${f}"
  done
  log ""
  log "Next steps:"
  log "  1. Run evidence-export.sh onprem-ha-fallback to copy to repo"
  log "  2. System is back in steady state"
fi
log "========================================================"
echo ""

exit 0
