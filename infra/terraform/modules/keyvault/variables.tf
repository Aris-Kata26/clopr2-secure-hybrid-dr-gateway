variable "name" {
  type        = string
  description = "Key Vault name."
}

variable "location" {
  type        = string
  description = "Azure region for the Key Vault."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name."
}

variable "tenant_id" {
  type        = string
  description = "Tenant ID for the Key Vault."
}

variable "sku_name" {
  type        = string
  description = "Key Vault SKU."
  default     = "standard"
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Soft delete retention in days."
  default     = 7
}

variable "rbac_authorization_enabled" {
  type        = bool
  description = "Enable RBAC authorization for Key Vault."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
