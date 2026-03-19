# providers/gcp/secrets — GCP Secret Manager
# ============================================
# STATUS: SCAFFOLD — NOT DEPLOYED
# Equivalent to: providers/azure → azurerm_key_vault + azurerm_key_vault_secret
# Implements: shared/secrets-interface

# terraform {
#   required_providers {
#     google = {
#       source  = "hashicorp/google"
#       version = "~> 5.0"
#     }
#   }
# }

# ── Secret — PostgreSQL replication password ──────────────────────────────────

# resource "google_secret_manager_secret" "pg_replication" {
#   secret_id = "${var.secret_name_prefix}-pg-replication-password"
#   project   = var.project_id
#
#   replication {
#     auto {}
#   }
#
#   labels = var.tags
# }

# resource "google_secret_manager_secret_version" "pg_replication" {
#   secret      = google_secret_manager_secret.pg_replication.id
#   secret_data = var.pg_replication_password
# }

# ── IAM — service account access binding ─────────────────────────────────────
# Equivalent to Azure "Key Vault Secrets User" role assignment

# resource "google_secret_manager_secret_iam_binding" "pg_dr_read" {
#   count     = var.consumer_service_account_email != null ? 1 : 0
#   project   = var.project_id
#   secret_id = google_secret_manager_secret.pg_replication.secret_id
#   role      = "roles/secretmanager.secretAccessor"
#   members   = ["serviceAccount:${var.consumer_service_account_email}"]
# }
