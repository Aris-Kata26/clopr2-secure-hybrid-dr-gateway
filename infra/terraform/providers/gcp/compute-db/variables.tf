# providers/gcp/compute-db — Variables
# STATUS: SCAFFOLD — NOT DEPLOYED
# Mirrors shared/compute-db interface with GCP-specific additions.

variable "env_name" {
  type        = string
  description = "Logical environment name (e.g. dr-gcp-euw3)"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region (e.g. europe-west3)"
  default     = "europe-west3"
}

variable "network_self_link" {
  type        = string
  description = "GCP VPC network self_link (from providers/gcp/core-network outputs)"
}

variable "subnetwork_self_link" {
  type        = string
  description = "GCP subnetwork self_link for the DB VM"
}

variable "subnet_id" {
  type        = string
  description = "Alias for subnetwork_self_link (interface compatibility)"
  default     = null
}

variable "private_ip" {
  type        = string
  description = "Static internal IP for the Compute Engine VM (optional)"
  default     = null
}

variable "vm_size" {
  type        = string
  description = "GCP machine type (e.g. e2-small — maps to Azure Standard_B2ats_v2)"
  default     = "e2-small"
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB"
  default     = 30
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key (stored in instance metadata as ssh-keys)"
  sensitive   = true
}

variable "admin_username" {
  type        = string
  description = "SSH username"
  default     = "adminuser"
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL major version"
  default     = "16"
}

variable "pg_replication_password" {
  type        = string
  description = "PostgreSQL replication password"
  sensitive   = true
  default     = null
}

variable "wg_tunnel_ip" {
  type        = string
  description = "WireGuard tunnel IP for this VM (e.g. 10.200.0.10/30)"
  default     = "10.200.0.10/30"
}

variable "wg_private_key" {
  type        = string
  description = "WireGuard private key for wg0 interface"
  sensitive   = true
}

variable "wg_peer_public_key" {
  type        = string
  description = "WireGuard public key of on-prem peer (pg-primary)"
  sensitive   = true
}

variable "wg_onprem_public_ip" {
  type        = string
  description = "On-prem public IP for WireGuard endpoint"
}

variable "wg_listen_port" {
  type        = number
  description = "WireGuard UDP listen port"
  default     = 51820
}

variable "secret_store_id" {
  type        = string
  description = "GCP Secret Manager secret ID to grant service account access"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "GCP resource labels"
  default     = {}
}
