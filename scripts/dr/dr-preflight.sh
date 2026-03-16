#!/usr/bin/env bash
# dr-preflight.sh — Pre-drill readiness check for DR operations
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   Validate that the environment is in the correct steady state before beginning
#   any DR drill. Checks replication health, service states, VIP location, WireGuard
#   handshake, and application health. Read-only — no state changes made.
#
# USAGE:
#   ./scripts/dr/dr-preflight.sh <workflow>
#
# WORKFLOWS:
#   onprem-ha     On-prem HA drill (failover or fallback between pg-primary/pg-standby)
#   fullsite      Full-site drill (failover or failback to/from Azure)
#
# OPTIONS:
#   --verbose     Show full command output for failing checks
#
# EXIT CODES:
#   0  All checks pass — safe to proceed
#   1  One or more checks failed
#   2  Usage error

set -euo pipefail

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_PREFIX="[dr-preflight ${TIMESTAMP}]"
VERBOSE=false
WORKFLOW=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Thresholds
MAX_REPLICATION_LAG_BYTES=65536      # 64 KB — flag if higher
MAX_WG_HANDSHAKE_AGE_SECONDS=300     # 5 min — flag if older
APP_HEALTH_URL_ONPREM="http://10.0.96.13:8080/health"
APP_HEALTH_URL_DR="http://localhost:8000/health"

# ── argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    onprem-ha|fullsite) WORKFLOW="$arg" ;;
    --verbose)          VERBOSE=true ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -30
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 <onprem-ha|fullsite> [--verbose]" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$WORKFLOW" ]]; then
  echo "Error: workflow is required" >&2
  echo "Usage: $0 <onprem-ha|fullsite> [--verbose]" >&2
  exit 2
fi

# ── helpers ───────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log()  { echo "${LOG_PREFIX} $*"; }
pass() { printf "  %-42s  \033[32mPASS\033[0m  %s\n" "$1" "$2"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf "  %-42s  \033[31mFAIL\033[0m  %s\n" "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }
warn() { printf "  %-42s  \033[33mWARN\033[0m  %s\n" "$1" "$2"; WARN_COUNT=$((WARN_COUNT+1)); }
skip() { printf "  %-42s  \033[90mSKIP\033[0m  %s\n" "$1" "$2"; }

ssh_cmd() {
  local host="$1"; shift
  case "$host" in
    pg-standby|app-onprem)
      # PVE cannot TCP-forward to these hosts; relay via pg-primary
      local relay_target
      case "$host" in
        pg-standby) relay_target="10.0.96.14" ;;
        app-onprem)  relay_target="10.0.96.13" ;;
      esac
      local relay_cmd="ssh -W %h:%p -o BatchMode=yes -o ConnectTimeout=8 \
        -i ${HOME}/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11"
      ssh -o ConnectTimeout=10 -o BatchMode=yes \
          -o ProxyCommand="${relay_cmd}" \
          -i "${HOME}/.ssh/id_ed25519_dr_onprem" \
          "katar711@${relay_target}" "$@" 2>/dev/null
      ;;
    *)
      ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "$@" 2>/dev/null
      ;;
  esac
}

check_service() {
  local host="$1" service="$2" expected="$3" label="$4"
  local state
  state=$(ssh_cmd "$host" "sudo systemctl is-active ${service}" || echo "error")
  if [[ "$state" == "$expected" ]]; then
    pass "$label" "state=${state}"
  else
    fail "$label" "expected=${expected}, got=${state}"
  fi
}

check_pg_recovery() {
  local host="$1" expected="$2" label="$3"
  local val
  val=$(ssh_cmd "$host" "sudo -u postgres psql -qtAc 'SELECT pg_is_in_recovery();'" || echo "error")
  val=$(echo "$val" | tr -d '[:space:]')
  if [[ "$val" == "$expected" ]]; then
    pass "$label" "pg_is_in_recovery=${val}"
  else
    fail "$label" "expected=${expected}, got=${val}"
  fi
}

# ── step 1: SSH pre-check ─────────────────────────────────────────────────────
echo ""
log "Running SSH pre-check first..."
if "${SCRIPT_DIR}/ssh-precheck.sh" > /tmp/dr-preflight-ssh.txt 2>&1; then
  pass "SSH connectivity (all hosts)" "see /tmp/dr-preflight-ssh.txt"
else
  fail "SSH connectivity (all hosts)" "ssh-precheck.sh failed — check /tmp/dr-preflight-ssh.txt"
  echo ""
  log "PREFLIGHT ABORTED — SSH connectivity required before all other checks."
  exit 1
fi

echo ""
log "Checking steady-state for workflow: ${WORKFLOW}"
echo ""
printf "  %-42s  %-6s  %s\n" "CHECK" "RESULT" "DETAIL"
printf "  %-42s  %-6s  %s\n" "-----" "------" "------"
echo ""

# ── on-prem common checks (both workflows) ────────────────────────────────────
echo "  --- On-Prem Services ---"

check_service "pg-primary" "postgresql" "active" "pg-primary: postgresql active"
check_service "pg-primary" "keepalived" "active" "pg-primary: keepalived active"
check_service "pg-primary" "wg-quick@wg0" "active" "pg-primary: wireguard active"
check_pg_recovery "pg-primary" "f" "pg-primary: pg_is_in_recovery=f (PRIMARY)"

# Check pg-primary VIP ownership
vip_on_primary=$(ssh_cmd "pg-primary" "ip addr show eth0 | grep -c '10.0.96.10' || true")
if [[ "${vip_on_primary:-0}" -ge 1 ]]; then
  pass "pg-primary: VIP 10.0.96.10 held" "on eth0"
else
  fail "pg-primary: VIP 10.0.96.10 held" "VIP not found on eth0 — check keepalived state"
fi

echo ""
echo "  --- Replication: pg-primary → pg-standby ---"

# Check pg-standby replication
repl_standby=$(ssh_cmd "pg-primary" \
  "sudo -u postgres psql -qtAc \
   \"SELECT state FROM pg_stat_replication WHERE client_addr='10.0.96.14';\"" || echo "")
repl_standby=$(echo "$repl_standby" | tr -d '[:space:]')
if [[ "$repl_standby" == "streaming" ]]; then
  pass "pg-primary: pg-standby streaming" "state=streaming"
else
  fail "pg-primary: pg-standby streaming" "state='${repl_standby:-none}' (pg-standby may need pg_basebackup)"
fi

check_service "pg-standby" "postgresql" "active" "pg-standby: postgresql active"
check_pg_recovery "pg-standby" "t" "pg-standby: pg_is_in_recovery=t (replica)"

# On-prem app health — curl via pg-primary (WSL has no direct route to 10.0.96.x)
# Use -s without -f so we capture the body even on 503 (app up but DB unhealthy)
app_health=$(ssh_cmd "pg-primary" "curl -s --max-time 5 ${APP_HEALTH_URL_ONPREM}" 2>/dev/null || echo "error")
if echo "$app_health" | grep -q '"status":"ok"'; then
  recovery_val=$(echo "$app_health" | grep -o '"pg_is_in_recovery":[a-z]*' | cut -d: -f2)
  if [[ "$recovery_val" == "false" ]]; then
    pass "app-onprem: /health ok, recovery=false" "connected to primary"
  else
    warn "app-onprem: /health ok but recovery=true" "connected to standby (VIP issue?)"
  fi
else
  fail "app-onprem: /health reachable" "got: ${app_health:0:80}"
fi

# ── fullsite-specific checks ──────────────────────────────────────────────────
if [[ "$WORKFLOW" == "fullsite" ]]; then
  echo ""
  echo "  --- Replication: pg-primary → vm-pg-dr-fce (WireGuard) ---"

  # Replication to DR VM
  repl_drvm=$(ssh_cmd "pg-primary" \
    "sudo -u postgres psql -qtAc \
     \"SELECT state FROM pg_stat_replication WHERE client_addr='10.200.0.2';\"" || echo "")
  repl_drvm=$(echo "$repl_drvm" | tr -d '[:space:]')
  if [[ "$repl_drvm" == "streaming" ]]; then
    pass "pg-primary: vm-pg-dr-fce streaming" "state=streaming"
  else
    fail "pg-primary: vm-pg-dr-fce streaming" "state='${repl_drvm:-none}' — check WireGuard and DR VM pg"
  fi

  # DR VM replication lag
  lag_bytes=$(ssh_cmd "pg-primary" \
    "sudo -u postgres psql -qtAc \
     \"SELECT sent_lsn - replay_lsn FROM pg_stat_replication WHERE client_addr='10.200.0.2';\"" || echo "")
  lag_bytes=$(echo "$lag_bytes" | tr -d '[:space:]')
  if [[ -n "$lag_bytes" && "$lag_bytes" =~ ^[0-9]+$ ]]; then
    if [[ "$lag_bytes" -le "${MAX_REPLICATION_LAG_BYTES}" ]]; then
      pass "vm-pg-dr-fce: replication lag" "${lag_bytes} bytes (within threshold)"
    else
      warn "vm-pg-dr-fce: replication lag" "${lag_bytes} bytes (above ${MAX_REPLICATION_LAG_BYTES} threshold)"
    fi
  else
    fail "vm-pg-dr-fce: replication lag" "could not read lag (state=${repl_drvm:-unknown})"
  fi

  # WireGuard handshake age
  echo ""
  echo "  --- WireGuard Tunnel ---"
  wg_handshake=$(ssh_cmd "pg-primary" \
    "sudo wg show wg0 latest-handshakes 2>/dev/null | awk '{print \$2}'" || echo "0")
  wg_handshake=$(echo "$wg_handshake" | tr -d '[:space:]')
  if [[ -n "$wg_handshake" && "$wg_handshake" =~ ^[0-9]+$ && "$wg_handshake" -gt 0 ]]; then
    now_epoch=$(date +%s)
    age_seconds=$((now_epoch - wg_handshake))
    if [[ "$age_seconds" -le "${MAX_WG_HANDSHAKE_AGE_SECONDS}" ]]; then
      pass "WireGuard: handshake age" "${age_seconds}s ago (within 5 min threshold)"
    else
      warn "WireGuard: handshake age" "${age_seconds}s ago (above ${MAX_WG_HANDSHAKE_AGE_SECONDS}s threshold — may need restart)"
    fi
  else
    fail "WireGuard: handshake age" "no handshake data found"
  fi

  # DR VM PostgreSQL state
  echo ""
  echo "  --- Azure DR VM ---"
  check_service "vm-pg-dr-fce" "postgresql" "active" "vm-pg-dr-fce: postgresql active"
  check_pg_recovery "vm-pg-dr-fce" "t" "vm-pg-dr-fce: pg_is_in_recovery=t (replica)"

  # DR VM Docker image present
  image_check=$(ssh_cmd "vm-pg-dr-fce" \
    "sudo docker image ls clopr2-app --format '{{.Repository}}:{{.Tag}}' 2>/dev/null" || echo "")
  if echo "$image_check" | grep -q "clopr2-app"; then
    pass "vm-pg-dr-fce: clopr2-app image present" "${image_check}"
  else
    fail "vm-pg-dr-fce: clopr2-app image present" "image not found — run pre-test-day setup (section 4.2 of failover runbook)"
  fi
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
log "Preflight results: ${PASS_COUNT} PASS, ${WARN_COUNT} WARN, ${FAIL_COUNT} FAIL"
echo ""

if [[ ${FAIL_COUNT} -eq 0 && ${WARN_COUNT} -eq 0 ]]; then
  log "ALL CHECKS PASS — environment is in correct steady state."
  log "Safe to proceed with ${WORKFLOW} drill."
  echo ""
  exit 0
elif [[ ${FAIL_COUNT} -eq 0 && ${WARN_COUNT} -gt 0 ]]; then
  log "CHECKS PASS WITH WARNINGS — review warnings before proceeding."
  log "Warnings are advisory; they do not block the drill but should be investigated."
  echo ""
  exit 0
else
  log "PREFLIGHT FAILED — ${FAIL_COUNT} checks did not pass."
  log "Resolve all failures before starting the ${WORKFLOW} drill."
  echo ""
  exit 1
fi
