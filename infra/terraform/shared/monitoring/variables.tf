# shared/monitoring — Interface Contract
# ========================================
# Defines the required inputs for any cloud provider's log/alert sink.
# This file is the logical interface — not an implementation.
#
# Implementations:
#   providers/azure/monitoring/  → azurerm_log_analytics_workspace + alert rules (live)
#   providers/aws/monitoring/    → aws_cloudwatch_log_group (scaffold)
#   providers/gcp/monitoring/    → google_logging_log_sink (scaffold)

variable "env_name" {
  type        = string
  description = "Logical environment name"
}

variable "region" {
  type        = string
  description = "Provider region for the monitoring workspace"
}

variable "retention_days" {
  type        = number
  description = "Log retention period in days"
  default     = 30
}

variable "alert_email" {
  type        = string
  description = "Email address for alert notifications"
  default     = null
}

variable "vm_resource_ids" {
  type        = list(string)
  description = <<-EOT
    List of VM resource IDs to attach monitoring to:
    Azure: azurerm_linux_virtual_machine.id (list)
    AWS:   aws_instance.id (list)
    GCP:   google_compute_instance.id (list)
  EOT
  default     = []
}

variable "alert_thresholds" {
  type = object({
    cpu_percent       = number
    mem_percent       = number
    disk_percent      = number
    pg_connections    = number
    wg_handshake_age  = number
  })
  description = <<-EOT
    Alert thresholds for key metrics.
    Providers implement these as native alert rules where supported.
    Approximate equivalents:
      Azure:  azurerm_monitor_scheduled_query_rules_alert_v2
      AWS:    aws_cloudwatch_metric_alarm
      GCP:    google_monitoring_alert_policy
  EOT
  default = {
    cpu_percent      = 85
    mem_percent      = 85
    disk_percent     = 80
    pg_connections   = 80
    wg_handshake_age = 300
  }
}

variable "tags" {
  type        = map(string)
  description = "Resource tags / labels"
  default     = {}
}
