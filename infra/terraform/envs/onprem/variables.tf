variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL. For bpg/proxmox this should be like https://10.0.10.161:8006/ (no /api2/json). This env will also accept the /api2/json suffix and strip it."
}

variable "pm_api_token_id" {
  type        = string
  description = "Proxmox API token ID (user@realm!token)"

  validation {
    condition     = can(regex("^[^@]+@[^!]+![A-Za-z0-9._-]+$", var.pm_api_token_id))
    error_message = "pm_api_token_id must be in the format user@realm!tokenname (example: root@pam!terraform)."
  }
}

variable "pm_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", trimspace(var.pm_api_token_secret)))
    error_message = "pm_api_token_secret must be the token *secret* value (UUID-like), without the 'user@realm!tokenname=' prefix."
  }
}

variable "pm_tls_insecure" {
  type        = bool
  default     = true
  description = "Skip TLS verification for Proxmox API"
}

variable "pm_target_node" {
  type        = string
  description = "Proxmox node name"
}

variable "pm_pool" {
  type        = string
  default     = ""
  description = "Proxmox pool name (optional). Leave empty to not assign a pool."
}

variable "template_name" {
  type        = string
  description = "Template VM ID to clone (numeric, e.g. 200). Stored as string for convenience."
}

variable "vm_storage" {
  type        = string
  default     = "local-lvm"
  description = "Storage for VM disks"
}

variable "pg_primary_storage" {
  type        = string
  default     = ""
  description = "Override disk datastore for pg-primary (optional). If empty, uses vm_storage."
}

variable "pg_standby_storage" {
  type        = string
  default     = ""
  description = "Override disk datastore for pg-standby (optional). If empty, uses vm_storage."
}

variable "app_storage" {
  type        = string
  default     = ""
  description = "Override disk datastore for app (optional). If empty, uses vm_storage."
}

variable "mgmt_jump_storage" {
  type        = string
  default     = ""
  description = "Override disk datastore for mgmt-jump (optional). If empty, uses vm_storage."
}

variable "cloudinit_storage" {
  type        = string
  default     = "local-lvm"
  description = "Storage for Cloud-Init drive"
}

variable "vm_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Network bridge name"
}

variable "ci_user" {
  type        = string
  default     = "ubuntu"
  description = "Cloud-Init default user"
}

variable "ci_ssh_public_key" {
  type        = string
  description = "SSH public key to inject via Cloud-Init"
}

variable "pg_primary_vmid" {
  type        = number
  default     = 201
  description = "VM ID for pg-primary"

  validation {
    condition     = var.pg_primary_vmid >= 100 && var.pg_primary_vmid <= 2147483647
    error_message = "pg_primary_vmid must be in the range 100-2147483647."
  }
}

variable "pg_standby_vmid" {
  type        = number
  default     = 202
  description = "VM ID for pg-standby"

  validation {
    condition     = var.pg_standby_vmid >= 100 && var.pg_standby_vmid <= 2147483647
    error_message = "pg_standby_vmid must be in the range 100-2147483647."
  }
}

variable "app_vmid" {
  type        = number
  default     = 203
  description = "VM ID for app"

  validation {
    condition     = var.app_vmid >= 100 && var.app_vmid <= 2147483647
    error_message = "app_vmid must be in the range 100-2147483647."
  }
}

variable "mgmt_jump_vmid" {
  type        = number
  default     = 204
  description = "VM ID for mgmt-jump"

  validation {
    condition     = var.mgmt_jump_vmid >= 100 && var.mgmt_jump_vmid <= 2147483647
    error_message = "mgmt_jump_vmid must be in the range 100-2147483647."
  }
}

variable "pg_primary_cores" {
  type        = number
  default     = 4
  description = "CPU cores for pg-primary"
}

variable "pg_primary_memory_mb" {
  type        = number
  default     = 8192
  description = "Memory MB for pg-primary"
}

variable "pg_primary_disk_gb" {
  type        = string
  default     = "50G"
  description = "Disk size for pg-primary"
}

variable "pg_primary_ipconfig0" {
  type        = string
  default     = "ip=dhcp"
  description = "Cloud-Init IP config for pg-primary"
}

variable "pg_standby_cores" {
  type        = number
  default     = 4
  description = "CPU cores for pg-standby"
}

variable "pg_standby_memory_mb" {
  type        = number
  default     = 8192
  description = "Memory MB for pg-standby"
}

variable "pg_standby_disk_gb" {
  type        = string
  default     = "50G"
  description = "Disk size for pg-standby"
}

variable "pg_standby_ipconfig0" {
  type        = string
  default     = "ip=dhcp"
  description = "Cloud-Init IP config for pg-standby"
}

variable "app_cores" {
  type        = number
  default     = 2
  description = "CPU cores for app"
}

variable "app_memory_mb" {
  type        = number
  default     = 4096
  description = "Memory MB for app"
}

variable "app_disk_gb" {
  type        = string
  default     = "30G"
  description = "Disk size for app"
}

variable "app_ipconfig0" {
  type        = string
  default     = "ip=dhcp"
  description = "Cloud-Init IP config for app"
}

variable "mgmt_jump_cores" {
  type        = number
  default     = 2
  description = "CPU cores for mgmt-jump"
}

variable "mgmt_jump_memory_mb" {
  type        = number
  default     = 2048
  description = "Memory MB for mgmt-jump"
}

variable "mgmt_jump_disk_gb" {
  type        = string
  default     = "20G"
  description = "Disk size for mgmt-jump"
}

variable "mgmt_jump_ipconfig0" {
  type        = string
  default     = "ip=dhcp"
  description = "Cloud-Init IP config for mgmt-jump"
}

# ---------------------------------------------------------------------------
# WireGuard gateway VM — wg-gw-onprem (ADR-006)
# Dedicated VM with single responsibility: WireGuard tunnel endpoint.
# Decouples tunnel from pg-primary so unexpected pg-primary downtime does not
# isolate the Azure DR VM.
#
# Deploy: set enable_wg_gateway = true in terraform.tfvars and run
#         terraform apply, then ansible-playbook wg_tunnel.yml -l wg_gateway
# Default: false — collocated WireGuard on pg-primary preserved (current state)
# ---------------------------------------------------------------------------

variable "enable_wg_gateway" {
  type        = bool
  description = "Provision a dedicated WireGuard gateway VM (wg-gw-onprem). See ADR-006."
  default     = false
}
