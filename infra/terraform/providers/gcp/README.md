# providers/gcp — GCP Provider Adapter

## Status: SCAFFOLD — Not deployed. Proof-of-portability only.

This directory contains the GCP implementation of the CLOPR2 shared interface contracts.
No GCP resources have been deployed. No GCP project has been touched.
This does NOT affect the validated Azure DR platform.

## Module Map

| Shared interface | GCP module | Status |
|---|---|---|
| `shared/core-network` | `providers/gcp/core-network/` | Planned (not created) |
| `shared/compute-db` | `providers/gcp/compute-db/` | Scaffold |
| `shared/compute-app` | `providers/gcp/compute-app/` | Planned (not created) |
| `shared/secrets-interface` | `providers/gcp/secrets/` | Scaffold |
| `shared/monitoring` | `providers/gcp/monitoring/` | Planned (not created) |

## Provider Version

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
```

## Logical Role Mapping

| CLOPR2 logical role | Azure (live) | GCP (scaffold) |
|---|---|---|
| DR DB VM | `azurerm_linux_virtual_machine` | `google_compute_instance` (e2-small) |
| VM identity | SystemAssigned managed identity | `google_service_account` |
| Secret store | `azurerm_key_vault` | `google_secret_manager_secret` |
| Secret access | Key Vault Secrets User RBAC | `roles/secretmanager.secretAccessor` |
| VNet/subnet | `azurerm_virtual_network` / `azurerm_subnet` | `google_compute_network` / `google_compute_subnetwork` |
| NSG | `azurerm_network_security_group` | `google_compute_firewall` (VPC-level) |
| Public IP | `azurerm_public_ip` (Static) | `google_compute_address` (EXTERNAL) |
| Log sink | `azurerm_log_analytics_workspace` | `google_logging_log_sink` + Cloud Logging |
| Alert | `azurerm_monitor_scheduled_query_rules_alert_v2` | `google_monitoring_alert_policy` |

## Equivalence Notes

| Feature | Azure | GCP | Equivalence |
|---|---|---|---|
| Managed identity | SystemAssigned (per-resource) | `google_service_account` (project-scoped) | Approximate — GCP SA is project-level not resource-level |
| Secret access | RBAC role assignment | IAM binding on secret | Equivalent in effect |
| NSG | Resource-group level | VPC-level firewall | Approximate — GCP firewalls are network-wide with target tags |
| Budget alerts | Consumption budget | GCP Billing budget | Equivalent |
| Auto-shutdown | Dev/Test schedule | No direct equivalent (use Cloud Scheduler) | Approximate |
| Arc agent | Azure Arc | No equivalent | Azure-only |

## WireGuard Tunnel Addressing (planned)

On-prem peer (pg-primary): 10.200.0.9 (new peer entry in wg0.conf)
GCP DR VM:                  10.200.0.10/30

## GCP-Specific Considerations

1. **Firewall rules are VPC-level** (not per-VM like Azure NSGs). Use `target_tags` to scope rules.
2. **Service accounts are project-scoped**. Create one SA per DR VM to maintain least-privilege.
3. **Secret Manager requires API enablement**: `gcloud services enable secretmanager.googleapis.com`
4. **Compute Engine requires API enablement**: `gcloud services enable compute.googleapis.com`
5. **cloud-init**: GCP supports cloud-init via `user-data` metadata key. Same cloud-init YAML works.

## Steps to Deploy (roadmap)

1. Create GCP project + enable required APIs
2. Create Terraform backend (GCS bucket for state)
3. Uncomment provider block in `providers/gcp/compute-db/main.tf`
4. Create `providers/gcp/core-network/` module
5. Configure service account credentials
6. Run `terraform init && terraform plan`
7. Add second WireGuard [Peer] block on pg-primary for GCP endpoint
8. Run Ansible playbooks targeting GCP hosts
9. Run `dr-preflight.sh fullsite` to validate
