# providers/gcp/compute-db — GCP DR Database VM
# ================================================
# STATUS: SCAFFOLD — NOT DEPLOYED
# This module is proof-of-portability scaffolding only.
# It has NOT been applied to any GCP project.
# It does NOT affect the validated Azure DR platform.
#
# Implements: shared/compute-db interface
# Target:     Compute Engine VM running PostgreSQL 16 (DR replica from on-prem)

# ── Provider ──────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# provider "google" {
#   project = var.project_id
#   region  = var.region
# }

# ── Service Account ───────────────────────────────────────────────────────────
# Equivalent to Azure SystemAssigned Managed Identity

# resource "google_service_account" "pg_dr" {
#   account_id   = "clopr2-pg-dr-${var.env_name}"
#   display_name = "CLOPR2 DR DB VM — ${var.env_name}"
#   project      = var.project_id
# }

# ── Secret Manager access binding ─────────────────────────────────────────────
# Equivalent to Azure "Key Vault Secrets User" role assignment

# resource "google_secret_manager_secret_iam_binding" "pg_dr_replication" {
#   count     = var.secret_store_id != null ? 1 : 0
#   secret_id = var.secret_store_id
#   role      = "roles/secretmanager.secretAccessor"
#   members   = ["serviceAccount:${google_service_account.pg_dr.email}"]
# }

# ── Static IP ─────────────────────────────────────────────────────────────────
# Equivalent to Azure azurerm_public_ip (Static)

# resource "google_compute_address" "pg_dr" {
#   name         = "clopr2-pg-dr-ip-${var.env_name}"
#   region       = var.region
#   address_type = "EXTERNAL"
# }

# ── Firewall Rules ────────────────────────────────────────────────────────────
# Equivalent to Azure NSG rules
# Note: GCP firewall rules are VPC-level, not instance-level

# resource "google_compute_firewall" "pg_dr_wg" {
#   name    = "clopr2-pg-dr-wireguard-${var.env_name}"
#   network = var.network_self_link
#
#   allow {
#     protocol = "udp"
#     ports    = [tostring(var.wg_listen_port)]
#   }
#
#   source_ranges = ["${var.wg_onprem_public_ip}/32"]
#   target_tags   = ["clopr2-pg-dr"]
#   description   = "WireGuard inbound from on-prem public IP"
# }

# resource "google_compute_firewall" "pg_dr_ssh_wg" {
#   name    = "clopr2-pg-dr-ssh-wg-${var.env_name}"
#   network = var.network_self_link
#
#   allow {
#     protocol = "tcp"
#     ports    = ["22"]
#   }
#
#   source_ranges = ["10.200.0.0/24"]  # WireGuard tunnel range only
#   target_tags   = ["clopr2-pg-dr"]
#   description   = "SSH via WireGuard tunnel only"
# }

# resource "google_compute_firewall" "pg_dr_pg" {
#   name    = "clopr2-pg-dr-postgres-${var.env_name}"
#   network = var.network_self_link
#
#   allow {
#     protocol = "tcp"
#     ports    = ["5432"]
#   }
#
#   source_ranges = ["10.200.0.0/24"]
#   target_tags   = ["clopr2-pg-dr"]
#   description   = "PostgreSQL from WireGuard tunnel"
# }

# ── Cloud-Init (metadata startup-script) ─────────────────────────────────────
# Equivalent to Azure custom_data

# locals {
#   cloud_init = <<-CLOUDINIT
#     #cloud-config
#     packages:
#       - wireguard
#     write_files:
#       - path: /etc/wireguard/wg0.conf
#         permissions: '0600'
#         content: |
#           [Interface]
#           PrivateKey = ${var.wg_private_key}
#           Address    = ${var.wg_tunnel_ip}
#           ListenPort = ${var.wg_listen_port}
#           [Peer]
#           PublicKey    = ${var.wg_peer_public_key}
#           AllowedIPs   = 10.0.0.0/16,10.200.0.0/24
#           Endpoint     = ${var.wg_onprem_public_ip}:51820
#           PersistentKeepalive = 25
#     runcmd:
#       - systemctl enable --now wg-quick@wg0
#   CLOUDINIT
# }

# ── Compute Engine VM ─────────────────────────────────────────────────────────

# resource "google_compute_instance" "pg_dr" {
#   name         = "clopr2-pg-dr-${var.env_name}"
#   machine_type = var.vm_size          # e2-small
#   zone         = "${var.region}-b"   # e.g. europe-west3-b
#   project      = var.project_id
#
#   tags = ["clopr2-pg-dr"]
#
#   boot_disk {
#     initialize_params {
#       image = "ubuntu-os-cloud/ubuntu-2204-lts"
#       size  = var.disk_size_gb
#       type  = "pd-standard"
#     }
#   }
#
#   network_interface {
#     subnetwork = var.subnetwork_self_link
#     network_ip = var.private_ip
#     access_config {
#       nat_ip = google_compute_address.pg_dr.address
#     }
#   }
#
#   service_account {
#     email  = google_service_account.pg_dr.email
#     scopes = ["https://www.googleapis.com/auth/cloud-platform"]
#   }
#
#   metadata = {
#     ssh-keys   = "${var.admin_username}:${var.ssh_public_key}"
#     user-data  = local.cloud_init
#   }
#
#   labels = var.tags
# }
