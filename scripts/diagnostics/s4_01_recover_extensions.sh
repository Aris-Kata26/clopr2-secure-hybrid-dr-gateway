#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/05-evidence/monitoring
OUT="docs/05-evidence/monitoring/extension-recovery.log"
RG='rg-clopr2-katar711-gwc'

{
  echo "RecoveryStartUTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  for m in pg-standby app-onprem; do
    echo "[cleanup:$m]"
    az connectedmachine extension delete -g "$RG" --machine-name "$m" --name AzureMonitorLinuxAgent --yes --only-show-errors || true
    az connectedmachine extension delete -g "$RG" --machine-name "$m" --name DependencyAgentLinux --yes --only-show-errors || true
  done

  for m in pg-standby app-onprem; do
    echo "[wait-delete:$m]"
    rid=$(az connectedmachine show -g "$RG" -n "$m" --query id -o tsv | tr -d '\r')
    for i in $(seq 1 15); do
      ama=$(az resource show --ids "$rid/extensions/AzureMonitorLinuxAgent" --query properties.provisioningState -o tsv 2>/dev/null || echo missing)
      dep=$(az resource show --ids "$rid/extensions/DependencyAgentLinux" --query properties.provisioningState -o tsv 2>/dev/null || echo missing)
      echo "poll=$i ama=$ama dep=$dep"
      if [[ "$ama" == "missing" && "$dep" == "missing" ]]; then
        break
      fi
      sleep 20
    done
  done

  for m in pg-standby app-onprem; do
    echo "[create:$m]"
    az connectedmachine extension create -g "$RG" --machine-name "$m" --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor --type AzureMonitorLinuxAgent --type-handler-version 1.40 --only-show-errors -o json || true
    az connectedmachine extension create -g "$RG" --machine-name "$m" --name DependencyAgentLinux --publisher Microsoft.Azure.Monitoring.DependencyAgent --type DependencyAgentLinux --type-handler-version 9.10 --only-show-errors -o json || true
  done

  echo "[post-create-states]"
  for m in pg-primary pg-standby app-onprem; do
    rid=$(az connectedmachine show -g "$RG" -n "$m" --query id -o tsv | tr -d '\r')
    for e in AzureMonitorLinuxAgent DependencyAgentLinux; do
      echo "machine=$m extension=$e"
      az resource show --ids "$rid/extensions/$e" --query "{prov:properties.provisioningState,statuses:properties.instanceView.statuses,substatuses:properties.instanceView.substatuses}" -o json || echo '{"missing":true}'
    done
  done

  echo "RecoveryEndUTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT" 2>&1

cat "$OUT"
