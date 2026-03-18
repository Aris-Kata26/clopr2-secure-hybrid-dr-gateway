variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "dev"
}

variable "location" {
  type        = string
  description = "Azure region (EU only)."
  default     = "francecentral"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for DR resources."
}

variable "vnet_name" {
  type        = string
  description = "Virtual network name."
}

variable "vnet_address_space" {
  type        = list(string)
  description = "VNet address space."
}

variable "dr_subnet_name" {
  type        = string
  description = "Subnet name for DR VM."
}

variable "dr_subnet_prefix" {
  type        = string
  description = "Subnet CIDR for DR VM."
}

variable "nsg_name" {
  type        = string
  description = "Network security group name."
}

variable "pg_dr_vm_name" {
  type        = string
  description = "PostgreSQL DR VM name."
  default     = "vm-pg-dr-fce"
}

variable "pg_dr_vm_size" {
  type        = string
  description = "PostgreSQL DR VM size (cost-aware)."
  default     = "Standard_B2ats_v2"
}

variable "pg_dr_admin_username" {
  type        = string
  description = "Admin username for the PostgreSQL DR VM."
  default     = "azureuser"
}

variable "pg_dr_admin_ssh_public_key" {
  type        = string
  description = "SSH public key for the PostgreSQL DR VM admin user."
}

variable "pg_dr_allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH to the PostgreSQL DR VM."
  default     = []
}

variable "pg_dr_onprem_cidrs" {
  type        = list(string)
  description = "CIDR blocks for on-prem/VPN networks allowed to reach PostgreSQL (5432)."
  default     = []
}

variable "pg_dr_bootstrap_ssh_cidrs" {
  type        = list(string)
  description = "TEMPORARY: admin public IP /32 for initial Ansible bootstrap before WireGuard tunnel exists. Set to [] and re-apply once WireGuard is verified to destroy the rule."
  default     = []
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB."
  default     = 30
}

variable "keyvault_name" {
  type        = string
  description = "Key Vault name (must be globally unique)."
}

variable "pg_replication_password" {
  type        = string
  description = "Replication password stored in Key Vault for DR setup."
  sensitive   = true
}

variable "loganalytics_name" {
  type        = string
  description = "Log Analytics workspace name."
}

variable "enable_auto_shutdown" {
  type        = bool
  description = "Enable auto-shutdown schedule for cost control."
  default     = true
}

variable "auto_shutdown_time" {
  type        = string
  description = "Auto-shutdown time in HHmm (24h)."
  default     = "2300"
}

variable "auto_shutdown_timezone" {
  type        = string
  description = "Auto-shutdown timezone (Windows TZ)."
  default     = "W. Europe Standard Time"
}

variable "budget_name" {
  type        = string
  description = "Budget name for DR resource group."
  default     = "budget-dr-fce"
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget amount in EUR."
  default     = 15
}

variable "budget_contact_emails" {
  type        = list(string)
  description = "Notification emails for budget alerts."
  default     = []
}

variable "budget_start_date" {
  type        = string
  description = "Budget start date (RFC3339)."
  default     = "2026-03-01T00:00:00Z"
}

variable "enable_vpn_gateway" {
  type        = bool
  description = "Enable VPN gateway resources (scaffolding only)."
  default     = false
}

# ---------------------------------------------------------------------------
# WireGuard tunnel
# ---------------------------------------------------------------------------

variable "wg_onprem_public_ip" {
  type        = string
  description = "On-prem public IP (NAT exit) used for the WireGuard NSG rule (UDP port)."
}

variable "wg_listen_port" {
  type        = number
  description = "WireGuard listen port on the DR VM."
  default     = 51820
}

variable "wg_azure_tunnel_ip" {
  type        = string
  description = "WireGuard tunnel IP assigned to the Azure DR VM (e.g. 10.200.0.2)."
  default     = "10.200.0.2"
}

variable "wg_onprem_tunnel_ip" {
  type        = string
  description = "WireGuard tunnel IP assigned to on-prem pg-primary (e.g. 10.200.0.1)."
  default     = "10.200.0.1"
}

variable "wg_tunnel_prefix" {
  type        = number
  description = "Prefix length of the WireGuard /30 tunnel subnet."
  default     = 30
}

variable "wg_onprem_pubkey" {
  type        = string
  description = "WireGuard public key of on-prem pg-primary peer. Generate with scripts/wg-keygen.sh."
}

variable "wg_azure_privkey" {
  type        = string
  sensitive   = true
  description = "WireGuard private key for the Azure DR VM. Set via TF_VAR_wg_azure_privkey. Generate with scripts/wg-keygen.sh."
}

variable "gateway_subnet_prefix" {
  type        = string
  description = "GatewaySubnet CIDR."
  default     = "10.20.255.0/27"
}

variable "vpn_gateway_name" {
  type        = string
  description = "VPN gateway name."
  default     = "vpngw-clopr2-dr-fce"
}

variable "vpn_public_ip_name" {
  type        = string
  description = "VPN gateway public IP name."
  default     = "pip-vpngw-dr-fce"
}

variable "vpn_gateway_sku" {
  type        = string
  description = "VPN gateway SKU."
  default     = "VpnGw1"
}

variable "onprem_public_ip" {
  type        = string
  description = "On-prem VPN device public IP."
  default     = ""
}

variable "onprem_address_space" {
  type        = list(string)
  description = "On-prem address space."
  default     = ["10.0.0.0/16"]
}

variable "vpn_shared_key" {
  type        = string
  description = "Pre-shared key for VPN connection."
  sensitive   = true
  default     = ""
}

variable "local_network_gateway_name" {
  type        = string
  description = "Local network gateway name."
  default     = "lng-clopr2-onprem"
}

variable "vpn_connection_name" {
  type        = string
  description = "VPN connection name."
  default     = "conn-clopr2-dr-fce"
}

variable "ops_alert_email" {
  type        = string
  description = "Email address for operational alert notifications (action group)."
  default     = "katar711@school.lu"
}

# ---------------------------------------------------------------------------
# Azure DR App VM — separation of app and DB roles
# ---------------------------------------------------------------------------

variable "enable_app_dr_vm" {
  type        = bool
  description = "Provision a separate Azure app VM (vm-app-dr-fce) for the FastAPI container during full-site failover. When false, the app runs on the DB VM (legacy collocated mode)."
  default     = false
}

variable "app_dr_vm_name" {
  type        = string
  description = "Name for the Azure DR app VM."
  default     = "vm-app-dr-fce"
}

variable "app_dr_vm_size" {
  type        = string
  description = "VM SKU for the Azure DR app VM. B1s is sufficient (Docker only, no PostgreSQL)."
  default     = "Standard_B1s"
}

variable "app_dr_vm_private_ip" {
  type        = string
  description = "Static private IP for the app VM within dr-mgmt-subnet (10.20.2.0/24). Must not conflict with the DB VM's dynamically assigned IP."
  default     = "10.20.2.20"
}
