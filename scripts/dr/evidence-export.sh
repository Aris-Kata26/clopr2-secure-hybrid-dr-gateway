#!/usr/bin/env bash
# evidence-export.sh — Batch-export DR evidence files from all hosts to the repo
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   After a DR drill, collect all /tmp evidence files from all involved hosts and
#   copy them into the appropriate docs/05-evidence/ subdirectory in the repo.
#   Prints a manifest of files collected and skipped. Read-only SCP pull from remotes.
#
# USAGE:
#   ./scripts/dr/evidence-export.sh <phase>
#
# PHASES:
#   onprem-ha-failover    On-prem HA failover drill evidence
#   onprem-ha-fallback    On-prem HA fallback drill evidence
#   fullsite-failover     Full-site failover to Azure evidence
#   fullsite-fallback     Full-site failback to on-prem evidence
#
# OPTIONS:
#   --dry-run    Print what would be collected without copying files
#   --dest <dir> Override destination directory (default: auto-detected from repo root)
#
# EXIT CODES:
#   0  All files collected (or nothing to collect)
#   1  Some files could not be collected (see warnings)
#   2  Usage error

set -euo pipefail

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_PREFIX="[evidence-export ${TIMESTAMP}]"
PHASE=""
DRY_RUN=false
CUSTOM_DEST=""

# Detect repo root (two levels up from scripts/dr/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    onprem-ha-failover|onprem-ha-fallback|fullsite-failover|fullsite-fallback)
      PHASE="$1" ;;
    --dry-run)   DRY_RUN=true ;;
    --dest)      shift; CUSTOM_DEST="$1" ;;
    --help|-h)
      sed -n '/^# PURPOSE:/,/^[^#]/p' "$0" | head -30
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 <phase> [--dry-run] [--dest <dir>]" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$PHASE" ]]; then
  echo "Error: phase is required" >&2
  echo "Usage: $0 <onprem-ha-failover|onprem-ha-fallback|fullsite-failover|fullsite-fallback>" >&2
  exit 2
fi

# ── destination directory ─────────────────────────────────────────────────────
case "$PHASE" in
  onprem-ha-failover|onprem-ha-fallback)
    EVIDENCE_SUBDIR="dr-validation"
    FILE_PREFIX="fs-ha"
    ;;
  fullsite-failover)
    EVIDENCE_SUBDIR="full-site-dr-validation"
    FILE_PREFIX="fsdr"
    ;;
  fullsite-fallback)
    EVIDENCE_SUBDIR="full-site-dr-validation"
    FILE_PREFIX="fsdb"
    ;;
esac

if [[ -n "$CUSTOM_DEST" ]]; then
  DEST_DIR="$CUSTOM_DEST"
else
  DEST_DIR="${REPO_ROOT}/docs/05-evidence/${EVIDENCE_SUBDIR}"
fi

# ── helpers ───────────────────────────────────────────────────────────────────
log()      { echo "${LOG_PREFIX} $*"; }
collected(){ printf "  \033[32m[+]\033[0m  %-45s  <- %s:%s\n" "$1" "$2" "$3"; }
missing()  { printf "  \033[33m[-]\033[0m  %-45s  not found on %s\n" "$1" "$2"; }
skipped()  { printf "  \033[90m[~]\033[0m  %-45s  --dry-run\n" "$1"; }

_relay_host_target() {
  # Resolve relay-required hosts to their IP for ProxyCommand routing
  case "$1" in
    pg-standby) echo "10.0.96.14" ;;
    app-onprem) echo "10.0.96.13" ;;
    *)          echo "" ;;
  esac
}

_relay_proxy_cmd() {
  echo "ssh -W %h:%p -o BatchMode=yes -o ConnectTimeout=8 -i ~/.ssh/id_ed25519_dr_onprem -J pve katar711@10.0.96.11"
}

scp_file() {
  local host="$1" remote_path="$2" local_dest="$3"
  local relay_target
  relay_target=$(_relay_host_target "$host")
  if [[ -n "$relay_target" ]]; then
    scp -q -o ConnectTimeout=10 -o BatchMode=yes \
        -o "ProxyCommand=$(_relay_proxy_cmd)" \
        -i ~/.ssh/id_ed25519_dr_onprem \
        "katar711@${relay_target}:${remote_path}" "${local_dest}" 2>/dev/null
  else
    scp -q -o ConnectTimeout=10 -o BatchMode=yes \
        "${host}:${remote_path}" "${local_dest}" 2>/dev/null
  fi
}

collect() {
  local host="$1"
  local remote_file="$2"
  local dest_name="${3:-$(basename "$remote_file")}"
  local remote_path="/tmp/${remote_file}"
  local local_path="${DEST_DIR}/${dest_name}"
  local relay_target
  relay_target=$(_relay_host_target "$host")

  # Check if file exists on remote
  local ssh_ok=0
  if [[ -n "$relay_target" ]]; then
    ssh -o ConnectTimeout=10 -o BatchMode=yes \
        -o "ProxyCommand=$(_relay_proxy_cmd)" \
        -i ~/.ssh/id_ed25519_dr_onprem \
        "katar711@${relay_target}" "test -f ${remote_path}" 2>/dev/null || ssh_ok=1
  else
    ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" \
        "test -f ${remote_path}" 2>/dev/null || ssh_ok=1
  fi
  if [[ $ssh_ok -ne 0 ]]; then
    missing "$dest_name" "$host"
    MISSING_COUNT=$((MISSING_COUNT+1))
    return
  fi

  if $DRY_RUN; then
    skipped "$dest_name"
    DRY_COUNT=$((DRY_COUNT+1))
    return
  fi

  if scp_file "$host" "$remote_path" "$local_path"; then
    collected "$dest_name" "$host" "$remote_path"
    COLLECTED_COUNT=$((COLLECTED_COUNT+1))
  else
    missing "$dest_name" "$host (scp failed)"
    MISSING_COUNT=$((MISSING_COUNT+1))
  fi
}

collect_local() {
  local local_src="$1" dest_name="${2:-$(basename "$1")}"
  local local_path="${DEST_DIR}/${dest_name}"

  if [[ ! -f "$local_src" ]]; then
    missing "$dest_name" "local:${local_src}"
    MISSING_COUNT=$((MISSING_COUNT+1))
    return
  fi

  if $DRY_RUN; then
    skipped "$dest_name"
    DRY_COUNT=$((DRY_COUNT+1))
    return
  fi

  cp "$local_src" "$local_path"
  collected "$dest_name" "local" "$local_src"
  COLLECTED_COUNT=$((COLLECTED_COUNT+1))
}

# ── initialise counters and destination ──────────────────────────────────────
COLLECTED_COUNT=0
MISSING_COUNT=0
DRY_COUNT=0

echo ""
log "Phase:       ${PHASE}"
log "Destination: ${DEST_DIR}"
if $DRY_RUN; then
  log "Mode:        DRY RUN — no files will be copied"
fi
echo ""

if ! $DRY_RUN; then
  mkdir -p "${DEST_DIR}"
fi

printf "  %-5s  %-45s  %s\n" "ACT" "FILE" "SOURCE"
printf "  %-5s  %-45s  %s\n" "---" "----" "------"
echo ""

# ── phase-specific file collection ───────────────────────────────────────────
case "$PHASE" in

  onprem-ha-failover)
    # All evidence files are written locally via ssh | tee /tmp/... on the operator host
    echo "  --- Pre-checks ---"
    collect_local          "/tmp/fs-ha-precheck-primary.txt"
    collect_local          "/tmp/fs-ha-precheck-app-health.txt"
    collect_local          "/tmp/fs-ha-start-timestamp.txt"

    echo ""
    echo "  --- Failover execution ---"
    collect_local          "/tmp/fs-ha-keepalived-stopped.txt"
    collect_local          "/tmp/fs-ha-vip-check-primary.txt"
    collect_local          "/tmp/fs-ha-vip-check-standby.txt"
    collect_local          "/tmp/fs-ha-app-health-after.txt"
    collect_local          "/tmp/fs-ha-pg-stat-replication.txt"

    echo ""
    echo "  --- RTO summary ---"
    collect_local          "/tmp/fs-ha-rto-summary.txt"
    ;;

  onprem-ha-fallback)
    # All evidence files are written locally via ssh | tee /tmp/... on the operator host
    echo "  --- Fallback execution ---"
    collect_local          "/tmp/fs-ha-fb-start-timestamp.txt"
    collect_local          "/tmp/fs-ha-fb-services-started.txt"
    collect_local          "/tmp/fs-ha-fb-vip-returned.txt"
    collect_local          "/tmp/fs-ha-fb-replication-resumed.txt"
    collect_local          "/tmp/fs-ha-fb-app-health.txt"
    collect_local          "/tmp/fs-ha-fb-rto-summary.txt"
    ;;

  fullsite-failover)
    # All files written locally via ssh_run ... | tee /tmp/fsdr-*.txt in fullsite-failover.sh
    echo "  --- Pre-checks ---"
    collect_local          "/tmp/fsdr-start-timestamp.txt"
    collect_local          "/tmp/fsdr-precheck-primary.txt"
    collect_local          "/tmp/fsdr-precheck-app-health.txt"
    collect_local          "/tmp/fsdr-precheck-drvm.txt"

    echo ""
    echo "  --- Failover execution ---"
    collect_local          "/tmp/fsdr-app-stopped.txt"
    collect_local          "/tmp/fsdr-final-lsn.txt"
    collect_local          "/tmp/fsdr-primary-stopped.txt"
    collect_local          "/tmp/fsdr-replay-wait.txt"
    collect_local          "/tmp/fsdr-promoted.txt"
    collect_local          "/tmp/fsdr-write-test.txt"
    collect_local          "/tmp/fsdr-app-health-drvm.txt"
    collect_local          "/tmp/fsdr-app-health-local.txt"
    collect_local          "/tmp/fsdr-rto-summary.txt"
    collect_local          "/tmp/fsdr-post-failover-snapshot.txt"
    ;;

  fullsite-fallback)
    # All files written locally via ssh_run ... | tee /tmp/fsdb-*.txt in fullsite-fallback.sh
    echo "  --- Pre-checks ---"
    collect_local          "/tmp/fsdb-precheck.txt"
    collect_local          "/tmp/fsdb-start-timestamp.txt"

    echo ""
    echo "  --- Failback execution ---"
    collect_local          "/tmp/fsdb-azure-app-stopped.txt"
    collect_local          "/tmp/fsdb-drvm-readonly.txt"
    collect_local          "/tmp/fsdb-pg-basebackup.txt"
    collect_local          "/tmp/fsdb-primary-standby-start.txt"
    collect_local          "/tmp/fsdb-drvm-replication.txt"
    collect_local          "/tmp/fsdb-catchup-wait.txt"
    collect_local          "/tmp/fsdb-primary-promoted.txt"
    collect_local          "/tmp/fsdb-drvm-rebuild.txt"
    collect_local          "/tmp/fsdb-replication-restored.txt"
    collect_local          "/tmp/fsdb-vip-returned.txt"
    collect_local          "/tmp/fsdb-app-started.txt"
    collect_local          "/tmp/fsdb-app-health.txt"
    collect_local          "/tmp/fsdb-rto-summary.txt"
    collect_local          "/tmp/fsdb-post-failback-snapshot.txt"
    collect_local          "/tmp/fsdb-final-app-health.txt"
    ;;
esac

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
log "Collection summary:"
if $DRY_RUN; then
  log "  DRY RUN: ${DRY_COUNT} file(s) would be collected"
else
  log "  Collected:  ${COLLECTED_COUNT} file(s) -> ${DEST_DIR}"
  log "  Not found:  ${MISSING_COUNT} file(s)"
fi
echo ""

if [[ ${MISSING_COUNT} -gt 0 ]]; then
  log "WARNING: ${MISSING_COUNT} evidence file(s) not found."
  log "  Possible causes: drill step not yet executed, file written to different path, host unreachable."
  log "  Collect missing files manually before committing evidence."
  echo ""
  exit 1
else
  if ! $DRY_RUN; then
    log "All evidence collected. Next steps:"
    log "  1. Review files in ${DEST_DIR}"
    log "  2. Update evidence checklist"
    log "  3. git add + git commit"
  fi
  echo ""
  exit 0
fi
