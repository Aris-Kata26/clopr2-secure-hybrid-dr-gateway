variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL. For bpg/proxmox this should be like https://10.0.10.161:8006/ (no /api2/json). This env will also accept the /api2/json suffix and strip it."
}

variable "pm_api_token_id" {
  type        = string
  description = "Proxmox API token ID (user@realm!token)"
}

variable "pm_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret"
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
  description = "Proxmox pool name"
}

variable "template_name" {
  type        = string
  description = "Template VM ID to clone (numeric, e.g. 200). Stored as string for convenience."
}

variable "vm_storage" {
  type        = string
  default     = "Slightly-Big-Data"
  description = "Storage for VM disks"
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
}

variable "pg_standby_vmid" {
  type        = number
  default     = 202
  description = "VM ID for pg-standby"
}

variable "app_vmid" {
  type        = number
  default     = 203
  description = "VM ID for app"
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
