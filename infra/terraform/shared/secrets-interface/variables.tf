# shared/secrets-interface — Interface Contract
# ===============================================
# Defines the required inputs for any cloud provider's secret store.
# This file is the logical interface — not an implementation.
#
# Implementations:
#   providers/azure/secrets/  → azurerm_key_vault + azurerm_role_assignment (live)
#   providers/aws/secrets/    → aws_secretsmanager_secret (scaffold)
#   providers/gcp/secrets/    → google_secret_manager_secret (scaffold)

variable "env_name" {
  type        = string
  description = "Logical environment name"
}

variable "region" {
  type        = string
  description = "Provider region for the secret store"
}

variable "resource_group_or_project" {
  type        = string
  description = <<-EOT
    Scoping resource for the secret store:
    Azure: resource_group_name
    AWS:   (not applicable — secrets are global with path prefix)
    GCP:   project_id
  EOT
  default     = null
}

variable "secret_name_prefix" {
  type        = string
  description = "Prefix for all secret names (e.g. clopr2-dr-fce)"
  default     = "clopr2"
}

variable "pg_replication_password" {
  type        = string
  description = "PostgreSQL replication password to store"
  sensitive   = true
}

variable "consumer_identity_id" {
  type        = string
  description = <<-EOT
    Identity to grant read access to secrets:
    Azure: azurerm_linux_virtual_machine.identity[0].principal_id
    AWS:   aws_iam_role.arn
    GCP:   google_service_account.email
  EOT
  default     = null
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Soft delete retention (provider support varies)"
  default     = 7
}

variable "tags" {
  type        = map(string)
  description = "Resource tags / labels"
  default     = {}
}
