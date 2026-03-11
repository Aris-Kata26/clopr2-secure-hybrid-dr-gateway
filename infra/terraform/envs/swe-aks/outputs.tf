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

output "aks_kube_config_raw" {
  description = "Raw kubeconfig for kubectl access. Sensitive."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}
