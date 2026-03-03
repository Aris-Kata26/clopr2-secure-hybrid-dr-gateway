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
  # Users sometimes paste a Proxmox *UI* URL (includes # fragments). Strip query/fragment first.
  pm_api_url_no_fragment = split("#", var.pm_api_url)[0]
  pm_api_url_no_query    = split("?", local.pm_api_url_no_fragment)[0]

  # bpg provider endpoint must NOT include /api2/json
  endpoint_raw = trimsuffix(trimsuffix(local.pm_api_url_no_query, "/api2/json/"), "/api2/json")
  endpoint     = endswith(local.endpoint_raw, "/") ? local.endpoint_raw : "${local.endpoint_raw}/"

  # bpg provider token format: user@realm!tokenid=SECRET
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"

  pg_primary_datastore_id = var.pg_primary_storage != "" ? var.pg_primary_storage : var.vm_storage
  pg_standby_datastore_id = var.pg_standby_storage != "" ? var.pg_standby_storage : var.vm_storage
  app_datastore_id        = var.app_storage != "" ? var.app_storage : var.vm_storage
  mgmt_jump_datastore_id  = var.mgmt_jump_storage != "" ? var.mgmt_jump_storage : var.vm_storage

  pg_primary_disk_size_gb = tonumber(regex("^[0-9]+", var.pg_primary_disk_gb))
  pg_standby_disk_size_gb = tonumber(regex("^[0-9]+", var.pg_standby_disk_gb))
  app_disk_size_gb        = tonumber(regex("^[0-9]+", var.app_disk_gb))
  mgmt_jump_disk_size_gb  = tonumber(regex("^[0-9]+", var.mgmt_jump_disk_gb))

  pg_primary_ipv4_address = strcontains(var.pg_primary_ipconfig0, "dhcp") ? "dhcp" : regex("ip=([^,]+)", var.pg_primary_ipconfig0)[0]
  pg_primary_ipv4_gateway = strcontains(var.pg_primary_ipconfig0, "dhcp") ? null : regex("gw=([^,]+)", var.pg_primary_ipconfig0)[0]

  pg_standby_ipv4_address = strcontains(var.pg_standby_ipconfig0, "dhcp") ? "dhcp" : regex("ip=([^,]+)", var.pg_standby_ipconfig0)[0]
  pg_standby_ipv4_gateway = strcontains(var.pg_standby_ipconfig0, "dhcp") ? null : regex("gw=([^,]+)", var.pg_standby_ipconfig0)[0]

  app_ipv4_address = strcontains(var.app_ipconfig0, "dhcp") ? "dhcp" : regex("ip=([^,]+)", var.app_ipconfig0)[0]
  app_ipv4_gateway = strcontains(var.app_ipconfig0, "dhcp") ? null : regex("gw=([^,]+)", var.app_ipconfig0)[0]

  mgmt_jump_ipv4_address = strcontains(var.mgmt_jump_ipconfig0, "dhcp") ? "dhcp" : regex("ip=([^,]+)", var.mgmt_jump_ipconfig0)[0]
  mgmt_jump_ipv4_gateway = strcontains(var.mgmt_jump_ipconfig0, "dhcp") ? null : regex("gw=([^,]+)", var.mgmt_jump_ipconfig0)[0]
}

provider "proxmox" {
  endpoint  = local.endpoint
  api_token = local.api_token
  insecure  = var.pm_tls_insecure
}

resource "proxmox_virtual_environment_vm" "pg_primary" {
  name      = "pg-primary"
  node_name = var.pm_target_node
  pool_id   = var.pm_pool != "" ? var.pm_pool : null
  vm_id     = var.pg_primary_vmid

  clone {
    vm_id = tonumber(var.template_name)
    full  = true
  }

  agent {
    enabled = true
  }

  on_boot = true

  cpu {
    cores = var.pg_primary_cores
  }

  memory {
    dedicated = var.pg_primary_memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = local.pg_primary_datastore_id
    interface    = "scsi0"
    size         = local.pg_primary_disk_size_gb
    iothread     = true
  }

  initialization {
    datastore_id = var.cloudinit_storage

    ip_config {
      ipv4 {
        address = local.pg_primary_ipv4_address
        gateway = local.pg_primary_ipv4_gateway
      }
    }

    user_account {
      username = var.ci_user
      keys     = [trimspace(var.ci_ssh_public_key)]
    }
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "pg_standby" {
  name      = "pg-standby"
  node_name = var.pm_target_node
  pool_id   = var.pm_pool != "" ? var.pm_pool : null
  vm_id     = var.pg_standby_vmid

  lifecycle {
    ignore_changes = [clone]
  }

  clone {
    vm_id = tonumber(var.template_name)
    full  = true
  }

  agent {
    enabled = true
  }

  on_boot = true

  cpu {
    cores = var.pg_standby_cores
  }

  memory {
    dedicated = var.pg_standby_memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = local.pg_standby_datastore_id
    interface    = "scsi0"
    size         = local.pg_standby_disk_size_gb
    iothread     = true
  }

  initialization {
    datastore_id = var.cloudinit_storage

    ip_config {
      ipv4 {
        address = local.pg_standby_ipv4_address
        gateway = local.pg_standby_ipv4_gateway
      }
    }

    user_account {
      username = var.ci_user
      keys     = [trimspace(var.ci_ssh_public_key)]
    }
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "app" {
  name      = "app-onprem"
  node_name = var.pm_target_node
  pool_id   = var.pm_pool != "" ? var.pm_pool : null
  vm_id     = var.app_vmid

  clone {
    vm_id = tonumber(var.template_name)
    full  = true
  }

  agent {
    enabled = true
  }

  on_boot = true

  cpu {
    cores = var.app_cores
  }

  memory {
    dedicated = var.app_memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = local.app_datastore_id
    interface    = "scsi0"
    size         = local.app_disk_size_gb
    iothread     = false
  }

  initialization {
    datastore_id = var.cloudinit_storage

    ip_config {
      ipv4 {
        address = local.app_ipv4_address
        gateway = local.app_ipv4_gateway
      }
    }

    user_account {
      username = var.ci_user
      keys     = [trimspace(var.ci_ssh_public_key)]
    }
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "mgmt_jump" {
  name      = "mgmt-jump"
  node_name = var.pm_target_node
  pool_id   = var.pm_pool != "" ? var.pm_pool : null
  vm_id     = var.mgmt_jump_vmid

  lifecycle {
    ignore_changes = [
      keyboard_layout,
      agent[0].type,
    ]
  }

  agent {
    enabled = true
  }

  on_boot = false

  cpu {
    cores = var.mgmt_jump_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.mgmt_jump_memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = local.mgmt_jump_datastore_id
    interface    = "scsi0"
    size         = local.mgmt_jump_disk_size_gb
    iothread     = true
  }

  initialization {
    datastore_id = var.cloudinit_storage
    interface    = "ide0"

    ip_config {
      ipv4 {
        address = local.mgmt_jump_ipv4_address
        gateway = local.mgmt_jump_ipv4_gateway
      }
    }

    user_account {
      username = var.ci_user
      keys     = [trimspace(var.ci_ssh_public_key)]
    }
  }

  network_device {
    bridge = var.vm_bridge
    firewall = true
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}
