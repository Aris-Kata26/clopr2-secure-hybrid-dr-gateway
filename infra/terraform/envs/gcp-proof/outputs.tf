# envs/gcp-proof — Outputs
# Mirrors shared/compute-db interface contract outputs.

output "instance_id" {
  description = "Compute Engine instance ID — equivalent to azurerm_linux_virtual_machine.id"
  value       = google_compute_instance.proof.instance_id
}

output "instance_name" {
  description = "Compute Engine instance name"
  value       = google_compute_instance.proof.name
}

output "private_ip" {
  description = "Internal IP — equivalent to azurerm_network_interface.private_ip_address"
  value       = google_compute_instance.proof.network_interface[0].network_ip
}

output "public_ip" {
  description = "External IP — equivalent to azurerm_public_ip.ip_address (WireGuard endpoint)"
  value       = google_compute_address.proof.address
}

output "service_account_email" {
  description = "Service account email — equivalent to Azure managed identity principal_id"
  value       = google_service_account.proof.email
}

output "network_id" {
  description = "VPC network ID — equivalent to azurerm_virtual_network.id"
  value       = google_compute_network.proof.id
}

output "zone" {
  description = "GCP zone the VM was deployed in"
  value       = google_compute_instance.proof.zone
}

output "teardown_command" {
  description = "Command to destroy all proof resources"
  value       = "terraform -chdir=infra/terraform/envs/gcp-proof destroy -auto-approve"
}
