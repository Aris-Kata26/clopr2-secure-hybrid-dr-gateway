output "storage_account_name" {
  description = "Storage account name — use in backend.tf for all environments"
  value       = azurerm_storage_account.tfstate.name
}

output "resource_group_name" {
  description = "Resource group containing the TF state storage account"
  value       = azurerm_resource_group.tfstate.name
}

output "backend_config_snippet" {
  description = "Backend configuration snippet for use in each environment"
  value = <<-EOT
    terraform {
      backend "azurerm" {
        resource_group_name  = "${azurerm_resource_group.tfstate.name}"
        storage_account_name = "${azurerm_storage_account.tfstate.name}"
        container_name       = "<env-name>"   # onprem | dr-fce | dev | swe-aks
        key                  = "terraform.tfstate"
        use_azuread_auth     = true
      }
    }
  EOT
}
