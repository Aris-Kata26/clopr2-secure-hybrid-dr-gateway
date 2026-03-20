#!/usr/bin/env bash
# classify-vm.sh
# ==============
# Read-only DR inventory classifier for CLOPR2.
#
# Reads dr-inventory.yml from the repository root and prints a classification
# report showing each VM's DR status. No side effects, no Azure calls, no
# Terraform apply, no Ansible execution.
#
# Usage:
#   bash scripts/dr/classify-vm.sh [--inventory <path>] [--json] [--vm <name>]
#
# Options:
#   --inventory <path>   Path to dr-inventory.yml (default: repo root)
#   --json               Output as JSON instead of table
#   --vm <name>          Show classification for one VM only
#   --help               Show this help
#
# Exit codes:
#   0  Classification completed successfully
#   1  YAML parse error or missing inventory file
#   2  Dependency missing (yq not found)
#   3  Schema version unsupported
#
# Dependencies:
#   yq >= 4.x (https://github.com/mikefarah/yq)
#   Install: brew install yq  /  snap install yq  /  apt install yq
#   Verify:  yq --version
#
# Status values:
#   MANAGED              VM is DR-managed with an active Azure-side path
#   EXCLUDED             VM is explicitly not DR-managed
#   PROTECTED_BY_PRIMARY VM is covered by another VM's DR path (db-standby)
#   BACKUP_ONLY          VM is DR-managed with backup-level coverage only
#   UNKNOWN_ROLE         Role not recognised — treated as excluded
#
# Author: KATAR711 | Team: BCLC24 | 2026-03-20

set -euo pipefail

# ─── Defaults ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY_FILE="${REPO_ROOT}/dr-inventory.yml"
OUTPUT_JSON=false
FILTER_VM=""

# ─── Argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      INVENTORY_FILE="$2"
      shift 2
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --vm)
      FILTER_VM="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '2,/^# Author/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      echo "Usage: bash classify-vm.sh [--inventory <path>] [--json] [--vm <name>]" >&2
      exit 1
      ;;
  esac
done

# ─── Dependency check ─────────────────────────────────────────────────────────

if ! command -v yq &>/dev/null; then
  echo "ERROR: yq is not installed." >&2
  echo "" >&2
  echo "yq is required to parse dr-inventory.yml." >&2
  echo "Install options:" >&2
  echo "  brew install yq                                     (macOS)" >&2
  echo "  snap install yq                                     (Ubuntu/snap)" >&2
  echo "  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq" >&2
  echo "  GCP Cloud Shell: yq is pre-installed" >&2
  echo "  WSL Ubuntu:      sudo apt install yq (if available) or use wget above" >&2
  exit 2
fi

# ─── Inventory validation ─────────────────────────────────────────────────────

if [[ ! -f "${INVENTORY_FILE}" ]]; then
  echo "ERROR: Inventory file not found: ${INVENTORY_FILE}" >&2
  exit 1
fi

# Validate YAML is parseable — yq will exit non-zero if malformed
if ! yq '.' "${INVENTORY_FILE}" >/dev/null 2>&1; then
  echo "ERROR: ${INVENTORY_FILE} is not valid YAML." >&2
  exit 1
fi

# Check schema version
SCHEMA_VERSION="$(yq '.schema_version' "${INVENTORY_FILE}" 2>/dev/null || echo "null")"
if [[ "${SCHEMA_VERSION}" == "null" || "${SCHEMA_VERSION}" == "" ]]; then
  echo "WARNING: No schema_version found in inventory. Proceeding with best-effort parsing." >&2
elif [[ "${SCHEMA_VERSION}" != "1.0" ]]; then
  echo "ERROR: Unsupported schema_version: ${SCHEMA_VERSION}. This classifier supports 1.0 only." >&2
  exit 3
fi

# ─── Classification logic ─────────────────────────────────────────────────────

# Map role + dr_managed + dr_mode to a STATUS string.
# Management role is always EXCLUDED regardless of dr_managed value.
classify_vm() {
  local name="$1"
  local role="$2"
  local dr_managed="$3"
  local dr_mode="$4"

  case "${role}" in
    management)
      echo "EXCLUDED"
      ;;
    db-standby)
      echo "PROTECTED_BY_PRIMARY"
      ;;
    db-primary)
      if [[ "${dr_managed}" == "true" ]]; then
        echo "MANAGED"
      else
        echo "EXCLUDED"
      fi
      ;;
    app)
      if [[ "${dr_managed}" == "true" ]]; then
        case "${dr_mode}" in
          live-standby)     echo "MANAGED" ;;
          backup-only)      echo "BACKUP_ONLY" ;;
          *)                echo "BACKUP_ONLY" ;;
        esac
      else
        echo "EXCLUDED"
      fi
      ;;
    utility)
      if [[ "${dr_managed}" == "true" ]]; then
        echo "BACKUP_ONLY"
      else
        echo "EXCLUDED"
      fi
      ;;
    ""|null)
      echo "UNKNOWN_ROLE"
      ;;
    *)
      echo "UNKNOWN_ROLE"
      ;;
  esac
}

# ─── Collect VM data ──────────────────────────────────────────────────────────

VM_COUNT="$(yq '.vms | length' "${INVENTORY_FILE}")"

# ─── JSON output ──────────────────────────────────────────────────────────────

if [[ "${OUTPUT_JSON}" == "true" ]]; then
  echo "["
  first=true
  for i in $(seq 0 $((VM_COUNT - 1))); do
    name="$(yq ".vms[${i}].name" "${INVENTORY_FILE}")"
    [[ -n "${FILTER_VM}" && "${name}" != "${FILTER_VM}" ]] && continue

    role="$(yq ".vms[${i}].role" "${INVENTORY_FILE}")"
    dr_managed="$(yq ".vms[${i}].dr_managed" "${INVENTORY_FILE}")"
    dr_mode="$(yq ".vms[${i}].dr_mode" "${INVENTORY_FILE}")"
    ip="$(yq ".vms[${i}].ip" "${INVENTORY_FILE}")"
    azure_dr_vm="$(yq ".vms[${i}].azure_dr_vm" "${INVENTORY_FILE}")"
    status="$(classify_vm "${name}" "${role}" "${dr_managed}" "${dr_mode}")"

    [[ "${first}" == "true" ]] && first=false || echo ","
    printf '  {"name":"%s","role":"%s","dr_managed":%s,"dr_mode":"%s","ip":"%s","azure_dr_vm":"%s","status":"%s"}' \
      "${name}" "${role}" "${dr_managed}" "${dr_mode}" "${ip}" \
      "$([ "${azure_dr_vm}" = "null" ] && echo "" || echo "${azure_dr_vm}")" \
      "${status}"
  done
  echo ""
  echo "]"
  exit 0
fi

# ─── Table output ─────────────────────────────────────────────────────────────

# shellcheck disable=SC2059  # HEADER_FMT and ROW_FMT are intentional format strings
HEADER_FMT="%-15s  %-14s  %-10s  %-20s  %-10s  %-20s  %s"
ROW_FMT="%-15s  %-14s  %-10s  %-20s  %-10s  %-20s  %s"

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

echo ""
echo "CLOPR2 DR Inventory Classification"
echo "Manifest: ${INVENTORY_FILE}"
echo "Run at:   ${TIMESTAMP}"
echo ""
printf "${HEADER_FMT}\n" "NAME" "ROLE" "DR_MANAGED" "DR_MODE" "IP" "AZURE_DR_VM" "STATUS"
printf '%s\n' "$(printf '─%.0s' {1..100})"

managed_count=0
excluded_count=0
backup_count=0
protected_count=0
unknown_count=0

for i in $(seq 0 $((VM_COUNT - 1))); do
  name="$(yq ".vms[${i}].name" "${INVENTORY_FILE}")"
  [[ -n "${FILTER_VM}" && "${name}" != "${FILTER_VM}" ]] && continue

  role="$(yq ".vms[${i}].role" "${INVENTORY_FILE}")"
  dr_managed="$(yq ".vms[${i}].dr_managed" "${INVENTORY_FILE}")"
  dr_mode="$(yq ".vms[${i}].dr_mode" "${INVENTORY_FILE}")"
  ip="$(yq ".vms[${i}].ip" "${INVENTORY_FILE}")"
  azure_dr_vm="$(yq ".vms[${i}].azure_dr_vm" "${INVENTORY_FILE}")"
  status="$(classify_vm "${name}" "${role}" "${dr_managed}" "${dr_mode}")"

  display_azure="$([ "${azure_dr_vm}" = "null" ] && echo "-" || echo "${azure_dr_vm}")"

  printf "${ROW_FMT}\n" \
    "${name}" "${role}" "${dr_managed}" "${dr_mode}" "${ip}" \
    "${display_azure}" "${status}"

  case "${status}" in
    MANAGED)              managed_count=$(( managed_count + 1 )) ;;
    EXCLUDED)             excluded_count=$(( excluded_count + 1 )) ;;
    BACKUP_ONLY)          backup_count=$(( backup_count + 1 )) ;;
    PROTECTED_BY_PRIMARY) protected_count=$(( protected_count + 1 )) ;;
    UNKNOWN_ROLE)         unknown_count=$(( unknown_count + 1 )) ;;
  esac
done

printf '%s\n' "$(printf '─%.0s' {1..100})"
echo ""
echo "Summary:"
echo "  MANAGED              : ${managed_count}"
echo "  BACKUP_ONLY          : ${backup_count}"
echo "  PROTECTED_BY_PRIMARY : ${protected_count}"
echo "  EXCLUDED             : ${excluded_count}"
echo "  UNKNOWN_ROLE         : ${unknown_count}"
echo ""

if [[ ${unknown_count} -gt 0 ]]; then
  echo "ERROR: ${unknown_count} VM(s) have UNKNOWN_ROLE — review dr-inventory.yml" >&2
  echo "       See docs/07-dr-onboarding/01-role-taxonomy.md for valid roles." >&2
  echo ""
  exit 1
fi

echo "Policy: docs/07-dr-onboarding/00-policy-model.md"
echo "Roles:  docs/07-dr-onboarding/01-role-taxonomy.md"
echo "ADR:    docs/07-dr-onboarding/02-adr-manifest-model.md"
echo ""
