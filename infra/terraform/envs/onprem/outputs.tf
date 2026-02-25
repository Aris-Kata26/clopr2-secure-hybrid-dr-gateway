output "vm_ids" {
  description = "Provisioned VM IDs"
  value = {
    pg_primary = proxmox_vm_qemu.pg_primary.vmid
    pg_standby = proxmox_vm_qemu.pg_standby.vmid
    app        = proxmox_vm_qemu.app.vmid
  }
}

output "vm_names" {
  description = "Provisioned VM names"
  value = {
    pg_primary = proxmox_vm_qemu.pg_primary.name
    pg_standby = proxmox_vm_qemu.pg_standby.name
    app        = proxmox_vm_qemu.app.name
  }
}
