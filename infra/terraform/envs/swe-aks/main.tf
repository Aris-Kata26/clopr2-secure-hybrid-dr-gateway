terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# AKS-dedicated resource group (new, swedencentral)
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "aks" {
  name     = var.aks_resource_group_name
  location = var.aks_location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Data source — existing ACR in germanywestcentral (NOT recreated)
# ---------------------------------------------------------------------------

# ACR lives in germanywestcentral; AKS (swedencentral) pulls from it cross-region
data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group_name
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  tags = {
    Team        = "BCLC24"
    Owner       = "KATAR711"
    Environment = var.environment
    Sprint      = "prototype-b"
    Region      = var.aks_location
  }
}

# ---------------------------------------------------------------------------
# AKS cluster — Free tier, 1 node, minimal config
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.aks_cluster_name
  location            = var.aks_location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = var.aks_cluster_name
  sku_tier            = "Free" # $0 control-plane cost

  default_node_pool {
    name            = "system"
    node_count      = 1
    vm_size         = var.aks_node_size # Standard_B2s_v2
    os_disk_size_gb = 30                # Minimum — saves vs default 128 GB
    os_disk_type    = "Managed"
  }

  identity {
    type = "SystemAssigned"
  }

  # No monitoring add-on, no policy add-on, no Azure CNI — keep sprint-minimal

  tags = local.tags

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# ---------------------------------------------------------------------------
# AcrPull — AKS kubelet identity → existing ACR (cross-region, supported)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
