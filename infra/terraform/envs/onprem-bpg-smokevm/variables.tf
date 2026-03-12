variable "endpoint" {
  description = "Proxmox API endpoint (DO NOT include /api2/json). Example: https://10.0.10.161:8006/"
  type        = string

  validation {
    condition     = length(var.endpoint) > 0 && can(regex("^https?://", var.endpoint))
    error_message = "endpoint must be a full URL like https://10.0.10.161:8006/."
  }
}

variable "api_token" {
  description = "API token in bpg format: user@realm!tokenname=SECRET"
  type        = string
  sensitive   = true
}

variable "insecure" {
  description = "Set true when using self-signed TLS certs"
  type        = bool
  default     = true
}

variable "node_name" {
  description = "Target Proxmox node name"
  type        = string
}

variable "pool_id" {
  description = "Target Proxmox pool name"
  type        = string
}

variable "vm_id" {
  description = "VMID to allocate for the smoke test"
  type        = number
  default     = 210
}

variable "name" {
  description = "VM name"
  type        = string
  default     = "smoke-test-vm"
}

variable "vm_storage" {
  description = "Storage for the VM disk"
  type        = string
  default     = "Slightly-Big-Data"
}

variable "vm_bridge" {
  description = "Network bridge name"
  type        = string
  default     = "vmbr0"
}

variable "cores" {
  description = "CPU cores"
  type        = number
  default     = 1
}

variable "memory_mb" {
  description = "Memory (MB)"
  type        = number
  default     = 1024
}
