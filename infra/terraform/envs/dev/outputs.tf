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

output "pg_dr_vm_id" {
  description = "PostgreSQL DR VM ID."
  value       = azurerm_linux_virtual_machine.pg_dr.id
}

output "pg_dr_nic_id" {
  description = "PostgreSQL DR VM NIC ID."
  value       = azurerm_network_interface.pg_dr.id
}

output "pg_dr_private_ip" {
  description = "PostgreSQL DR VM private IP address."
  value       = azurerm_network_interface.pg_dr.private_ip_address
}

output "acr_login_server" {
  description = "ACR login server URL."
  value       = azurerm_container_registry.this.login_server
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "aks_kube_config_raw" {
  description = "Raw kubeconfig (sensitive)."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}
