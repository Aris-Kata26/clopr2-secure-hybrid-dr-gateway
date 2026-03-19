# providers/azure — Azure Provider Adapter

## Status: LIVE — Validated 2026-03-14

The Azure implementation is the **current production-validated provider**.
All DR testing, failover validation, and CI/CD pipelines target this provider.

## Mapping to Shared Interface

| Shared interface module | Azure implementation | Location |
|---|---|---|
| `shared/core-network` | `azurerm_virtual_network` + `azurerm_subnet` + `azurerm_network_security_group` | `modules/network/` |
| `shared/compute-db` | `azurerm_linux_virtual_machine` (SystemAssigned identity) | `envs/dr-fce/main.tf` |
| `shared/compute-app` | `azurerm_linux_virtual_machine` (conditional, `enable_app_dr_vm`) | `envs/dr-fce/main.tf` |
| `shared/secrets-interface` | `azurerm_key_vault` + `azurerm_key_vault_secret` + `azurerm_role_assignment` | `modules/keyvault/` |
| `shared/monitoring` | `azurerm_log_analytics_workspace` + alert rules | `modules/loganalytics/` + `envs/dr-fce/alerting.tf` |

## Azure-Specific Features (no cross-cloud equivalent)

| Feature | Notes |
|---|---|
| Managed Identity (SystemAssigned) | Equivalent: EC2 instance profile (AWS), service account (GCP) |
| Azure Monitor / DCR / MMA Agent | Approximate: CloudWatch Agent (AWS), Ops Agent (GCP) |
| `azurerm_dev_test_global_vm_shutdown_schedule` | No direct equivalent — cost control only |
| `azurerm_consumption_budget_resource_group` | Approximate: AWS Budgets, GCP Billing budgets |
| Azure Arc | Azure-specific agent — not applicable outside Azure |

## Deployed Environments

| Environment | Region | Purpose |
|---|---|---|
| `envs/dr-fce` | germanywestcentral | Primary DR environment (PostgreSQL DR replica, WireGuard) |
| `envs/dev` | germanywestcentral | Dev/test (AKS + ACR + pg-dr VM) |
| `envs/swe-aks` | swedencentral | AKS cluster |

## Provider Version

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```

## Do Not Modify

The existing `envs/` and `modules/` directories are the validated Azure implementation.
Do not refactor them into the new shared/providers structure until:
1. AWS and GCP providers are deployed and validated
2. Module interfaces are proven equivalent in at least one non-Azure environment
3. A safe migration plan is documented
