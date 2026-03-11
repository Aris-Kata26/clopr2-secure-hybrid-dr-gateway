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

data "azurerm_client_config" "current" {}

locals {
  tags = {
    Team        = "BCLC24"
    Owner       = "KATAR711"
    Environment = var.environment
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

module "network" {
  source              = "../../modules/network"
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = local.tags

  subnets = {
    "aks-subnet" = {
      address_prefixes = [var.aks_subnet_prefix]
      nsg_name         = "${var.vnet_name}-aks-nsg"
    }
    "mgmt-subnet" = {
      address_prefixes = [var.mgmt_subnet_prefix]
      nsg_name         = "${var.vnet_name}-mgmt-nsg"
    }
  }
}

module "loganalytics" {
  source              = "../../modules/loganalytics"
  name                = var.loganalytics_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "keyvault" {
  source              = "../../modules/keyvault"
  name                = var.keyvault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

resource "azurerm_network_interface" "pg_dr" {
  name                = "${var.pg_dr_vm_name}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = module.network.subnet_ids[var.pg_dr_subnet_name]
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.tags
}

resource "azurerm_network_security_rule" "pg_dr_ssh" {
  count                       = length(var.pg_dr_allowed_ssh_cidrs) > 0 ? 1 : 0
  name                        = "allow-ssh"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.pg_dr_allowed_ssh_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = basename(module.network.nsg_ids[var.pg_dr_subnet_name])
}

resource "azurerm_network_security_rule" "pg_dr_postgres" {
  count                       = length(var.pg_dr_onprem_cidrs) > 0 ? 1 : 0
  name                        = "allow-postgres"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5432"
  source_address_prefixes     = var.pg_dr_onprem_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = basename(module.network.nsg_ids[var.pg_dr_subnet_name])
}

resource "azurerm_linux_virtual_machine" "pg_dr" {
  name                = var.pg_dr_vm_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.pg_dr_vm_size
  admin_username      = var.pg_dr_admin_username
  network_interface_ids = [
    azurerm_network_interface.pg_dr.id,
  ]

  admin_ssh_key {
    username   = var.pg_dr_admin_username
    public_key = var.pg_dr_admin_ssh_public_key
  }

  disable_password_authentication = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_key_vault_secret" "pg_replication_password" {
  name         = "pg-replication-password"
  value        = var.pg_replication_password
  key_vault_id = module.keyvault.key_vault_id
  content_type = "text/plain"
}

resource "azurerm_role_assignment" "pg_dr_kv_secrets_user" {
  scope                = module.keyvault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.pg_dr.identity[0].principal_id
}

resource "azurerm_virtual_machine_extension" "pg_dr_ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.pg_dr.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_rule" "pg_dr" {
  name                = "dcr-${var.pg_dr_vm_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  destinations {
    log_analytics {
      workspace_resource_id = module.loganalytics.workspace_id
      name                  = "la"
    }
  }

  data_sources {
    syslog {
      name           = "syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["*"]
      log_levels     = ["*"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["la"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "pg_dr" {
  name                    = "dcr-${var.pg_dr_vm_name}"
  target_resource_id      = azurerm_linux_virtual_machine.pg_dr.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.pg_dr.id
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "pg_dr" {
  count              = var.enable_auto_shutdown ? 1 : 0
  virtual_machine_id = azurerm_linux_virtual_machine.pg_dr.id
  location           = var.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }
}

resource "azurerm_recovery_services_vault" "pg_dr" {
  count               = var.enable_backup ? 1 : 0
  name                = var.backup_vault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Prototype B — ACR + AKS (demo-minimal, cost-aware)
# ---------------------------------------------------------------------------

resource "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = local.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.aks_cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.aks_cluster_name

  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = var.aks_node_size
    vnet_subnet_id = module.network.subnet_ids["aks-subnet"]
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

resource "azurerm_backup_policy_vm" "pg_dr" {
  count               = var.enable_backup ? 1 : 0
  name                = var.backup_policy_name
  resource_group_name = azurerm_resource_group.this.name
  recovery_vault_name = azurerm_recovery_services_vault.pg_dr[0].name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 7
  }
}

resource "azurerm_backup_protected_vm" "pg_dr" {
  count               = var.enable_backup ? 1 : 0
  resource_group_name = azurerm_resource_group.this.name
  recovery_vault_name = azurerm_recovery_services_vault.pg_dr[0].name
  source_vm_id        = azurerm_linux_virtual_machine.pg_dr.id
  backup_policy_id    = azurerm_backup_policy_vm.pg_dr[0].id
}
