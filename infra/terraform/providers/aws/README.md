# providers/aws — AWS Provider Adapter

## Status: SCAFFOLD — Not deployed. Proof-of-portability only.

This directory contains the AWS implementation of the CLOPR2 shared interface contracts.
No AWS resources have been deployed. No AWS account has been touched.
This does NOT affect the validated Azure DR platform.

## Module Map

| Shared interface | AWS module | Status |
|---|---|---|
| `shared/core-network` | `providers/aws/core-network/` | Planned (not created) |
| `shared/compute-db` | `providers/aws/compute-db/` | Scaffold |
| `shared/compute-app` | `providers/aws/compute-app/` | Planned (not created) |
| `shared/secrets-interface` | `providers/aws/secrets/` | Scaffold |
| `shared/monitoring` | `providers/aws/monitoring/` | Planned (not created) |

## Provider Version

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

## Logical Role Mapping

| CLOPR2 logical role | Azure (live) | AWS (scaffold) |
|---|---|---|
| DR DB VM | `azurerm_linux_virtual_machine` | `aws_instance` (t3.small) |
| VM identity | SystemAssigned managed identity | `aws_iam_role` + `aws_iam_instance_profile` |
| Secret store | `azurerm_key_vault` | `aws_secretsmanager_secret` |
| Secret access | Key Vault Secrets User RBAC | `secretsmanager:GetSecretValue` IAM policy |
| VNet/subnet | `azurerm_virtual_network` / `azurerm_subnet` | `aws_vpc` / `aws_subnet` |
| NSG | `azurerm_network_security_group` | `aws_security_group` |
| Public IP | `azurerm_public_ip` (Static) | `aws_eip` |
| Log sink | `azurerm_log_analytics_workspace` | `aws_cloudwatch_log_group` |
| Alert | `azurerm_monitor_scheduled_query_rules_alert_v2` | `aws_cloudwatch_metric_alarm` |

## Equivalence Notes

| Feature | Azure | AWS | Equivalence |
|---|---|---|---|
| Managed identity | SystemAssigned (zero-credential) | IAM instance profile | Equivalent in function |
| Key Vault RBAC | `Key Vault Secrets User` built-in role | Custom IAM policy (GetSecretValue) | Approximate — AWS requires explicit policy |
| Auto-shutdown | `azurerm_dev_test_global_vm_shutdown_schedule` | Instance Scheduler or EventBridge | Not directly equivalent — cost control only |
| Budget alerts | `azurerm_consumption_budget_resource_group` | `aws_budgets_budget` | Approximate |
| Arc agent | Azure Arc | No equivalent | Azure-only concept |

## WireGuard Tunnel Addressing (planned)

On-prem peer (pg-primary): 10.200.0.5 (new peer entry in wg0.conf)
AWS DR VM:                  10.200.0.6/30

The on-prem pg-primary wg0.conf would need a second [Peer] block for the AWS endpoint.
Current on-prem peer (Azure): 10.200.0.1 / 10.200.0.2

## Steps to Deploy (roadmap)

1. Create AWS account + Terraform backend (S3 + DynamoDB state lock)
2. Uncomment provider block in `providers/aws/compute-db/main.tf`
3. Create `providers/aws/core-network/` module
4. Populate tfvars with region, VPC CIDR, WireGuard keys
5. Run `terraform init && terraform plan`
6. Configure pg-primary wg0.conf with second [Peer] block for AWS endpoint
7. Run Ansible `pg_ha.yml` and `wg_tunnel.yml` targeting AWS hosts
8. Run `dr-preflight.sh fullsite` to validate
