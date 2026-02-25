terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.97"
    }
  }
}

provider "proxmox" {
  endpoint  = var.endpoint
  api_token = var.api_token
  insecure  = var.insecure
}

data "proxmox_virtual_environment_nodes" "nodes" {}

data "proxmox_virtual_environment_version" "version" {}
