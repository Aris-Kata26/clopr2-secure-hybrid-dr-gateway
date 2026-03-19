# Provider Mapping — Azure ↔ AWS ↔ GCP

**Date:** 2026-03-19 | **Author:** KATAR711 | **Team:** BCLC24

Legend: ✅ Equivalent | ≈ Approximate | 🔲 Conceptual only | ❌ No equivalent

---

## Compute

| CLOPR2 role | Azure (live) | AWS (scaffold) | GCP (scaffold) | Equivalence |
|---|---|---|---|---|
| DR DB VM | `azurerm_linux_virtual_machine` | `aws_instance` | `google_compute_instance` | ✅ |
| App VM | `azurerm_linux_virtual_machine` | `aws_instance` | `google_compute_instance` | ✅ |
| Container runtime | Docker (manual install via Ansible) | Docker (same) | Docker (same) | ✅ |
| AKS cluster | `azurerm_kubernetes_cluster` | `aws_eks_cluster` | `google_container_cluster` | ≈ |
| Container registry | `azurerm_container_registry` (ACR) | `aws_ecr_repository` | `google_artifact_registry_repository` | ≈ |

### VM Size Mapping

| Logical size | vCPU | RAM | Azure | AWS | GCP |
|---|---|---|---|---|---|
| Minimal DR VM | 2 | 2 GB | Standard_B2ats_v2 | t3.small | e2-small |
| Small DR VM | 2 | 4 GB | Standard_B2s | t3.medium | e2-medium |
| Dev VM | 1 | 1 GB | Standard_B1s | t3.micro | e2-micro |

---

## Identity & Access

| CLOPR2 role | Azure (live) | AWS (scaffold) | GCP (scaffold) | Equivalence |
|---|---|---|---|---|
| VM machine identity | SystemAssigned Managed Identity | EC2 IAM instance profile | Service account bound to VM | ✅ |
| Identity creation | Automatic (SystemAssigned) | `aws_iam_role` + `aws_iam_instance_profile` | `google_service_account` | ≈ (AWS/GCP require explicit creation) |
| Secret read permission | `Key Vault Secrets User` RBAC role | `secretsmanager:GetSecretValue` IAM policy | `roles/secretmanager.secretAccessor` | ✅ |
| AKS/EKS/GKE pull from registry | AcrPull RBAC | ECR policy attachment | Artifact Registry IAM | ≈ |

---

## Secret Store

| CLOPR2 role | Azure (live) | AWS (scaffold) | GCP (scaffold) | Equivalence |
|---|---|---|---|---|
| Secret store resource | `azurerm_key_vault` | `aws_secretsmanager_secret` | `google_secret_manager_secret` | ✅ |
| Secret value storage | `azurerm_key_vault_secret` | `aws_secretsmanager_secret_version` | `google_secret_manager_secret_version` | ✅ |
| Authorization model | RBAC (role assignment) | IAM policy + role | IAM binding on secret | ≈ (functionally equivalent; syntax differs) |
| Soft delete / recovery | 7-day retention (configurable) | 7-day recovery window | Version disabled (no built-in soft delete) | ≈ (GCP has no direct equivalent for soft delete) |
| Secret name format | `pg-replication-password` | `clopr2/pg-replication-password` | `clopr2-pg-replication-password` | ≈ |
| Network access control | Public (VM-level NSG controls access) | VPC endpoint optional | VPC Service Controls optional | ≈ |

---

## Networking

| CLOPR2 role | Azure (live) | AWS (scaffold) | GCP (scaffold) | Equivalence |
|---|---|---|---|---|
| Virtual network | `azurerm_virtual_network` | `aws_vpc` | `google_compute_network` | ✅ |
| Subnet | `azurerm_subnet` | `aws_subnet` | `google_compute_subnetwork` | ✅ |
| Network security | `azurerm_network_security_group` (per NIC/subnet) | `aws_security_group` (per instance) | `google_compute_firewall` (VPC-level, target tags) | ≈ |
| Public IP | `azurerm_public_ip` (Static) | `aws_eip` (Elastic IP) | `google_compute_address` (EXTERNAL) | ✅ |
| WireGuard UDP 51820 | NSG rule, source = on-prem public IP | Security group ingress rule | Firewall rule, target tags | ✅ |
| VPN gateway (optional) | `azurerm_virtual_network_gateway` | `aws_vpn_gateway` | `google_compute_vpn_gateway` | ≈ |

**GCP networking difference:** GCP firewall rules are VPC-level, not per-VM. Use `target_tags` on the VM and matching firewall rules. Azure NSGs can be attached per NIC or subnet.

---

## Monitoring & Logging

| CLOPR2 role | Azure (live) | AWS (scaffold) | GCP (scaffold) | Equivalence |
|---|---|---|---|---|
| Log workspace | `azurerm_log_analytics_workspace` | `aws_cloudwatch_log_group` | Cloud Logging (built-in, no resource needed) | ≈ |
| VM agent | Azure Monitor Agent (`AzureMonitorLinuxAgent` extension) | CloudWatch Agent (SSM or user-data) | Ops Agent (startup script or policy) | ≈ |
| Metric alerts | `azurerm_monitor_scheduled_query_rules_alert_v2` | `aws_cloudwatch_metric_alarm` | `google_monitoring_alert_policy` | ≈ |
| Alert notification | Action group → email | SNS topic → email | Notification channel → email | ≈ |
| Log retention | 30 days (configurable) | Retention policy on log group | Log bucket retention policy | ≈ |
| Dashboard | Azure Workbook | CloudWatch Dashboard | GCP Cloud Monitoring dashboard | 🔲 |

---

## Backup

| CLOPR2 role | Azure (live) | AWS (scaffold) | GCP (scaffold) | Equivalence |
|---|---|---|---|---|
| pgBackRest backend | Azure Blob Storage | AWS S3 | GCP Cloud Storage | ✅ (pgBackRest supports all three) |
| pgBackRest stanza config | `repo1-type=azure` | `repo1-type=s3` | `repo1-type=gcs` | ✅ |
| VM backup | `azurerm_backup_protected_vm` (optional) | AWS Backup vault | GCP Backup and DR | ≈ |
| Backup credentials | Azure Managed Identity | EC2 instance profile (S3 access) | Service account (GCS access) | ✅ |

**pgBackRest note:** This is the highest-portability component in the stack. Changing the provider requires only updating `repo1-type`, `repo1-azure-*`/`repo1-s3-*`/`repo1-gcs-*` config and creating the equivalent storage bucket + access binding. The PostgreSQL backup logic is identical.

---

## Cost Controls

| CLOPR2 role | Azure (live) | AWS (scaffold) | GCP (scaffold) | Equivalence |
|---|---|---|---|---|
| Budget alert | `azurerm_consumption_budget_resource_group` | `aws_budgets_budget` | GCP Billing budget (no Terraform resource) | ≈ |
| Auto-shutdown | `azurerm_dev_test_global_vm_shutdown_schedule` | EventBridge rule + Lambda, or AWS Instance Scheduler | Cloud Scheduler + Cloud Functions | ≈ (no direct equivalent) |

---

## What Is Only Conceptual (not implementable now)

| Feature | Reason |
|---|---|
| AWS/GCP full-site DR validation | Requires live deployment, WireGuard tunnel test, Ansible run |
| Multi-cloud active-active DR | Out of scope — architectural complexity, no current requirement |
| Cross-cloud secret sync | No Terraform-native multi-cloud secret replication |
| Azure Arc on AWS/GCP VMs | Azure Arc can connect non-Azure VMs — possible but adds Azure dependency to AWS/GCP |

---

## pgBackRest Provider Config Reference

```ini
# Azure (live)
repo1-type=azure
repo1-azure-account=clopr2backupkatar
repo1-azure-container=pgbackrest
repo1-azure-key=<storage-key-or-managed-identity>

# AWS (scaffold — change only these 3 lines)
repo1-type=s3
repo1-s3-bucket=clopr2-pgbackrest
repo1-s3-region=eu-central-1

# GCP (scaffold — change only these 2 lines)
repo1-type=gcs
repo1-gcs-bucket=clopr2-pgbackrest
```

PostgreSQL configuration, stanza name, backup schedule, and restore procedure are identical across providers.
