#!/usr/bin/env bash
# =============================================================================
# scripts/dr/deploy-workbook.sh — Deploy Azure Monitor Workbook
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# Deploys (or re-deploys) the DR Operational Dashboard workbook to the
# dev workspace resource group (rg-clopr2-katar711-gwc).
#
# azurerm_monitor_workbook is not available in azurerm ~4.0 — we use the
# Azure CLI / ARM REST API instead. The workbook JSON definition is stored
# alongside the dev Terraform environment:
#   infra/terraform/envs/dev/workbook-dr-ops.json
#
# USAGE:
#   ./scripts/dr/deploy-workbook.sh
#
# PREREQUISITES:
#   - az login (or service principal / managed identity)
#   - Subscription 94e5704a-b411-402b-a8f3-ef46309fe5fb selected
#   - Python 3 available on PATH
#
# RE-DEPLOYMENT:
#   To re-deploy (update), call this script again. It always creates a new
#   resource with a fresh GUID. To replace an existing one, delete first:
#     az resource delete --ids <workbook-resource-id>
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKBOOK_JSON="${REPO_ROOT}/infra/terraform/envs/dev/workbook-dr-ops.json"
RG="rg-clopr2-katar711-gwc"
LOCATION="germanywestcentral"
SUBSCRIPTION="94e5704a-b411-402b-a8f3-ef46309fe5fb"
WS_ID="/subscriptions/${SUBSCRIPTION}/resourceGroups/${RG}/providers/Microsoft.OperationalInsights/workspaces/log-clopr2-dev-gwc"

if [[ ! -f "$WORKBOOK_JSON" ]]; then
  echo "ERROR: workbook JSON not found at $WORKBOOK_JSON" >&2
  exit 1
fi

WORKBOOK_GUID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
echo "Deploying workbook with GUID: $WORKBOOK_GUID"

SERIALIZED=$(python3 -c "
import json, sys
with open('${WORKBOOK_JSON}') as f:
    data = f.read()
print(json.dumps(data))
")

az resource create \
  --resource-group "$RG" \
  --resource-type "microsoft.insights/workbooks" \
  --name "$WORKBOOK_GUID" \
  --location "$LOCATION" \
  --is-full-object \
  --properties "{
    \"location\": \"${LOCATION}\",
    \"kind\": \"shared\",
    \"properties\": {
      \"displayName\": \"CLOPR2 DR Operational Dashboard\",
      \"category\": \"workbook\",
      \"sourceId\": \"${WS_ID}\",
      \"serializedData\": ${SERIALIZED}
    }
  }"

echo ""
echo "Workbook deployed: CLOPR2 DR Operational Dashboard"
echo "Resource group:    ${RG}"
echo "Workbook GUID:     ${WORKBOOK_GUID}"
echo "View in portal:    https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION}/resourceGroups/${RG}/providers/microsoft.insights/workbooks/${WORKBOOK_GUID}/workbook"
