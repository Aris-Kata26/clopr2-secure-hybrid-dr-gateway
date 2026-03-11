variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "dev"
}

variable "location" {
  type        = string
  description = "Azure region (EU only)."
  default     = "westeurope"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for baseline resources."
}

variable "vnet_name" {
  type        = string
  description = "Virtual network name."
}

variable "vnet_address_space" {
  type        = list(string)
  description = "VNet address space."
}

variable "aks_subnet_prefix" {
  type        = string
  description = "Address prefix for AKS subnet."
}

variable "mgmt_subnet_prefix" {
  type        = string
  description = "Address prefix for management subnet."
}

variable "loganalytics_name" {
  type        = string
  description = "Log Analytics workspace name."
}

variable "keyvault_name" {
  type        = string
  description = "Key Vault name (must be globally unique)."
}

variable "pg_dr_vm_name" {
  type        = string
  description = "PostgreSQL DR VM name."
  default     = "vm-pg-dr"
}

variable "pg_dr_vm_size" {
  type        = string
  description = "PostgreSQL DR VM size (cost-aware)."
  default     = "Standard_B2s"
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

variable "pg_dr_subnet_name" {
  type        = string
  description = "Subnet name where the PostgreSQL DR VM NIC is attached."
  default     = "mgmt-subnet"
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

variable "pg_replication_password" {
  type        = string
  description = "Replication password stored in Key Vault for DR setup."
  sensitive   = true
}

variable "enable_auto_shutdown" {
  type        = bool
  description = "Enable auto-shutdown schedule for cost control."
  default     = false
}

variable "auto_shutdown_time" {
  type        = string
  description = "Auto-shutdown time in HHmm (24h)."
  default     = "2300"
}

variable "auto_shutdown_timezone" {
  type        = string
  description = "Auto-shutdown timezone (IANA/Windows TZ)."
  default     = "UTC"
}

variable "enable_backup" {
  type        = bool
  description = "Enable Azure Backup for the PostgreSQL DR VM."
  default     = false
}

# ---------------------------------------------------------------------------
# Prototype B — ACR + AKS
# ---------------------------------------------------------------------------

variable "acr_name" {
  type        = string
  description = "Container Registry name (alphanumeric, globally unique)."
  default     = "acrb2clckatargwc"
}

variable "aks_cluster_name" {
  type        = string
  description = "AKS cluster name."
  default     = "aks-b2clc-katar-gwc"
}

variable "aks_node_size" {
  type        = string
  description = "AKS system node pool VM size (cost-aware)."
  default     = "Standard_B2s"
}

variable "backup_vault_name" {
  type        = string
  description = "Recovery Services vault name for VM backups."
  default     = "rsv-clopr2-dr"
}

variable "backup_policy_name" {
  type        = string
  description = "Backup policy name for the PostgreSQL DR VM."
  default     = "policy-pg-dr"
}
