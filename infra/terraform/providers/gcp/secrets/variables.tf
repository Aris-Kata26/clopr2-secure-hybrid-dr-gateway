# providers/gcp/secrets — Variables
# STATUS: SCAFFOLD — NOT DEPLOYED

variable "env_name" {
  type        = string
  description = "Logical environment name"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "secret_name_prefix" {
  type        = string
  description = "Prefix for secret IDs (e.g. clopr2-dr-gcp-euw3)"
  default     = "clopr2"
}

variable "pg_replication_password" {
  type        = string
  description = "PostgreSQL replication password to store in Secret Manager"
  sensitive   = true
}

variable "consumer_service_account_email" {
  type        = string
  description = "Service account email to grant secretAccessor role"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "GCP resource labels"
  default     = {}
}
