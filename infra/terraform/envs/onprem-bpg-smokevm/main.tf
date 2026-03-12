terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.97"
    }
  }
}

locals {
  endpoint_no_fragment = split("#", var.endpoint)[0]
  endpoint_no_query    = split("?", local.endpoint_no_fragment)[0]
  normalized_endpoint  = endswith(local.endpoint_no_query, "/") ? local.endpoint_no_query : "${local.endpoint_no_query}/"
}

provider "proxmox" {
  endpoint  = local.normalized_endpoint
  api_token = var.api_token
  insecure  = var.insecure
}

# Creates a minimal VM to validate RBAC for VM allocation.
# No clone/template is used here.
resource "proxmox_virtual_environment_vm" "smoke" {
  name      = var.name
  node_name = var.node_name
  pool_id   = var.pool_id
  vm_id     = var.vm_id

  started = false
  on_boot = false

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = 8
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}
