output "resource_group_name" {
  description = "DR resource group name."
  value       = azurerm_resource_group.dr.name
}

output "vnet_id" {
  description = "DR VNet ID."
  value       = azurerm_virtual_network.dr.id
}

output "dr_subnet_id" {
  description = "DR subnet ID."
  value       = azurerm_subnet.dr_mgmt.id
}

output "nsg_id" {
  description = "DR NSG ID."
  value       = azurerm_network_security_group.dr.id
}

output "pg_dr_vm_id" {
  description = "PostgreSQL DR VM ID."
  value       = azurerm_linux_virtual_machine.pg_dr.id
}

output "pg_dr_private_ip" {
  description = "PostgreSQL DR VM private IP address."
  value       = azurerm_network_interface.pg_dr.private_ip_address
}

output "key_vault_name" {
  description = "DR Key Vault name."
  value       = azurerm_key_vault.dr.name
}

output "key_vault_uri" {
  description = "DR Key Vault URI."
  value       = azurerm_key_vault.dr.vault_uri
}

output "loganalytics_workspace_name" {
  description = "DR Log Analytics workspace name."
  value       = azurerm_log_analytics_workspace.dr.name
}

output "vpn_gateway_id" {
  description = "VPN gateway ID (if enabled)."
  value       = try(azurerm_virtual_network_gateway.vpn[0].id, null)
}

output "vpn_public_ip" {
  description = "VPN public IP (if enabled)."
  value       = try(azurerm_public_ip.vpn[0].ip_address, null)
}

output "pg_dr_wg_public_ip" {
  description = "Public IP of the DR VM used as WireGuard endpoint. Set as wg_peer_endpoint in pg-primary group_vars after apply."
  value       = azurerm_public_ip.pg_dr_wg.ip_address
}
