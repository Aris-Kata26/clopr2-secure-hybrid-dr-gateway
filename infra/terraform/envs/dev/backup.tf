# =============================================================================
# envs/dev/backup.tf — pgBackRest Backup Storage
# CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24
#
# Implemented: 2026-03-18 (architecture hardening phase)
#
# WHAT THIS PROVISIONS:
#   Azure Blob Storage account and container for pgBackRest PostgreSQL backups.
#   pgBackRest on pg-primary archives WAL and stores full backups here.
#
# STORAGE ACCOUNT: clopr2backupkatar (Standard LRS, germanywestcentral)
# CONTAINER:       pgbackrest
# CONFIGURED BY:   infra/ansible/roles/pgbackrest/
#
# KEY USAGE PATTERN:
#   The storage account key is passed to pgbackrest.conf as repo1-azure-key.
#   Key retrieval: az storage account keys list --account-name clopr2backupkatar
#   The key is stored only on pg-primary in /etc/pgbackrest/pgbackrest.conf
#   (mode 640, owned root:postgres).
#
# NOTE: This file documents the as-built storage resources. The storage
# account was created manually via Azure CLI on 2026-03-18 during initial
# pgBackRest setup. Future re-deployments use terraform apply.
# =============================================================================

resource "azurerm_storage_account" "backup" {
  name                = "clopr2backupkatar"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "pgbackrest" {
  name                  = "pgbackrest"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Output — backup storage account name for Ansible variable injection
# ---------------------------------------------------------------------------
output "backup_storage_account_name" {
  value       = azurerm_storage_account.backup.name
  description = "Storage account name for pgBackRest (pass to Ansible as repo1_azure_account)."
}
