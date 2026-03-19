# shared/compute-db — Interface Contract
# =========================================
# Defines the required inputs for any cloud provider's DR database VM.
# This file is the logical interface — not an implementation.
#
# Implementations:
#   providers/azure/compute-db/   → azurerm_linux_virtual_machine
#   providers/aws/compute-db/     → aws_instance (scaffold)
#   providers/gcp/compute-db/     → google_compute_instance (scaffold)
#
# Rules:
#   - Do NOT add provider-specific resource blocks here.
#   - Any provider implementing this interface must accept all required variables.
#   - Optional variables (default = null) may be ignored by providers that
#     do not support that capability natively.

# ── Identity ──────────────────────────────────────────────────────────────────

variable "env_name" {
  type        = string
  description = "Logical environment name (e.g. dr-fce, dr-aws-use1, dr-gcp-euw1)"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags / labels applied to all created resources"
  default     = {}
}

# ── Placement ─────────────────────────────────────────────────────────────────

variable "region" {
  type        = string
  description = <<-EOT
    Provider region for the DB VM.
    Azure: germanywestcentral | AWS: eu-central-1 | GCP: europe-west3
  EOT
}

variable "subnet_id" {
  type        = string
  description = <<-EOT
    Subnet to place the DB VM in (provider-specific format):
    Azure: azurerm_subnet.id
    AWS:   aws_subnet.id
    GCP:   google_compute_subnetwork.self_link
  EOT
}

variable "private_ip" {
  type        = string
  description = "Static private IP for the DB VM. Must be within subnet CIDR."
  default     = null
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "vm_size" {
  type        = string
  description = <<-EOT
    Instance size / VM SKU (provider-specific).
    Reference mapping in providers/*/compute-db/README.md:
    Azure: Standard_B2ats_v2 | AWS: t3.small | GCP: e2-small
  EOT
}

variable "disk_size_gb" {
  type        = number
  description = "OS disk size in GB"
  default     = 30
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for operator access to the DB VM"
  sensitive   = true
}

variable "admin_username" {
  type        = string
  description = "OS-level admin / SSH username"
  default     = "adminuser"
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────

variable "postgres_version" {
  type        = string
  description = "PostgreSQL major version to deploy (must match on-prem primary)"
  default     = "16"
}

variable "pg_replication_password" {
  type        = string
  description = "PostgreSQL replication user password — passed to cloud-init or secret store"
  sensitive   = true
  default     = null
}

# ── WireGuard ─────────────────────────────────────────────────────────────────

variable "wg_tunnel_ip" {
  type        = string
  description = <<-EOT
    WireGuard tunnel IP assigned to this VM.
    Current Azure: 10.200.0.2/30
    AWS target:    10.200.0.6/30  (10.200.0.4/30 subnet)
    GCP target:    10.200.0.10/30 (10.200.0.8/30 subnet)
  EOT
}

variable "wg_private_key" {
  type        = string
  description = "WireGuard private key for this VM's wg0 interface"
  sensitive   = true
}

variable "wg_peer_public_key" {
  type        = string
  description = "WireGuard public key of the on-prem peer (pg-primary)"
  sensitive   = true
}

variable "wg_onprem_public_ip" {
  type        = string
  description = "Public IP of the on-prem WireGuard peer (pg-primary's ISP IP)"
}

variable "wg_listen_port" {
  type        = number
  description = "UDP port for WireGuard listener on this VM"
  default     = 51820
}

# ── Secret store (optional — provider-specific) ───────────────────────────────

variable "secret_store_id" {
  type        = string
  description = <<-EOT
    Resource ID of the secret store to grant this VM's identity access to.
    Azure: azurerm_key_vault.id
    AWS:   aws_secretsmanager_secret.arn
    GCP:   google_secret_manager_secret.id
    Set null if secrets are injected via cloud-init / userdata only.
  EOT
  default     = null
}
