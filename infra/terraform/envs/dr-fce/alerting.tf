# =============================================================================
# envs/dr-fce/alerting.tf — Azure DR VM Alerting
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# Implemented: 2026-03-18 (architecture hardening phase)
#
# SIGNALS MONITORED (dr-fce workspace — 7d25b9ec-b9aa-4a5b-a8f6-065f26dc630d):
#   - Heartbeat from vm-pg-dr-fce (AMA agent)
#   - Syslog from vm-pg-dr-fce (limited: daemon, cron)
#
# ALERT COVERAGE:
#   1. alert-pgdr-heartbeat-silence — Azure DR VM silent > 10m
#      (proxies WireGuard tunnel health: if tunnel is down, VM cannot send heartbeat)
#
# On-prem alerts (pg-primary, app-onprem, Keepalived, Docker) are in:
#   envs/dev/alerting.tf
# =============================================================================

# ---------------------------------------------------------------------------
# Data source — Log Analytics workspace (defined in dr-fce main.tf)
# ---------------------------------------------------------------------------

data "azurerm_log_analytics_workspace" "dr" {
  name                = var.loganalytics_name
  resource_group_name = azurerm_resource_group.dr.name
}

# ---------------------------------------------------------------------------
# Action Group — email notification for Azure DR environment alerts
# ---------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-clopr2-ops-dr"
  resource_group_name = azurerm_resource_group.dr.name
  short_name          = "clopr2dr"
  tags                = local.tags

  email_receiver {
    name                    = "ops-email"
    email_address           = var.ops_alert_email
    use_common_alert_schema = true
  }
}

# ---------------------------------------------------------------------------
# Alert 5: Azure DR VM heartbeat silence
# Fires if vm-pg-dr-fce has not sent a heartbeat in 10 minutes.
#
# This alert serves dual purpose:
#   a) VM is down or AMA agent has failed
#   b) WireGuard tunnel health proxy: if the tunnel between pg-primary and
#      vm-pg-dr-fce is broken, the Azure DR VM cannot forward telemetry to
#      the Log Analytics workspace (data flows via tunnel or Azure direct).
#      An agent that can't phone home suggests connectivity issues.
#
# Note: WireGuard handshakes are not logged continuously to syslog.
#       This heartbeat alert is the strongest available proxy for tunnel health.
#
# Severity 1 (Critical) — Azure DR replica may be unreachable or down.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pgdr_heartbeat_silence" {
  name                = "alert-pgdr-heartbeat-silence"
  resource_group_name = azurerm_resource_group.dr.name
  location            = azurerm_resource_group.dr.location
  tags                = local.tags

  evaluation_frequency    = "PT5M"
  window_duration         = "PT10M"
  auto_mitigation_enabled = true
  scopes                  = [data.azurerm_log_analytics_workspace.dr.id]
  severity                = 1
  description          = "CRITICAL: vm-pg-dr-fce (Azure DR PostgreSQL replica) has not sent a heartbeat in 10 minutes. Azure DR VM may be down, AMA agent failed, or WireGuard tunnel may be broken. Check Azure VM status and WireGuard handshake on pg-primary."

  criteria {
    query = <<-KQL
      let dr_vm = "vm-pg-dr-fce";
      Heartbeat
      | where Computer == dr_vm
      | where TimeGenerated > ago(10m)
      | summarize LastSeen = max(TimeGenerated)
      | extend Status = iff(isnull(LastSeen), "SILENT", "ONLINE")
      | where Status == "SILENT"
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.ops.id]
    custom_properties = {
      "alert_type" = "azure_dr_availability"
      "component"  = "vm-pg-dr-fce"
      "runbook"    = "docs/03-operations/alerting-architecture.md"
    }
  }
}
