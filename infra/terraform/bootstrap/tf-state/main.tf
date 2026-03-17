# =============================================================================
# infra/terraform/bootstrap/tf-state/main.tf
# Terraform Remote State Backend — Bootstrap Documentation
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# PURPOSE:
#   Documents the Azure Storage Account used as remote state backend for all
#   CLOPR2 Terraform environments. This environment was bootstrapped via az CLI
#   (see docs/03-operations/tf-state-governance.md) to avoid the chicken-and-egg
#   problem of a state backend that needs state.
#
#   This file serves as code-as-documentation. It can also be used to reproduce
#   the backend infrastructure from scratch (terraform apply with local backend).
#
# BOOTSTRAP DATE: 2026-03-17
# BOOTSTRAP METHOD: az CLI (see governance doc for exact commands)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  # This bootstrap environment intentionally uses local state.
  # The state file is committed to git since it contains no sensitive data —
  # only a storage account and resource group definition.
  backend "local" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# ---------------------------------------------------------------------------
# Dedicated resource group for Terraform state
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-clopr2-tfstate"
  location = "germanywestcentral"

  tags = {
    Team        = "BCLC24"
    Owner       = "KATAR711"
    Purpose     = "terraform-state"
    Environment = "global"
  }
}

# ---------------------------------------------------------------------------
# Storage Account — CLOPR2 Terraform remote state
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "tfstate" {
  name                     = "clopr2tfstatekatar"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Security baseline
  min_tls_version           = "TLS1_2"
  https_traffic_only_enabled = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true # State version history + rollback
  }

  tags = {
    Team        = "BCLC24"
    Owner       = "KATAR711"
    Purpose     = "terraform-state"
    Environment = "global"
  }
}

# ---------------------------------------------------------------------------
# Per-environment containers (one per Terraform environment)
# Separation ensures blast radius is scoped to one environment per operation.
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "tfstate" {
  for_each = toset(["onprem", "dr-fce", "dev", "swe-aks"])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}
