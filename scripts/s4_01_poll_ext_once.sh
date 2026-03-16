#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
out="docs/05-evidence/monitoring/ext-poll.txt"
rg='rg-clopr2-katar711-gwc'
{
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for m in pg-primary pg-standby app-onprem; do
    rid=$(az connectedmachine show -g "$rg" -n "$m" --query id -o tsv 2>/dev/null | tr -d '\r' || true)
    if [[ -z "$rid" ]]; then
      echo "$m RID=missing"
      continue
    fi
    ama=$(az resource show --ids "$rid/extensions/AzureMonitorLinuxAgent" --query properties.provisioningState -o tsv 2>/dev/null || echo missing)
    dep=$(az resource show --ids "$rid/extensions/DependencyAgentLinux" --query properties.provisioningState -o tsv 2>/dev/null || echo missing)
    echo "$m AMA=$ama DEP=$dep"
    echo "$m AMA_DETAIL:"
    az resource show --ids "$rid/extensions/AzureMonitorLinuxAgent" --query "{prov:properties.provisioningState,statuses:properties.instanceView.statuses,substatuses:properties.instanceView.substatuses}" -o json 2>/dev/null || echo '{"missing":true}'
    echo "$m DEP_DETAIL:"
    az resource show --ids "$rid/extensions/DependencyAgentLinux" --query "{prov:properties.provisioningState,statuses:properties.instanceView.statuses,substatuses:properties.instanceView.substatuses}" -o json 2>/dev/null || echo '{"missing":true}'
  done
} > "$out"
cat "$out"
