#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p docs/05-evidence/monitoring

RG='rg-clopr2-katar711-gwc'
WS='ad36192c-ac77-40dc-878d-0f8e74cd3638'
OUT='docs/05-evidence/monitoring/status-latest.txt'

{
  echo "GeneratedUTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[ArcConnectedStatus]"
  az connectedmachine list -g "$RG" --query "[?name=='pg-primary' || name=='pg-standby' || name=='app-onprem'].{name:name,status:properties.status,lastStatusChange:properties.lastStatusChange}" -o table
  echo

  echo "[ExtensionsSummary]"
  for m in pg-primary pg-standby app-onprem; do
    echo "Machine=$m"
    az connectedmachine extension list -g "$RG" --machine-name "$m" --query "[].{name:name,publisher:publisher,type:type,provisioningState:provisioningState}" -o table || true
    echo
  done

  echo "[ExtensionsInstanceViewRaw]"
  for m in pg-primary pg-standby app-onprem; do
    rid=$(az connectedmachine show -g "$RG" -n "$m" --query id -o tsv | tr -d '\r')
    for e in AzureMonitorLinuxAgent DependencyAgentLinux; do
      extid="$rid/extensions/$e"
      echo "Resource=$m Extension=$e"
      az resource show --ids "$extid" --query "{prov:properties.provisioningState,statuses:properties.instanceView.statuses,substatuses:properties.instanceView.substatuses}" -o json || true
      echo
    done
  done

  echo "[DCRAssociations]"
  dcrid=$(az monitor data-collection rule show -g "$RG" -n dcr-hybrid-monitoring --query id -o tsv | tr -d '\r')
  echo "DCRID=$dcrid"
  for m in pg-primary pg-standby app-onprem; do
    rid=$(az connectedmachine show -g "$RG" -n "$m" --query id -o tsv | tr -d '\r')
    echo "Machine=$m"
    az monitor data-collection rule association list --resource "$rid" --query "[].{name:name,dcr:dataCollectionRuleId}" -o table || true
    echo
  done

  echo "[HeartbeatByComputer_15m]"
  az monitor log-analytics query -w "$WS" --analytics-query "Heartbeat | where TimeGenerated > ago(15m) | summarize c=count(), last=max(TimeGenerated) by Computer | order by Computer asc" -o table || true
  echo

  echo "[SyslogByComputer_15m]"
  az monitor log-analytics query -w "$WS" --analytics-query "Syslog | where TimeGenerated > ago(15m) | summarize c=count(), last=max(TimeGenerated) by Computer | order by Computer asc" -o table || true
} > "$OUT" 2>&1

cat "$OUT"
