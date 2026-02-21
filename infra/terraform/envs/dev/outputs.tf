output "resource_group_name" {
  description = "Resource group name."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "VNet ID."
  value       = module.network.vnet_id
}

output "subnet_ids" {
  description = "Subnet IDs by name."
  value       = module.network.subnet_ids
}

output "nsg_ids" {
  description = "NSG IDs by subnet."
  value       = module.network.nsg_ids
}

output "loganalytics_workspace_id" {
  description = "Log Analytics workspace ID."
  value       = module.loganalytics.workspace_id
}

output "key_vault_id" {
  description = "Key Vault ID."
  value       = module.keyvault.key_vault_id
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.keyvault.key_vault_uri
}
