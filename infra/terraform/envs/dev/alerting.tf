# =============================================================================
# envs/dev/alerting.tf — Minimum Viable Alerting + Dashboard
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# Implemented: 2026-03-18 (architecture hardening phase)
#
# SIGNALS MONITORED (dev workspace — ad36192c-ac77-40dc-878d-0f8e74cd3638):
#   - Heartbeat from pg-primary and app-onprem (Arc + AMA agents)
#   - Keepalived VRRP syslog from pg-primary (priority changes, state transitions)
#   - systemd syslog from app-onprem (Docker service health)
#
# KNOWN LIMITATIONS:
#   - pg-standby: Arc extension stuck (HCRP409) — NOT in this workspace.
#     Heartbeat and syslog from pg-standby are unavailable. Manual check required.
#   - WireGuard handshakes: not logged to syslog on pg-primary — tunnel health
#     proxied via Azure DR VM heartbeat alert in envs/dr-fce/alerting.tf.
#
# ALERT COVERAGE:
#   1. alert-onprem-heartbeat-silence   — pg-primary or app-onprem silent > 10m
#   2. alert-keepalived-priority-drop   — pg_isready fails (VRRP priority 100→80)
#   3. alert-keepalived-vip-state-change— pg-primary enters BACKUP (VIP moved)
#   4. alert-app-docker-failure         — Docker service stopped on app-onprem
#
# ACTION GROUP: ag-clopr2-ops (email to ops_alert_email)
# WORKBOOK: wb-clopr2-dr-ops — DR operational visibility for presentation + ops
# =============================================================================

# ---------------------------------------------------------------------------
# Data source — Log Analytics workspace (created by loganalytics module)
# ---------------------------------------------------------------------------

data "azurerm_log_analytics_workspace" "this" {
  name                = var.loganalytics_name
  resource_group_name = azurerm_resource_group.this.name
}

# ---------------------------------------------------------------------------
# Action Group — email notification for all alerts in this environment
# ---------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-clopr2-ops"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "clopr2ops"
  tags                = local.tags

  email_receiver {
    name                    = "ops-email"
    email_address           = var.ops_alert_email
    use_common_alert_schema = true
  }
}

# ---------------------------------------------------------------------------
# Alert 1: On-prem host heartbeat silence
# Fires if pg-primary OR app-onprem has not sent a heartbeat in 10 minutes.
# Heartbeat is sent every ~60s; 10m silence = host unreachable / agent down.
# Severity 1 (Critical) — host silence is a hard signal of failure.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "onprem_heartbeat_silence" {
  name                = "alert-onprem-heartbeat-silence"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  evaluation_frequency    = "PT5M"
  window_duration         = "PT10M"
  auto_mitigation_enabled = true
  scopes                  = [data.azurerm_log_analytics_workspace.this.id]
  severity                = 1
  description             = "CRITICAL: pg-primary or app-onprem has not sent a heartbeat in 10 minutes. Host may be down or Arc agent has failed. Investigate immediately."

  criteria {
    query = <<-KQL
      let monitored_hosts = datatable(Computer: string) [
        "pg-primary",
        "app-onprem"
      ];
      monitored_hosts
      | join kind=leftouter (
          Heartbeat
          | where TimeGenerated > ago(10m)
          | summarize LastSeen = max(TimeGenerated) by Computer
        ) on Computer
      | where isnull(LastSeen)
      | project Computer, Status = "SILENT"
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
      "alert_type" = "host_availability"
      "environment" = "on-prem"
      "runbook"    = "docs/03-operations/alerting-architecture.md"
    }
  }
}

# ---------------------------------------------------------------------------
# Alert 2: Keepalived priority drop — pg_isready failure on pg-primary
# Fires when Keepalived_vrrp logs a priority decrease from 100 to 80.
# This means pg_isready failed 3 consecutive checks (6 seconds).
# PostgreSQL may be starting, stopping, or unresponsive.
# Severity 2 (High) — priority drop is recoverable; monitor for persistence.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "keepalived_priority_drop" {
  name                = "alert-keepalived-priority-drop"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  scopes                  = [data.azurerm_log_analytics_workspace.this.id]
  severity                = 2
  description             = "HIGH: Keepalived on pg-primary has dropped priority from 100 to 80 — pg_isready failed 3 checks. PostgreSQL may be unresponsive. Check if VIP moves to pg-standby."

  criteria {
    query = <<-KQL
      Syslog
      | where Computer == "pg-primary"
      | where ProcessName == "Keepalived_vrrp"
      | where SyslogMessage contains "Changing effective priority from 100 to 80"
      | where TimeGenerated > ago(5m)
      | summarize Count = count()
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
      "alert_type" = "postgresql_health"
      "component"  = "keepalived-vrrp"
      "runbook"    = "docs/03-operations/alerting-architecture.md"
    }
  }
}

# ---------------------------------------------------------------------------
# Alert 3: Keepalived VIP state change — pg-primary enters BACKUP
# Fires when pg-primary Keepalived logs a transition to BACKUP state.
# This means the VIP (10.0.96.10) has moved to pg-standby.
# This is the observable marker that an on-prem HA failover has occurred.
# Severity 1 (Critical) — VIP moved = production traffic rerouted.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "keepalived_vip_state_change" {
  name                = "alert-keepalived-vip-state-change"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  scopes                  = [data.azurerm_log_analytics_workspace.this.id]
  severity                = 1
  description             = "CRITICAL: pg-primary Keepalived has entered BACKUP state. VIP 10.0.96.10 has moved to pg-standby. Production PostgreSQL traffic is now served by the standby. Confirm application health and begin failback procedure if unplanned."

  criteria {
    query = <<-KQL
      Syslog
      | where Computer == "pg-primary"
      | where ProcessName == "Keepalived_vrrp"
      | where SyslogMessage contains "Entering BACKUP STATE"
         or SyslogMessage contains "Going to BACKUP"
         or SyslogMessage contains "New primary elected"
      | where TimeGenerated > ago(5m)
      | summarize Count = count()
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
      "alert_type" = "vip_failover"
      "component"  = "keepalived-vrrp"
      "runbook"    = "docs/03-operations/dr-validation-runbook.md"
    }
  }
}

# ---------------------------------------------------------------------------
# Alert 4: Application Docker service failure on app-onprem
# Fires when systemd on app-onprem logs a Docker service failure or stop.
# The FastAPI app runs in Docker — a Docker failure means the app is down.
# Severity 2 (High) — application unavailable, users cannot reach /health.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "app_docker_failure" {
  name                = "alert-app-docker-failure"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  scopes                  = [data.azurerm_log_analytics_workspace.this.id]
  severity                = 2
  description             = "HIGH: Docker service on app-onprem has stopped or failed according to systemd. The FastAPI application (/health endpoint) is likely unavailable. Check app-onprem Docker status."

  criteria {
    query = <<-KQL
      Syslog
      | where Computer == "app-onprem"
      | where ProcessName == "systemd"
      | where SyslogMessage has_any ("docker.service", "docker")
        and SyslogMessage has_any ("failed", "Failed to start", "deactivating")
      | where TimeGenerated > ago(5m)
      | summarize Count = count()
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
      "alert_type" = "application_health"
      "component"  = "docker-app-onprem"
      "runbook"    = "docs/03-operations/alerting-architecture.md"
    }
  }
}

# ---------------------------------------------------------------------------
# NOTE: Azure Monitor Workbook
# azurerm_monitor_workbook is not available in azurerm ~4.0 (added in 4.x later).
# The workbook is deployed via Azure CLI using the ARM template approach.
# See: scripts/dr/deploy-workbook.sh and workbook-dr-ops.json in this directory.
# Evidence is captured in docs/05-evidence/alerting/
# ---------------------------------------------------------------------------
