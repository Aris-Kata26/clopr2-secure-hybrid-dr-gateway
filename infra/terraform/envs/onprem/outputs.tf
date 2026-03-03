output "vm_ids" {
  description = "Provisioned VM IDs"
  value = {
    pg_primary = proxmox_virtual_environment_vm.pg_primary.vm_id
    pg_standby = proxmox_virtual_environment_vm.pg_standby.vm_id
    app        = proxmox_virtual_environment_vm.app.vm_id
    mgmt_jump  = proxmox_virtual_environment_vm.mgmt_jump.vm_id
  }
}

output "vm_names" {
  description = "Provisioned VM names"
  value = {
    pg_primary = proxmox_virtual_environment_vm.pg_primary.name
    pg_standby = proxmox_virtual_environment_vm.pg_standby.name
    app        = proxmox_virtual_environment_vm.app.name
    mgmt_jump  = proxmox_virtual_environment_vm.mgmt_jump.name
  }
}

output "vm_ipv4_addresses" {
  description = "IPv4 addresses reported by QEMU guest agent (may be empty until agent is running)"
  value = {
    pg_primary = proxmox_virtual_environment_vm.pg_primary.ipv4_addresses
    pg_standby = proxmox_virtual_environment_vm.pg_standby.ipv4_addresses
    app        = proxmox_virtual_environment_vm.app.ipv4_addresses
    mgmt_jump  = proxmox_virtual_environment_vm.mgmt_jump.ipv4_addresses
  }
}

output "mgmt_jump_vmid" {
  description = "VM ID for mgmt-jump"
  value       = proxmox_virtual_environment_vm.mgmt_jump.vm_id
}

output "mgmt_jump_ip" {
  description = "IPv4 address from mgmt-jump ipconfig0"
  value       = try(format("%s/16", proxmox_virtual_environment_vm.mgmt_jump.ipv4_addresses[1][0]), null)
}
