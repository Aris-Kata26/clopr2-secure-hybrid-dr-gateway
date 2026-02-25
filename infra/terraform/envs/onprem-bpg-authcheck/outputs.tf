output "node_names" {
  value = data.proxmox_virtual_environment_nodes.nodes.names
}

output "node_online" {
  value = data.proxmox_virtual_environment_nodes.nodes.online
}

output "pve_release" {
  value = data.proxmox_virtual_environment_version.version.release
}

output "pve_version" {
  value = data.proxmox_virtual_environment_version.version.version
}
