# envs/gcp-proof — GCP Proof-of-Portability
# ===========================================
# PURPOSE: Minimal isolated proof that the CLOPR2 DR VM pattern provisions
#          correctly on GCP. Not a production DR environment.
#
# SCOPE:   Isolated — entirely independent of the validated Azure platform.
#          Uses its own VPC, firewall rules, service account. No Azure resources touched.
#
# DEPLOY:  Run this in GCP Cloud Shell (gcloud auth application-default login already done):
#          cd clopr2-secure-hybrid-dr-gateway
#          terraform -chdir=infra/terraform/envs/gcp-proof init
#          terraform -chdir=infra/terraform/envs/gcp-proof plan
#          terraform -chdir=infra/terraform/envs/gcp-proof apply
#
# TEARDOWN: terraform -chdir=infra/terraform/envs/gcp-proof destroy
#
# Maps to:  shared/compute-db interface contract
# Scaffold: providers/gcp/compute-db/ (uncommented here for proof)
#
# Date:     2026-03-19 | Author: KATAR711 | Team: BCLC24

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # Local state — proof only. Run from Cloud Shell.
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── VPC (isolated, CIDR does not overlap Azure or on-prem) ───────────────────

resource "google_compute_network" "proof" {
  name                    = "clopr2-proof-vpc"
  auto_create_subnetworks = false
  description             = "CLOPR2 GCP proof-of-portability isolated VPC"
}

resource "google_compute_subnetwork" "proof" {
  name          = "clopr2-proof-subnet"
  region        = var.region
  network       = google_compute_network.proof.id
  ip_cidr_range = var.subnet_cidr
  description   = "CLOPR2 GCP proof subnet — CIDR isolated from Azure (10.20.x) and on-prem (10.0.x)"
}

# ── Firewall Rules ────────────────────────────────────────────────────────────
# GCP: VPC-level rules with target_tags (equivalent to Azure per-VM NSG)

resource "google_compute_firewall" "wg_inbound" {
  name        = "clopr2-proof-wireguard"
  network     = google_compute_network.proof.id
  description = "WireGuard UDP 51820 - proof only, production restricts to on-prem public IP"

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["clopr2-proof-dr-vm"]
}

resource "google_compute_firewall" "egress_all" {
  name        = "clopr2-proof-egress"
  network     = google_compute_network.proof.id
  description = "All egress for apt-get during bootstrap"
  direction   = "EGRESS"

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["clopr2-proof-dr-vm"]
}

# ── Static External IP ────────────────────────────────────────────────────────
# Equivalent to azurerm_public_ip (Static) — WireGuard endpoint address

resource "google_compute_address" "proof" {
  name         = "clopr2-proof-ip"
  region       = var.region
  address_type = "EXTERNAL"
  description  = "Static external IP for GCP proof DR VM (WireGuard endpoint)"
}

# ── Service Account ───────────────────────────────────────────────────────────
# Equivalent to Azure SystemAssigned Managed Identity.
# Least-privilege: no roles assigned for proof (would add secretAccessor in production).

resource "google_service_account" "proof" {
  account_id   = "clopr2-proof-dr-vm"
  display_name = "CLOPR2 GCP Proof DR VM"
  description  = "Service account for CLOPR2 GCP proof-of-portability DR VM"
}

# ── Cloud-Init via startup-script metadata ────────────────────────────────────
# Equivalent to Azure custom_data / AWS user_data.
# Installs WireGuard and PostgreSQL client — validates package availability.
# Does NOT configure WireGuard tunnel. Does NOT install PostgreSQL server.

locals {
  startup_script = <<-SCRIPT
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/clopr2-proof-init.log 2>&1

    echo "=== CLOPR2 GCP Proof-of-Portability Bootstrap ==="
    echo "Date:     $(date -u)"
    echo "Instance: $(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name)"
    echo "Zone:     $(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone)"

    apt-get update -qq
    apt-get install -y wireguard postgresql-client curl 2>&1

    echo ""
    echo "=== Package validation ==="
    wg --version
    psql --version

    echo ""
    echo "=== Proof marker ==="
    echo "clopr2-portability-proof-gcp-$(date +%Y%m%d)" > /etc/clopr2-proof
    cat /etc/clopr2-proof

    echo "=== Bootstrap complete ==="
  SCRIPT
}

# ── Compute Engine VM ─────────────────────────────────────────────────────────
# Equivalent to azurerm_linux_virtual_machine in envs/dr-fce/main.tf.
# Same logical role: DR DB VM that would host PostgreSQL + WireGuard.
# Same OS: Ubuntu 22.04 LTS (Jammy).

resource "google_compute_instance" "proof" {
  name         = "clopr2-proof-dr-vm"
  machine_type = var.vm_size
  zone         = var.zone
  description  = "CLOPR2 GCP proof-of-portability DR VM"

  tags = ["clopr2-proof-dr-vm"]

  labels = merge(var.labels, {
    role    = "dr-db-vm"
    purpose = "portability-proof"
    managed = "terraform"
  })

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-standard"
    }
    auto_delete = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.proof.id
    access_config {
      nat_ip = google_compute_address.proof.address
    }
  }

  service_account {
    email  = google_service_account.proof.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    ssh-keys           = "${var.ssh_username}:${var.ssh_public_key}"
    startup-script     = local.startup_script
    serial-port-enable = "TRUE"
  }

  allow_stopping_for_update = true
}
