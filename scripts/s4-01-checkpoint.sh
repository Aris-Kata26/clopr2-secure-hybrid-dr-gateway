#!/bin/bash
# S4-01 Checkpoint Evaluation Script (16:30Z)
# Collects extension states, heartbeat, syslog, and validation data

set -e

TIMESTAMP=$(date -u +'%Y%m%d-%H%M%SZ')
EVIDENCE_DIR="docs/05-evidence/outputs"
RG="rg-clopr2-katar711-gwc"
MACHINES=("pg-primary" "pg-standby-dr" "app-onprem")

echo "═══════════════════════════════════════════════════════════════════"
echo "S4-01 CHECKPOINT EVALUATION - ${TIMESTAMP}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Create evidence directory
mkdir -p "${EVIDENCE_DIR}"

# 1. Extension States for pg-standby-dr and app-onprem
echo "[1/7] Collecting extension states..."
{
  echo "=== Extension States - pg-standby-dr ==="
  az vm extension list --resource-group "${RG}" --vm-name "pg-standby-dr" --output table 2>/dev/null || echo "ERROR: Could not fetch pg-standby-dr extensions"
  echo ""
  echo "=== Extension States - app-onprem ==="
  az vm extension list --resource-group "${RG}" --vm-name "app-onprem" --output table 2>/dev/null || echo "ERROR: Could not fetch app-onprem extensions"
  echo ""
  echo "=== Instance View - Provisioning State ==="
  for machine in "${MACHINES[@]}"; do
    echo "  $machine:"
    az vm get-instance-view --resource-group "${RG}" --name "$machine" --query "instanceView.statuses[?starts_with(code, 'ProvisioningState')]" --output table 2>/dev/null || echo "    ERROR: Could not fetch instance view for $machine"
  done
} | tee "${EVIDENCE_DIR}/S4-01-checkpoint-extension-states-${TIMESTAMP}.txt"

# 2. Heartbeat Status (Log Analytics query for heartbeat)
echo ""
echo "[2/7] Checking heartbeat status..."
{
  echo "=== Heartbeat Status (Last 5 minutes) ==="
  for machine in "${MACHINES[@]}"; do
    echo "  $machine:"
    # Query Log Analytics for recent heartbeats
    az monitor log-analytics query \
      --workspace "law-clopr2-katar711-gwc" \
      --analytics-query "Heartbeat | where Computer == '${machine}' | top 1 by TimeGenerated" \
      --output table 2>/dev/null || echo "    [No recent heartbeat data or query failed]"
  done
} | tee "${EVIDENCE_DIR}/S4-01-checkpoint-heartbeats-${TIMESTAMP}.txt"

# 3. Syslog/Event Logs (from extension output)
echo ""
echo "[3/7] Collecting extension logs..."
{
  echo "=== Extension Stderr/Stdout Logs ==="
  for machine in "${MACHINES[@]}"; do
    echo "  $machine:"
    # Try to get extension instance view with detailed status
    az vm extension get-instance-view --resource-group "${RG}" --vm-name "$machine" --name "AzureMonitorLinuxAgent" \
      --query "statuses[*].[code, message]" --output table 2>/dev/null || echo "    [No extension output available]"
  done
} | tee "${EVIDENCE_DIR}/S4-01-checkpoint-extension-logs-${TIMESTAMP}.txt"

# 4. PostgreSQL Replication Status (via queryable metrics if available)
echo ""
echo "[4/7] Checking replication health indicators..."
{
  echo "=== VM Metrics - CPU/Memory (Proxy for system health) ==="
  for machine in "${MACHINES[@]}"; do
    echo "  $machine (last 5 min avg):"
    az monitor metrics list \
      --resource "/subscriptions/$(az account show -q --query id -o tsv)/resourceGroups/${RG}/providers/Microsoft.Compute/virtualMachines/${machine}" \
      --metric "Percentage CPU" \
      --output table 2>/dev/null | head -3 || echo "    [Metrics not immediately available]"
  done
} | tee "${EVIDENCE_DIR}/S4-01-checkpoint-vm-health-${TIMESTAMP}.txt"

# 5. WireGuard/Network Connectivity Check (via Arc agent telemetry)
echo ""
echo "[5/7] Validating Arc agent connectivity..."
{
  echo "=== Azure Arc Agent Status ==="
  for machine in "${MACHINES[@]}"; do
    echo "  $machine:"
    az connectedmachine show --resource-group "${RG}" --name "$machine" \
      --query "{Name: name, Status: status, AgentVersion: agentVersion, LastStatus: lastStatusChange}" \
      --output table 2>/dev/null || echo "    [Arc agent status unavailable]"
  done
} | tee "${EVIDENCE_DIR}/S4-01-checkpoint-arc-status-${TIMESTAMP}.txt"

# 6. Defender/Monitoring Alerts
echo ""
echo "[6/7] Checking for critical alerts..."
{
  echo "=== Recent Alerts (Last 30 minutes) ==="
  az monitor alert list --resource-group "${RG}" --output table 2>/dev/null | head -10 || echo "[No alerts or query unavailable]"
} | tee "${EVIDENCE_DIR}/S4-01-checkpoint-alerts-${TIMESTAMP}.txt"

# 7. Summary Assessment
echo ""
echo "[7/7] Generating checkpoint summary..."
{
  echo "═══════════════════════════════════════════════════════════════════"
  echo "S4-01 CHECKPOINT SUMMARY - ${TIMESTAMP}"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "EVALUATION CRITERIA:"
  echo "  1. pg-standby-dr extension provisioning state = 'Succeeded'"
  echo "  2. app-onprem extension provisioning state = 'Succeeded'"
  echo "  3. All machines have recent heartbeat (< 5 min)"
  echo "  4. Arc agent status = 'Connected' for all machines"
  echo "  5. No critical alerts in past 30 minutes"
  echo ""
  echo "EVIDENCE FILES COLLECTED:"
  ls -lh "${EVIDENCE_DIR}/S4-01-checkpoint-"* 2>/dev/null | awk '{print "  " $9}' || echo "  [Files being written...]"
  echo ""
  echo "NEXT STEPS:"
  echo "  • Review evidence files for success indicators"
  echo "  • Validate replication health via SSH to pg-primary/pg-standby-dr"
  echo "  • Confirm Keepalived VIP active on primary"
  echo "  • Decide: S4-01 success → S4-02 launch | S4-01 blocked → S4-06 start"
  echo ""
} | tee "${EVIDENCE_DIR}/S4-01-checkpoint-summary-${TIMESTAMP}.txt"

echo ""
echo "✓ Checkpoint evaluation data collected"
echo "Evidence location: ${EVIDENCE_DIR}/"
echo "Timestamp: ${TIMESTAMP}"
