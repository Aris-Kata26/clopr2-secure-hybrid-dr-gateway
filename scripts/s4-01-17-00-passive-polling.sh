#!/bin/bash
# S4-01 Passive Polling for 17:00Z Checkpoint
# Started: 16:35Z
# Target: 17:00Z
# Monitoring: pg-standby and app-onprem extension states

RG="rg-clopr2-katar711-gwc"
TIMESTAMP=$(date -u +'%Y%m%d-%H%M%SZ')
CHECKPOINT_LOG="docs/05-evidence/outputs/S4-01-17:00-checkpoint-${TIMESTAMP}.log"

echo "S4-01 Passive Polling Started: $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "${CHECKPOINT_LOG}"
echo "Target Checkpoint: 2026-03-13T17:00:00Z" >> "${CHECKPOINT_LOG}"
echo "Monitoring pg-standby and app-onprem extension states..." >> "${CHECKPOINT_LOG}"
echo "" >> "${CHECKPOINT_LOG}"

# Loop until 17:00Z
while true; do
  CURRENT_TIME=$(date +%s)
  TARGET_TIME=$(date -d "2026-03-13 17:00:00Z" +%s 2>/dev/null || date -d "2026-03-13 17:00:00 UTC" +%s 2>/dev/null || echo "0")
  
  if [ "$TARGET_TIME" != "0" ] && [ "$CURRENT_TIME" -ge "$TARGET_TIME" ]; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Checkpoint time reached!" >> "${CHECKPOINT_LOG}"
    break
  fi
  
  # Poll every 5 minutes
  sleep 300
done

# At checkpoint time, collect extension states
echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] POLLING EXTENSION STATES AT 17:00Z" >> "${CHECKPOINT_LOG}"
echo "" >> "${CHECKPOINT_LOG}"

for machine in "pg-standby" "app-onprem"; do
  echo "=== $machine Extension State ===" >> "${CHECKPOINT_LOG}"
  az connectedmachine extension list --resource-group "${RG}" --machine-name "$machine" --query "[].{Name:name, State:properties.provisioningState}" --output table 2>&1 >> "${CHECKPOINT_LOG}"
  echo "" >> "${CHECKPOINT_LOG}"
done

echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] 17:00Z polling complete" >> "${CHECKPOINT_LOG}"
echo "Log written to: ${CHECKPOINT_LOG}"

# Print summary to stdout
cat "${CHECKPOINT_LOG}"
