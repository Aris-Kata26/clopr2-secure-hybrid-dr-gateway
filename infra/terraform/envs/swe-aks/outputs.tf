output "aks_resource_group" {
  description = "Dedicated resource group for the AKS demo cluster."
  value       = azurerm_resource_group.aks.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "aks_location" {
  description = "Azure region where the AKS cluster is deployed."
  value       = azurerm_kubernetes_cluster.this.location
}

output "acr_login_server" {
  description = "Login server of the ACR used by this cluster."
  value       = data.azurerm_container_registry.acr.login_server
}

# aks_kube_config_raw intentionally removed: terraform output -json exposes
# sensitive values in plaintext regardless of sensitive=true.
# Retrieve credentials with: az aks get-credentials -g <rg> -n <cluster>
