# shared/compute-app — Interface Contract
# ==========================================
# Defines the required inputs for any cloud provider's application VM.
# This file is the logical interface — not an implementation.
#
# Implementations:
#   providers/azure/compute-app/  → azurerm_linux_virtual_machine (scaffold)
#   providers/aws/compute-app/    → aws_instance (scaffold)
#   providers/gcp/compute-app/    → google_compute_instance (scaffold)
#
# Current status: app-onprem runs on Proxmox, not cloud.
# This interface targets the optional cloud-hosted app DR VM pattern.

variable "env_name" {
  type        = string
  description = "Logical environment name"
}

variable "region" {
  type        = string
  description = "Provider region for the app VM"
}

variable "subnet_id" {
  type        = string
  description = "Subnet to place the app VM in (provider-specific format)"
}

variable "vm_size" {
  type        = string
  description = <<-EOT
    Instance size for the app VM (provider-specific).
    Azure: Standard_B1s | AWS: t3.micro | GCP: e2-micro
  EOT
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for operator access"
  sensitive   = true
}

variable "admin_username" {
  type        = string
  description = "OS-level admin / SSH username"
  default     = "adminuser"
}

variable "disk_size_gb" {
  type        = number
  description = "OS disk size in GB"
  default     = 20
}

variable "container_image" {
  type        = string
  description = <<-EOT
    Container image to run on the app VM.
    Format: registry/image:tag
    Current: clopr2-app:latest (built locally, transferred manually)
    Future:  acr.azurecr.io/clopr2-app:tag | ECR URI | Artifact Registry URI
  EOT
}

variable "app_port" {
  type        = number
  description = "Port the FastAPI app listens on inside the container"
  default     = 8000
}

variable "host_port" {
  type        = number
  description = "Port exposed on the host VM"
  default     = 8080
}

variable "db_host" {
  type        = string
  description = "Database host the app connects to (VIP or private IP)"
}

variable "db_port" {
  type        = number
  description = "PostgreSQL port"
  default     = 5432
}

variable "db_name" {
  type        = string
  description = "PostgreSQL database name"
  default     = "appdb"
}

variable "db_user" {
  type        = string
  description = "PostgreSQL application user"
  default     = "appuser"
}

variable "db_password" {
  type        = string
  description = "PostgreSQL application user password"
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Resource tags / labels"
  default     = {}
}
