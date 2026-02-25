variable "endpoint" {
  description = "Proxmox API endpoint (DO NOT include /api2/json). Example: https://10.0.10.161:8006/"
  type        = string
  default     = "https://10.0.10.161:8006/"

  validation {
    condition     = length(var.endpoint) > 0 && can(regex("^https?://", var.endpoint)) && !can(regex("/api2/json/?$", var.endpoint))
    error_message = "endpoint must be a full URL like https://10.0.10.161:8006/ and must NOT include /api2/json."
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
