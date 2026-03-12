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

resource "azurerm_resource_group" "dr" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "dr" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_network_security_group" "dr" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
  tags                = local.tags
}

resource "azurerm_subnet" "dr_mgmt" {
  name                              = var.dr_subnet_name
  resource_group_name               = azurerm_resource_group.dr.name
  virtual_network_name              = azurerm_virtual_network.dr.name
  address_prefixes                  = [var.dr_subnet_prefix]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet_network_security_group_association" "dr_mgmt" {
  subnet_id                 = azurerm_subnet.dr_mgmt.id
  network_security_group_id = azurerm_network_security_group.dr.id
}

resource "azurerm_network_security_rule" "dr_ssh" {
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
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.dr.name
}

resource "azurerm_network_security_rule" "dr_postgres" {
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
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.dr.name
}

# TEMPORARY bootstrap SSH rule — TCP 22 from admin public IP only.
# Required to run the initial Ansible WireGuard playbook against the Azure VM
# before the WireGuard tunnel exists. Remove after tunnel is verified:
#   1. Set pg_dr_bootstrap_ssh_cidrs = [] in terraform.tfvars
#   2. terraform apply   ← destroys this rule (count goes to 0)
#   3. SSH is then only reachable via WireGuard ProxyJump (10.200.0.1/32)
resource "azurerm_network_security_rule" "dr_ssh_bootstrap" {
  count                       = length(var.pg_dr_bootstrap_ssh_cidrs) > 0 ? 1 : 0
  name                        = "allow-ssh-bootstrap-TEMPORARY"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.pg_dr_bootstrap_ssh_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.dr.name
}

# WireGuard tunnel endpoint — UDP 51820 from on-prem public IP only.
# SSH (22) is intentionally NOT open to the internet; it is only reachable
# via the WireGuard tunnel (source 10.200.0.1/32 = pg-primary tunnel IP).
resource "azurerm_network_security_rule" "dr_wireguard" {
  name                        = "allow-wireguard"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.wg_listen_port)
  source_address_prefix       = "${var.wg_onprem_public_ip}/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dr.name
  network_security_group_name = azurerm_network_security_group.dr.name
}

# Public IP used exclusively as WireGuard endpoint.
# SSH is NOT reachable on this IP (NSG blocks port 22 from internet).
resource "azurerm_public_ip" "pg_dr_wg" {
  name                = "${var.pg_dr_vm_name}-wg-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "pg_dr" {
  name                = "${var.pg_dr_vm_name}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.dr_mgmt.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pg_dr_wg.id
  }

  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "pg_dr" {
  name                = var.pg_dr_vm_name
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
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
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # cloud-init configures WireGuard on first boot so that the tunnel is
  # available before any Ansible run. See cloud_init.tftpl for the script.
  # NOTE: wg_azure_privkey will appear in terraform.tfstate — treat that file
  # as sensitive and never commit it.
  custom_data = base64encode(templatefile("${path.module}/cloud_init.tftpl", {
    wg_azure_privkey    = var.wg_azure_privkey
    wg_azure_tunnel_ip  = var.wg_azure_tunnel_ip
    wg_tunnel_prefix    = var.wg_tunnel_prefix
    wg_listen_port      = var.wg_listen_port
    wg_onprem_pubkey    = var.wg_onprem_pubkey
    wg_onprem_tunnel_ip = var.wg_onprem_tunnel_ip
  }))

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_key_vault" "dr" {
  name                          = var.keyvault_name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.dr.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  rbac_authorization_enabled    = true
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_key_vault_secret" "pg_replication_password" {
  name         = "pg-replication-password"
  value        = var.pg_replication_password
  key_vault_id = azurerm_key_vault.dr.id
  content_type = "text/plain"
}

resource "azurerm_role_assignment" "pg_dr_kv_secrets_user" {
  scope                = azurerm_key_vault.dr.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.pg_dr.identity[0].principal_id
}

resource "azurerm_log_analytics_workspace" "dr" {
  name                = var.loganalytics_name
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
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
  resource_group_name = azurerm_resource_group.dr.name

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.dr.id
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

resource "azurerm_consumption_budget_resource_group" "dr" {
  name              = var.budget_name
  resource_group_id = azurerm_resource_group.dr.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    contact_emails = var.budget_contact_emails
  }
}

resource "azurerm_subnet" "gateway" {
  count                = var.enable_vpn_gateway ? 1 : 0
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

resource "azurerm_public_ip" "vpn" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = var.vpn_public_ip_name
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = var.vpn_gateway_name
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  sku                 = var.vpn_gateway_sku

  ip_configuration {
    name                          = "vpngw-ipconfig"
    public_ip_address_id          = azurerm_public_ip.vpn[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }

  tags = local.tags
}

resource "azurerm_local_network_gateway" "onprem" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = var.local_network_gateway_name
  location            = var.location
  resource_group_name = azurerm_resource_group.dr.name
  gateway_address     = var.onprem_public_ip
  address_space       = var.onprem_address_space
  tags                = local.tags
}

resource "azurerm_virtual_network_gateway_connection" "vpn" {
  count                      = var.enable_vpn_gateway ? 1 : 0
  name                       = var.vpn_connection_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.dr.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem[0].id
  shared_key                 = var.vpn_shared_key
  tags                       = local.tags
}
