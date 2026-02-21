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
