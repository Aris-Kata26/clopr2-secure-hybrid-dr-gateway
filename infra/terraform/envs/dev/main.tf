terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
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
