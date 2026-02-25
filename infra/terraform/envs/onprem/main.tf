terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 3.0.1"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = var.pm_tls_insecure
}

resource "proxmox_vm_qemu" "pg_primary" {
  name                    = "pg-primary"
  target_node             = var.pm_target_node
  pool                    = var.pm_pool
  vmid                    = var.pg_primary_vmid
  clone                   = var.template_name
  full_clone              = true
  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = var.cloudinit_storage
  agent                   = 1
  onboot                  = true

  cores   = var.pg_primary_cores
  memory  = var.pg_primary_memory_mb
  scsihw  = "virtio-scsi-single"
  bootdisk = "scsi0"

  disk {
    size    = var.pg_primary_disk_gb
    storage = var.vm_storage
  }

  network {
    model  = "virtio"
    bridge = var.vm_bridge
  }

  ciuser   = var.ci_user
  sshkeys  = var.ci_ssh_public_key
  ipconfig0 = var.pg_primary_ipconfig0
}

resource "proxmox_vm_qemu" "pg_standby" {
  name                    = "pg-standby"
  target_node             = var.pm_target_node
  pool                    = var.pm_pool
  vmid                    = var.pg_standby_vmid
  clone                   = var.template_name
  full_clone              = true
  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = var.cloudinit_storage
  agent                   = 1
  onboot                  = true

  cores   = var.pg_standby_cores
  memory  = var.pg_standby_memory_mb
  scsihw  = "virtio-scsi-single"
  bootdisk = "scsi0"

  disk {
    size    = var.pg_standby_disk_gb
    storage = var.vm_storage
  }

  network {
    model  = "virtio"
    bridge = var.vm_bridge
  }

  ciuser   = var.ci_user
  sshkeys  = var.ci_ssh_public_key
  ipconfig0 = var.pg_standby_ipconfig0
}

resource "proxmox_vm_qemu" "app" {
  name                    = "app-01"
  target_node             = var.pm_target_node
  pool                    = var.pm_pool
  vmid                    = var.app_vmid
  clone                   = var.template_name
  full_clone              = true
  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = var.cloudinit_storage
  agent                   = 1
  onboot                  = true

  cores   = var.app_cores
  memory  = var.app_memory_mb
  scsihw  = "virtio-scsi-single"
  bootdisk = "scsi0"

  disk {
    size    = var.app_disk_gb
    storage = var.vm_storage
  }

  network {
    model  = "virtio"
    bridge = var.vm_bridge
  }

  ciuser   = var.ci_user
  sshkeys  = var.ci_ssh_public_key
  ipconfig0 = var.app_ipconfig0
}
