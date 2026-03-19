# providers/gcp/compute-db — Outputs (commented until deployed)

# output "vm_id" {
#   description = "Compute Engine instance ID"
#   value       = google_compute_instance.pg_dr.instance_id
# }

# output "private_ip" {
#   description = "Internal IP address"
#   value       = google_compute_instance.pg_dr.network_interface[0].network_ip
# }

# output "public_ip" {
#   description = "External (NAT) IP address — WireGuard endpoint"
#   value       = google_compute_address.pg_dr.address
# }

# output "identity_id" {
#   description = "Service account email (equivalent to Azure managed identity)"
#   value       = google_service_account.pg_dr.email
# }
