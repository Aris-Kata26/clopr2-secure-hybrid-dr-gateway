#!/usr/bin/env bash
# validate-registry.sh
# ====================
# Read-only validator for the resource_registry in dr-inventory.yml.
#
# Checks the resource_registry section for allocation conflicts that would
# cause silent failures when a second DR cluster is onboarded:
#   - Duplicate Keepalived VRIDs  (causes VRRP split-brain)
#   - Duplicate pgBackRest stanza names  (corrupts backup metadata)
#   - Duplicate static on-prem IPs  (network conflict)
#   - Duplicate or overlapping WireGuard CIDRs  (tunnel routing conflict)
#
# Usage:
#   bash scripts/dr/validate-registry.sh [--inventory <path>]
#
# Exit codes:
#   0  Registry is conflict-free
#   1  One or more conflicts detected
#   2  Dependency missing (yq)
#   3  Inventory file missing or unparseable
#
# Dependencies:
#   yq >= 4.x  (required — for YAML parsing)
#   python3    (optional — enables WireGuard CIDR overlap detection)
#              python3 is always available on ubuntu-latest (GitHub Actions)
#
# This script is read-only. It makes no changes to any file, Azure resource,
# Terraform state, or SSH target.
#
# Author: KATAR711 | Team: BCLC24 | 2026-03-20

set -euo pipefail

# ─── Defaults ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY_FILE="${REPO_ROOT}/dr-inventory.yml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory) INVENTORY_FILE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ─── Dependency checks ────────────────────────────────────────────────────────

if ! command -v yq &>/dev/null; then
  echo "ERROR: yq is not installed. See scripts/dr/classify-vm.sh for install instructions." >&2
  exit 2
fi

if [[ ! -f "${INVENTORY_FILE}" ]]; then
  echo "ERROR: Inventory file not found: ${INVENTORY_FILE}" >&2
  exit 3
fi

if ! yq '.' "${INVENTORY_FILE}" >/dev/null 2>&1; then
  echo "ERROR: ${INVENTORY_FILE} is not valid YAML." >&2
  exit 3
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

CONFLICTS=0
CHECKS_RUN=0

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*" >&2; CONFLICTS=$(( CONFLICTS + 1 )); }
skip() { echo "  SKIP  $*"; }

section() {
  echo ""
  echo "── $* ──"
}

# Emit sorted unique duplicates from a list of newline-separated values.
# Filters out "null" and empty lines (yq emits "null" for absent fields).
find_duplicates() {
  grep -v '^null$' | grep -v '^$' | sort | uniq -d
}

# ─── Guard: resource_registry presence ───────────────────────────────────────

REGISTRY_TYPE="$(yq '.resource_registry | type' "${INVENTORY_FILE}" 2>/dev/null || echo "null")"
if [[ "${REGISTRY_TYPE}" == "null" || "${REGISTRY_TYPE}" == "!!null" ]]; then
  echo ""
  echo "WARNING: No resource_registry section found in ${INVENTORY_FILE}."
  echo "         Skipping all registry checks. Add a resource_registry section"
  echo "         before onboarding a second DR cluster."
  echo ""
  exit 0
fi

# ─── Banner ───────────────────────────────────────────────────────────────────

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""
echo "CLOPR2 DR Registry — Conflict Validation"
echo "Manifest: ${INVENTORY_FILE}"
echo "Run at:   ${TIMESTAMP}"

# ─────────────────────────────────────────────────────────────────────────────
# Check 1 — Keepalived VRIDs
# ─────────────────────────────────────────────────────────────────────────────

section "Keepalived VRIDs"
CHECKS_RUN=$(( CHECKS_RUN + 1 ))

VRID_COUNT="$(yq '.resource_registry.keepalived_vrids | length' "${INVENTORY_FILE}" 2>/dev/null || echo "0")"

if [[ "${VRID_COUNT}" == "0" || "${VRID_COUNT}" == "null" ]]; then
  skip "No keepalived_vrids entries found."
else
  VRID_DUPS="$(yq '.resource_registry.keepalived_vrids[].vrid' "${INVENTORY_FILE}" | find_duplicates || true)"

  if [[ -n "${VRID_DUPS}" ]]; then
    fail "Duplicate Keepalived VRID(s) detected: ${VRID_DUPS}"
    echo "       Duplicate VRIDs cause VRRP split-brain. Each HA cluster requires a unique VRID." >&2
  else
    pass "No duplicate VRIDs. (${VRID_COUNT} entries checked)"
    # Print each allocation for visibility
    yq '.resource_registry.keepalived_vrids[] | "       VRID " + (.vrid | tostring) + " — " + .cluster + " [" + .status + "]"' \
      "${INVENTORY_FILE}" 2>/dev/null | sed 's/"//g' || true
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 2 — pgBackRest stanza names
# ─────────────────────────────────────────────────────────────────────────────

section "pgBackRest Stanza Names"
CHECKS_RUN=$(( CHECKS_RUN + 1 ))

STANZA_COUNT="$(yq '.resource_registry.pgbackrest_stanzas | length' "${INVENTORY_FILE}" 2>/dev/null || echo "0")"

if [[ "${STANZA_COUNT}" == "0" || "${STANZA_COUNT}" == "null" ]]; then
  skip "No pgbackrest_stanzas entries found."
else
  STANZA_DUPS="$(yq '.resource_registry.pgbackrest_stanzas[].stanza' "${INVENTORY_FILE}" | find_duplicates || true)"

  if [[ -n "${STANZA_DUPS}" ]]; then
    fail "Duplicate pgBackRest stanza name(s): ${STANZA_DUPS}"
    echo "       Duplicate stanzas corrupt backup metadata. Each cluster requires a unique stanza." >&2
  else
    pass "No duplicate stanza names. (${STANZA_COUNT} entries checked)"
    yq '.resource_registry.pgbackrest_stanzas[] | "       stanza=" + .stanza + " — " + .cluster + " [" + .status + "]"' \
      "${INVENTORY_FILE}" 2>/dev/null | sed 's/"//g' || true
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 3 — Static on-prem IP addresses
# ─────────────────────────────────────────────────────────────────────────────

section "Static On-Prem IP Addresses"
CHECKS_RUN=$(( CHECKS_RUN + 1 ))

IP_COUNT="$(yq '.resource_registry.static_ips_onprem | length' "${INVENTORY_FILE}" 2>/dev/null || echo "0")"

if [[ "${IP_COUNT}" == "0" || "${IP_COUNT}" == "null" ]]; then
  skip "No static_ips_onprem entries found."
else
  IP_DUPS="$(yq '.resource_registry.static_ips_onprem[].ip' "${INVENTORY_FILE}" | find_duplicates || true)"

  if [[ -n "${IP_DUPS}" ]]; then
    fail "Duplicate static IP(s) detected: ${IP_DUPS}"
    echo "       Duplicate IPs cause ARP conflicts. Each VM requires a unique static address." >&2
  else
    pass "No duplicate IPs. (${IP_COUNT} entries checked)"
    yq '.resource_registry.static_ips_onprem[] | "       " + .ip + " — " + .purpose + " [" + .status + "]"' \
      "${INVENTORY_FILE}" 2>/dev/null | sed 's/"//g' || true
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 4 — WireGuard subnet allocation (exact duplicates)
# ─────────────────────────────────────────────────────────────────────────────

section "WireGuard Subnets — Exact Duplicates"
CHECKS_RUN=$(( CHECKS_RUN + 1 ))

WG_COUNT="$(yq '.resource_registry.wireguard_subnets | length' "${INVENTORY_FILE}" 2>/dev/null || echo "0")"

if [[ "${WG_COUNT}" == "0" || "${WG_COUNT}" == "null" ]]; then
  skip "No wireguard_subnets entries found."
else
  WG_DUPS="$(yq '.resource_registry.wireguard_subnets[].cidr' "${INVENTORY_FILE}" | find_duplicates || true)"

  if [[ -n "${WG_DUPS}" ]]; then
    fail "Duplicate WireGuard CIDR(s) detected: ${WG_DUPS}"
    echo "       Duplicate CIDRs produce routing conflicts. Each tunnel pair requires a unique /30." >&2
  else
    pass "No exact duplicate WireGuard CIDRs. (${WG_COUNT} entries checked)"
    yq '.resource_registry.wireguard_subnets[] | "       " + .cidr + " [" + .status + "]"' \
      "${INVENTORY_FILE}" 2>/dev/null | sed 's/"//g' || true
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 5 — WireGuard subnet overlap (requires python3)
# ─────────────────────────────────────────────────────────────────────────────

section "WireGuard Subnets — CIDR Overlap"
CHECKS_RUN=$(( CHECKS_RUN + 1 ))

if [[ "${WG_COUNT}" == "0" || "${WG_COUNT}" == "null" ]]; then
  skip "No wireguard_subnets entries — skipping overlap check."
elif [[ "${WG_COUNT}" -lt 2 ]]; then
  skip "Only one WireGuard subnet — no overlap possible."
elif ! command -v python3 &>/dev/null; then
  skip "python3 not available — CIDR overlap check skipped (exact-duplicate check still ran above)."
  echo "       Install python3 to enable full overlap detection."
else
  # Feed all CIDRs to Python3 for overlap detection using the ipaddress stdlib module.
  # Exits 0 if no overlaps, 1 if any overlap is found.
  WG_CIDRS="$(yq '.resource_registry.wireguard_subnets[].cidr' "${INVENTORY_FILE}" | grep -v '^null$' | grep -v '^$' || true)"
  OVERLAP_RESULT="$(echo "${WG_CIDRS}" | python3 - <<'PYEOF' 2>&1 || true
import ipaddress, sys
lines = [l.strip() for l in sys.stdin.readlines() if l.strip()]
nets = []
for line in lines:
    try:
        nets.append(ipaddress.ip_network(line, strict=False))
    except ValueError as e:
        print(f"PARSE_ERROR: {line} — {e}", file=sys.stderr)
        sys.exit(2)
overlaps = []
for i in range(len(nets)):
    for j in range(i + 1, len(nets)):
        if nets[i].overlaps(nets[j]):
            overlaps.append(f"{nets[i]} overlaps {nets[j]}")
if overlaps:
    for o in overlaps:
        print(f"OVERLAP: {o}")
    sys.exit(1)
PYEOF
)"

  if echo "${OVERLAP_RESULT}" | grep -q '^OVERLAP:'; then
    fail "WireGuard CIDR overlap detected:"
    echo "${OVERLAP_RESULT}" | grep '^OVERLAP:' | sed 's/^/       /' >&2
    echo "       Overlapping CIDRs cause routing conflicts. Each /30 must be non-overlapping." >&2
  else
    pass "No WireGuard CIDR overlaps. (${WG_COUNT} subnets checked)"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Checks run:       ${CHECKS_RUN}"
echo "Conflicts found:  ${CONFLICTS}"
echo ""

if [[ ${CONFLICTS} -gt 0 ]]; then
  echo "RESULT: FAIL — ${CONFLICTS} conflict(s) detected." >&2
  echo "        Review dr-inventory.yml resource_registry and resolve before onboarding." >&2
  echo ""
  exit 1
fi

echo "RESULT: PASS — Registry is conflict-free."
echo "        Safe to onboard a new DR cluster provided all new allocations"
echo "        are added to this registry before provisioning."
echo ""
