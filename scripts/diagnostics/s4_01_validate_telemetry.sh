#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/05-evidence/monitoring
OUT_HB="docs/05-evidence/monitoring/log-analytics-heartbeat-query.txt"
OUT_SYS="docs/05-evidence/monitoring/log-analytics-syslog-query.txt"
OUT_SUM="docs/05-evidence/monitoring/status-latest.txt"
RG='rg-clopr2-katar711-gwc'
WS='ad36192c-ac77-40dc-878d-0f8e74cd3638'

az monitor log-analytics query -w "$WS" --analytics-query "Heartbeat | where TimeGenerated > ago(15m) | summarize count() by Computer | order by Computer asc" -o table > "$OUT_HB" 2>&1 || true
az monitor log-analytics query -w "$WS" --analytics-query "Syslog | where TimeGenerated > ago(15m) | summarize count() by Computer | order by Computer asc" -o table > "$OUT_SYS" 2>&1 || true

{
  echo "GeneratedUTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[ArcConnectedStatus]"
  az connectedmachine list -g "$RG" --query "[?name=='pg-primary' || name=='pg-standby' || name=='app-onprem'].{name:name,status:properties.status,lastStatusChange:properties.lastStatusChange}" -o table
  echo
  echo "[ExtensionProvisioning]"
  for m in pg-primary pg-standby app-onprem; do
    rid=$(az connectedmachine show -g "$RG" -n "$m" --query id -o tsv | tr -d '\r')
    ama=$(az resource show --ids "$rid/extensions/AzureMonitorLinuxAgent" --query properties.provisioningState -o tsv 2>/dev/null || echo missing)
    dep=$(az resource show --ids "$rid/extensions/DependencyAgentLinux" --query properties.provisioningState -o tsv 2>/dev/null || echo missing)
    echo "$m AMA=$ama DEP=$dep"
  done
  echo
  echo "[DCRAssociations]"
  for m in pg-primary pg-standby app-onprem; do
    rid=$(az connectedmachine show -g "$RG" -n "$m" --query id -o tsv | tr -d '\r')
    echo "Machine=$m"
    az monitor data-collection rule association list --resource "$rid" --query "[].{name:name,dcr:dataCollectionRuleId}" -o table || true
  done
  echo
  echo "[HeartbeatByComputer_15m]"
  cat "$OUT_HB"
  echo
  echo "[SyslogByComputer_15m]"
  cat "$OUT_SYS"
} > "$OUT_SUM" 2>&1

cat "$OUT_SUM"
