# =============================================================================
# envs/dr-fce/backend.tf — Remote state backend (Azure Storage)
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# Backend: Azure Blob Storage
#   Resource Group : rg-clopr2-tfstate
#   Storage Account: clopr2tfstatekatar (germanywestcentral, Standard_LRS)
#   Container      : dr-fce
#   State Key      : terraform.tfstate
#
# Authentication: Azure AD (az login)
#   Requires Storage Blob Data Contributor on the dr-fce container.
#
# State locking: Automatic via Azure Blob lease (built-in to azurerm backend).
# State versioning: Enabled on storage account — supports rollback.
#
# Migration: 2026-03-17 | Evidence: docs/05-evidence/tf-state-migration/
# Governance: docs/03-operations/tf-state-governance.md
#
# ROLLBACK:
#   1. Copy backup from docs/05-evidence/tf-state-migration/backups/ here
#   2. Replace this file with: terraform { backend "local" {} }
#   3. Run: terraform init -reconfigure
# =============================================================================

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-clopr2-tfstate"
    storage_account_name = "clopr2tfstatekatar"
    container_name       = "dr-fce"
    key                  = "terraform.tfstate"
    use_azuread_auth     = true
  }
}
