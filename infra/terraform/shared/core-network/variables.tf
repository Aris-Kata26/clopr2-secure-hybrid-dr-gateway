# shared/core-network — Interface Contract
# ==========================================
# Defines the required inputs for any cloud provider's DR network layer.
# This file is the logical interface — not an implementation.
#
# Implementations:
#   providers/azure/core-network/  → azurerm_virtual_network + NSG (live, via modules/network)
#   providers/aws/core-network/    → aws_vpc + security groups (scaffold)
#   providers/gcp/core-network/    → google_compute_network + firewall rules (scaffold)

variable "env_name" {
  type        = string
  description = "Logical environment name"
}

variable "region" {
  type        = string
  description = "Provider region for the network"
}

variable "address_space" {
  type        = string
  description = <<-EOT
    CIDR block for the DR VNet/VPC.
    Azure live: 10.20.0.0/16
    AWS planned: 10.21.0.0/16
    GCP planned: 10.22.0.0/16
  EOT
}

variable "db_subnet_cidr" {
  type        = string
  description = "CIDR for the DB subnet within the address space"
}

variable "app_subnet_cidr" {
  type        = string
  description = "CIDR for the app subnet (null if app is on-prem only)"
  default     = null
}

variable "wg_allowed_udp_port" {
  type        = number
  description = "UDP port to open for WireGuard inbound"
  default     = 51820
}

variable "wg_onprem_public_ip" {
  type        = string
  description = "On-prem public IP allowed through WireGuard NSG/security group rule"
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDR list allowed SSH inbound (bootstrap only — should be empty post-setup)"
  default     = []
}

variable "allowed_pg_cidrs" {
  type        = list(string)
  description = "CIDR list allowed PostgreSQL 5432 inbound (WireGuard tunnel IPs)"
  default     = ["10.200.0.0/24"]
}

variable "tags" {
  type        = map(string)
  description = "Resource tags / labels"
  default     = {}
}
