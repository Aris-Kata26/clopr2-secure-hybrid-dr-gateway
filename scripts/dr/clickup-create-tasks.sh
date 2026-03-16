#!/usr/bin/env bash
# clickup-create-tasks.sh — Create S5-01 automation sprint tasks in ClickUp
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   Creates the DR automation sprint tasks recommended by dr-automation-audit.md.
#   All tasks are linked as follow-on work from S4-09 (task 86c8u3pwy).
#
# USAGE:
#   CLICKUP_TOKEN=your_token LIST_ID=your_list_id ./scripts/dr/clickup-create-tasks.sh
#
# FIND YOUR LIST ID:
#   In ClickUp, open the list where DR tasks live, look at the URL:
#   https://app.clickup.com/XXXXXXXX/v/l/YYYYYYYYY  <- LIST_ID is YYYYYYYYY
#
# FIND YOUR TOKEN:
#   ClickUp Settings -> Apps -> API Token
#
# EXIT CODES:
#   0  All tasks created
#   1  API call failed

set -euo pipefail

CLICKUP_TOKEN="${CLICKUP_TOKEN:-}"
LIST_ID="${LIST_ID:-}"

if [[ -z "$CLICKUP_TOKEN" ]]; then
  echo "Error: CLICKUP_TOKEN is required" >&2
  echo "Usage: CLICKUP_TOKEN=<token> LIST_ID=<list_id> $0" >&2
  exit 1
fi

if [[ -z "$LIST_ID" ]]; then
  echo "Error: LIST_ID is required" >&2
  echo "Usage: CLICKUP_TOKEN=<token> LIST_ID=<list_id> $0" >&2
  exit 1
fi

PARENT_TASK_ID="86c8u3pwy"  # S4-09 — the completed DR validation task
API_BASE="https://api.clickup.com/api/v2"

create_task() {
  local name="$1"
  local description="$2"
  local sprint="$3"
  local priority="$4"   # 1=urgent 2=high 3=normal 4=low

  echo "Creating task: ${name}..."
  response=$(curl -sf -X POST \
    "${API_BASE}/list/${LIST_ID}/task" \
    -H "Authorization: ${CLICKUP_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${name}\",
      \"description\": \"${description}\",
      \"priority\": ${priority},
      \"tags\": [\"automation\", \"dr\", \"${sprint}\"],
      \"custom_fields\": []
    }" 2>&1)

  if echo "$response" | grep -q '"id"'; then
    task_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "unknown")
    echo "  Created: ${task_id} — ${name}"
  else
    echo "  FAILED to create: ${name}"
    echo "  Response: ${response:0:200}"
    return 1
  fi
}

echo ""
echo "Creating S5-01 DR Automation tasks in ClickUp..."
echo "List ID: ${LIST_ID}"
echo "Parent task (S4-09): ${PARENT_TASK_ID}"
echo ""

# ── S5-01 tasks (Phase 2 safe scripts) ───────────────────────────────────────
create_task \
  "[S5-01] Build ssh-precheck.sh — mandatory SSH ControlMaster pre-check" \
  "Implement scripts/dr/ssh-precheck.sh\n\nClears stale ControlMaster sockets and tests connectivity to all DR hosts (pve, pg-primary, pg-standby, app-onprem, vm-pg-dr-fce).\n\nPriority: CRITICAL — eliminates the 45-min RTO failure mode confirmed in S4-09.\n\nReference: docs/03-operations/dr-automation-audit.md\nScript: already scaffolded at scripts/dr/ssh-precheck.sh\nBlocking: fullsite-failover RTO reduction to <5 min" \
  "S5-01" "1"

create_task \
  "[S5-01] Build dr-preflight.sh — pre-drill readiness check" \
  "Implement scripts/dr/dr-preflight.sh\n\nValidates full steady-state before any DR drill: replication health, service states, VIP location, WireGuard handshake age, app /health. Read-only, no state changes.\n\nWorkflows: onprem-ha, fullsite\nReference: docs/03-operations/dr-automation-audit.md\nScript: already scaffolded at scripts/dr/dr-preflight.sh" \
  "S5-01" "2"

create_task \
  "[S5-01] Build evidence-export.sh — batch evidence collection" \
  "Implement scripts/dr/evidence-export.sh\n\nBatch-collects /tmp evidence files from all hosts after a drill and copies to docs/05-evidence/. Supports: onprem-ha-failover, onprem-ha-fallback, fullsite-failover, fullsite-failback.\n\nEliminates manual SCP steps. Includes --dry-run mode.\nReference: docs/03-operations/dr-automation-audit.md\nScript: already scaffolded at scripts/dr/evidence-export.sh" \
  "S5-01" "3"

echo ""

# ── S5-02 tasks (Phase 3 on-prem scripts) ────────────────────────────────────
create_task \
  "[S5-02] Build onprem-failover.sh — on-prem HA failover automation" \
  "Implement scripts/dr/onprem-failover.sh\n\nAutomates on-prem HA failover drill: stops keepalived (not just postgresql — nopreempt critical behaviour), asserts VIP moves to pg-standby, validates app health, captures evidence.\n\nRequires: --confirm flag\nSupports: --dry-run\nReference: docs/03-operations/dr-validation-runbook.md\nScript: already scaffolded at scripts/dr/onprem-failover.sh" \
  "S5-02" "2"

create_task \
  "[S5-02] Build onprem-fallback.sh — on-prem HA fallback automation" \
  "Implement scripts/dr/onprem-fallback.sh\n\nAutomates on-prem HA fallback: starts postgresql + keepalived on pg-primary, asserts VIP returns, polls replication resumption, validates app reconnects to primary.\n\nRequires: --confirm flag\nSupports: --dry-run\nReference: docs/03-operations/dr-validation-runbook.md\nScript: already scaffolded at scripts/dr/onprem-fallback.sh" \
  "S5-02" "2"

echo ""

# ── S5-03 tasks (Phase 4 full-site scaffolds -> full implementation) ──────────
create_task \
  "[S5-03] Enable fullsite-failover.sh execution steps (scaffold -> production)" \
  "fullsite-failover.sh is scaffolded with pre-checks fully implemented.\nExecution steps FS-1 through FS-10 are marked NOT_IMPLEMENTED.\n\nThis task: review each step, enable in sequence, test with --dry-run, validate.\n\nDestructive: stops pg-primary services (reversible via failback)\nRequires: --confirm flag, explicit review session\n\nReference: docs/03-operations/full-site-failover-runbook.md\nScript: scripts/dr/fullsite-failover.sh" \
  "S5-03" "2"

create_task \
  "[S5-03] Enable fullsite-failback.sh execution steps (scaffold -> production)" \
  "fullsite-failback.sh is scaffolded with H-1..H-7 pre-checks fully implemented.\nExecution steps FB-1 through FB-13 are marked NOT_IMPLEMENTED.\n\nThis task: review each step, enable in sequence, test with --dry-run, validate.\n\nTwo separate destructive gates:\n  GATE 1: --confirm-destructive pg-primary (wipes pg-primary data dir)\n  GATE 2: --confirm-destructive dr-vm (wipes DR VM data dir)\n\nReference: docs/03-operations/full-site-failback-runbook.md\nScript: scripts/dr/fullsite-failback.sh" \
  "S5-03" "2"

echo ""
echo "Task creation complete. Link all tasks to parent S4-09 (${PARENT_TASK_ID}) manually in ClickUp."
echo ""
