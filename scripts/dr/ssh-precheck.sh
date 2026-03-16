#!/usr/bin/env bash
# ssh-precheck.sh — Mandatory SSH ControlMaster pre-check for DR operations
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   Clear stale SSH ControlMaster sockets and verify connectivity to all DR hosts.
#   Must be run before any DR operation. A stale PVE mux socket silently hangs all
#   subsequent SSH commands, adding 45+ min to RTO (confirmed in S4-09 execution).
#
# USAGE:
#   ./scripts/dr/ssh-precheck.sh [--verbose]
#
# OPTIONS:
#   --verbose    Print full SSH output for each host test
#
# EXIT CODES:
#   0  All hosts reachable
#   1  One or more hosts unreachable
#   2  SSH config missing required host aliases
#
# HOSTS TESTED:
#   pve           10.0.10.71   Proxmox hypervisor (direct)
#   pg-primary    10.0.96.11   PostgreSQL primary (via pve ProxyJump)
#   pg-standby    10.0.96.14   PostgreSQL standby (via pg-primary relay)
#   app-onprem    10.0.96.13   FastAPI app VM (via pg-primary relay)
#   vm-pg-dr-fce  10.200.0.2   Azure DR VM (via WireGuard through pg-primary)

set -euo pipefail

# ── configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_PREFIX="[ssh-precheck ${TIMESTAMP}]"
VERBOSE=false
SSH_TIMEOUT=10
SSH_CTL_DIR="${HOME}/.ssh/ctl"

# Hosts to test (alias as defined in ~/.ssh/config)
DIRECT_HOSTS=("pve" "pg-primary" "vm-pg-dr-fce")

# Relay hosts (SSH via pg-primary ProxyCommand — PVE cannot TCP-forward to these)
RELAY_HOSTS=("pg-standby" "app-onprem")

# ── argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=true ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -30
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--verbose]" >&2
      exit 1
      ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────────────
log()  { echo "${LOG_PREFIX} $*"; }
ok()   { printf "  %-20s  \033[32mPASS\033[0m  %s\n" "$1" "$2"; }
fail() { printf "  %-20s  \033[31mFAIL\033[0m  %s\n" "$1" "$2"; }
warn() { printf "  %-20s  \033[33mWARN\033[0m  %s\n" "$1" "$2"; }

ssh_test() {
  local host="$1"
  local out
  if $VERBOSE; then
    out=$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
              -o StrictHostKeyChecking=accept-new \
              "$host" 'echo "OK:$(hostname)"' 2>&1)
  else
    out=$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
              -o StrictHostKeyChecking=accept-new \
              "$host" 'echo "OK:$(hostname)"' 2>/dev/null)
  fi
  echo "$out"
}

# ssh_test_relay: test relay hosts (pg-standby, app-onprem) via the pg-primary
# ProxyCommand. The SSH config uses ProxyJump pve for these hosts but PVE cannot
# TCP-forward to 10.0.96.14 or 10.0.96.13. The proven path is:
#   WSL --(ProxyJump pve)--> pg-primary (10.0.96.11) --(forward -W)--> target
ssh_test_relay() {
  local host="$1"
  local out
  local relay_cmd="ssh -W %h:%p -o BatchMode=yes -o ConnectTimeout=8 \
    -i ${HOME}/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11"
  if $VERBOSE; then
    out=$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
              -o StrictHostKeyChecking=accept-new \
              -o ProxyCommand="${relay_cmd}" \
              -i "${HOME}/.ssh/id_ed25519_dr_onprem" \
              "katar711@${host}" 'echo "OK:$(hostname)"' 2>&1)
  else
    out=$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
              -o StrictHostKeyChecking=accept-new \
              -o ProxyCommand="${relay_cmd}" \
              -i "${HOME}/.ssh/id_ed25519_dr_onprem" \
              "katar711@${host}" 'echo "OK:$(hostname)"' 2>/dev/null)
  fi
  echo "$out"
}

# ── step 0: clear ControlMaster sockets ──────────────────────────────────────
log "Clearing stale SSH ControlMaster sockets..."
if [[ -d "${SSH_CTL_DIR}" ]]; then
  for sock in "${SSH_CTL_DIR}"/*; do
    [[ -S "$sock" ]] || continue
    sockname=$(basename "$sock")
    rm -f "$sock"
    log "  Removed socket: ${sockname}"
  done
else
  log "  No ControlMaster socket directory found at ${SSH_CTL_DIR} (nothing to clear)"
fi

echo ""
log "Testing SSH connectivity to all DR hosts..."
echo ""
printf "  %-20s  %-6s  %s\n" "HOST" "RESULT" "DETAIL"
printf "  %-20s  %-6s  %s\n" "----" "------" "------"

PASS_COUNT=0
FAIL_COUNT=0
FAIL_HOSTS=()

# ── test direct hosts ─────────────────────────────────────────────────────────
for host in "${DIRECT_HOSTS[@]}"; do
  result=$(ssh_test "$host" || true)
  if echo "$result" | grep -q "^OK:"; then
    hostname_out=$(echo "$result" | grep "^OK:" | cut -d: -f2)
    ok "$host" "hostname=${hostname_out}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    if $VERBOSE; then
      fail "$host" "${result:-timeout or connection refused}"
    else
      fail "$host" "unreachable (run with --verbose for details)"
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_HOSTS+=("$host")
  fi
done

# ── test relay hosts (via pg-primary ProxyCommand relay) ─────────────────────
# Only attempt relay hosts if pg-primary is reachable.
# Uses ssh_test_relay which bypasses the SSH config's broken ProxyJump pve and
# instead routes through pg-primary (PVE cannot TCP-forward to 10.0.96.14/.13).
if echo " ${FAIL_HOSTS[*]:-} " | grep -q " pg-primary "; then
  for host in "${RELAY_HOSTS[@]}"; do
    warn "$host" "skipped — pg-primary unreachable (required relay)"
  done
else
  for host in "${RELAY_HOSTS[@]}"; do
    # Resolve alias to IP for ProxyCommand routing
    case "$host" in
      pg-standby) relay_target="10.0.96.14" ;;
      app-onprem)  relay_target="10.0.96.13" ;;
      *)           relay_target="$host" ;;
    esac
    result=$(ssh_test_relay "$relay_target" || true)
    if echo "$result" | grep -q "^OK:"; then
      hostname_out=$(echo "$result" | grep "^OK:" | cut -d: -f2)
      ok "$host" "hostname=${hostname_out} (via pg-primary relay)"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      if $VERBOSE; then
        fail "$host" "${result:-timeout or connection refused}"
      else
        fail "$host" "unreachable via pg-primary relay (run with --verbose for details)"
      fi
      FAIL_COUNT=$((FAIL_COUNT + 1))
      FAIL_HOSTS+=("$host")
    fi
  done
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
log "Results: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"
echo ""

# Store final exit code before printing — avoids set -e interfering in the else block
FINAL_EXIT=0
[[ ${FAIL_COUNT} -eq 0 ]] || FINAL_EXIT=1

if [[ ${FINAL_EXIT} -eq 0 ]]; then
  log "ALL HOSTS REACHABLE — safe to proceed with DR operation."
  echo ""
else
  log "CONNECTIVITY FAILURES DETECTED — DO NOT PROCEED with DR operation."
  log "Failed hosts: ${FAIL_HOSTS[*]:-unknown}"
  echo ""
  log "Troubleshooting hints:"
  if printf '%s\n' "${FAIL_HOSTS[@]:-}" | grep -q "^pve$"; then
    log "  - pve unreachable: check WSL network, VPN, or SSH config (Host pve in ~/.ssh/config)"
  fi
  if printf '%s\n' "${FAIL_HOSTS[@]:-}" | grep -q "^pg-primary$"; then
    log "  - pg-primary unreachable: check pve connectivity first, then ProxyJump config"
  fi
  if printf '%s\n' "${FAIL_HOSTS[@]:-}" | grep -q "^vm-pg-dr-fce$"; then
    log "  - vm-pg-dr-fce unreachable: check WireGuard on pg-primary: ssh pg-primary 'sudo wg show'"
    log "    Restart WireGuard: ssh pg-primary 'sudo systemctl restart wg-quick@wg0'"
  fi
  if printf '%s\n' "${FAIL_HOSTS[@]:-}" | grep -qE "^(pg-standby|app-onprem)$"; then
    log "  - Relay hosts unreachable via pg-primary: check host SSH daemon and pg-primary routing"
    log "    Test manually: ssh -o ProxyCommand=\"ssh -W %h:%p -J pve katar711@10.0.96.11\" katar711@<ip>"
  fi
  echo ""
fi

exit ${FINAL_EXIT}
