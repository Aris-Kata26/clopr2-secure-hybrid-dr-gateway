# Current-State Portability Audit

**Date:** 2026-03-19 | **Author:** KATAR711 | **Team:** BCLC24

---

## Classification Legend

- **Cloud-neutral:** Works identically on any cloud or on-prem with no changes
- **Azure-specific:** Uses Azure-only primitives; requires provider-specific replacement
- **Tightly coupled:** Part of the validated DR path; changing it risks breakage
- **Safe to abstract now:** Can be wrapped behind an interface without touching live resources
- **Unsafe to change before presentation:** Do not touch; leave as-is

---

## Component Audit Table

| Component | Current implementation | Portable? | Needs abstraction? | Risk to change now |
|---|---|---|---|---|
| **PostgreSQL 16** | Standard PostgreSQL, streaming replication. No Azure-specific extensions. | ✅ Cloud-neutral | No — already portable | None |
| **pg_hba.conf / replication config** | CIDR-based access from 10.0.0.0/16 and WireGuard range. Standard PG config. | ✅ Cloud-neutral | No | None |
| **Keepalived / VIP** | On-prem only (10.0.96.10). VRRP between pg-primary and pg-standby. Cloud VMs do not use Keepalived. | ✅ On-prem only — not a cloud concern | No | None |
| **WireGuard (core)** | Software VPN — runs on any Linux VM. Provider-agnostic tunnel setup. | ✅ Cloud-neutral | No — config is already provider-agnostic | None |
| **WireGuard (endpoint naming)** | Azure DR VM public IP 20.216.128.32 hardcoded in on-prem wg0.conf | ≈ Portable pattern, Azure-specific value | Yes — abstract IP as variable | Low (variable already exists in Terraform) |
| **WireGuard (multi-peer)** | Currently 1 peer only (Azure). Extending to AWS/GCP requires adding [Peer] blocks. | ≈ Portable | Yes — multi-peer wg0.conf template | Low (additive change, does not break existing peer) |
| **FastAPI application** | Docker container, python:3.12-slim. OCI-compliant. No Azure SDK calls. | ✅ Cloud-neutral | No | None |
| **app/src/main.py** | Reads DB_HOST from env. No cloud-specific code. SELECT pg_is_in_recovery() only. | ✅ Cloud-neutral | No | None |
| **Dockerfile** | python:3.12-slim, pip install, standard CMD. | ✅ Cloud-neutral | No | None |
| **pgBackRest** | Deployed on pg-primary. Azure Blob Storage backend (repo1-type=azure). | ≈ Portable core, Azure-specific backend | Yes — abstract repo1-type as variable | Low (config change only, new backend requires bucket) |
| **pgBackRest stanza** | Stanza: main. Schedule: full weekly, diff daily. | ✅ Cloud-neutral | No | None |
| **Azure Key Vault** | `azurerm_key_vault` + `azurerm_key_vault_secret`. RBAC auth. | ❌ Azure-specific | Yes — secrets-interface abstracted | **HIGH — do not touch live vault** |
| **Managed Identity** | SystemAssigned on pg-dr VM. Grants Key Vault Secrets User. | ❌ Azure-specific | Yes — abstracted in shared/compute-db | **HIGH — do not touch live MI binding** |
| **Log Analytics Workspace** | `azurerm_log_analytics_workspace`. DCR + MMA agent. | ❌ Azure-specific | Yes — monitoring abstracted in shared/monitoring | Medium — monitoring is not in DR critical path |
| **Azure Monitor alert rules** | 5 rules in alerting.tf. `azurerm_monitor_scheduled_query_rules_alert_v2`. | ❌ Azure-specific | Yes — monitoring abstracted | Medium — alerts are not in DR critical path |
| **Azure Arc** | Arc agent installed on on-prem VMs for Azure Monitor integration. | ❌ Azure-specific | No — de-scoped; Azure-only feature | None (leave as-is) |
| **Azure VNet + NSG** | `azurerm_virtual_network`, `azurerm_subnet`, `azurerm_network_security_group`. | ❌ Azure-specific | Yes — core-network abstracted | **HIGH — do not touch live networking** |
| **AKS cluster** | `azurerm_kubernetes_cluster` in dev + swe-aks envs. | ❌ Azure-specific | No — K8s is dev-only, not in DR path | None (leave as-is) |
| **ACR** | `azurerm_container_registry` Basic tier. | ❌ Azure-specific | No — registry is dev-only | None (leave as-is) |
| **Terraform env structure (`envs/`)** | Flat env folders per cloud. Provider embedded in main.tf. | ≈ Structure is portable pattern; content is Azure-specific | Yes — providers/ layer adds parallel structure | **UNSAFE — do not move envs/ content** |
| **Terraform modules (`modules/`)** | Azure-specific modules (network, keyvault, loganalytics). | ❌ Azure-specific implementations | Yes — abstracted by shared/ contracts above | **UNSAFE — do not rename/move live modules** |
| **Ansible role: postgres** | Standard PGDG repo + PG16 install. No cloud calls. | ✅ Cloud-neutral | No | None |
| **Ansible role: postgres_primary** | Creates replication user. Standard SQL. | ✅ Cloud-neutral | No | None |
| **Ansible role: postgres_standby** | pg_basebackup + standby.signal. Standard. | ✅ Cloud-neutral | No | None |
| **Ansible role: keepalived** | On-prem VIP management. Not used on cloud VMs. | ✅ On-prem only | No | None |
| **Ansible role: wireguard** | Installs wireguard, deploys wg0.conf template. No cloud calls. | ✅ Cloud-neutral | No | None |
| **Ansible role: pgbackrest** | Installs pgBackRest, configures stanza. Repo type is variable-driven. | ≈ Portable — repo backend is a variable | No — backend config should become a variable | Low |
| **Ansible playbook: arc-onboard-servers.yml** | Azure Arc registration. Azure-specific. | ❌ Azure-specific | No — not in DR path | None |
| **DR scripts (dr-preflight, etc.)** | SSH + psql + systemctl. No cloud SDK calls. | ✅ Cloud-neutral | No — already works on any SSH target | None |
| **evidence-export.sh** | SCP + tee. No cloud calls. Writes locally. | ✅ Cloud-neutral | No | None |
| **Auto-shutdown schedule** | `azurerm_dev_test_global_vm_shutdown_schedule`. Cost control. | ❌ Azure-specific | No — cost control only, not in DR path | None |
| **Budget alerts** | `azurerm_consumption_budget_resource_group`. | ❌ Azure-specific | No — cost control only | None |

---

## What Is Safe to Abstract Now (already done)

- `shared/compute-db/` — interface contract created
- `shared/compute-app/` — interface contract created
- `shared/secrets-interface/` — interface contract created
- `shared/monitoring/` — interface contract created
- `shared/core-network/` — interface contract created
- `providers/aws/compute-db/` — scaffold created (not deployed)
- `providers/aws/secrets/` — scaffold created (not deployed)
- `providers/gcp/compute-db/` — scaffold created (not deployed)
- `providers/gcp/secrets/` — scaffold created (not deployed)

## What Must Stay Azure-Specific Until Further Notice

- `envs/dr-fce/` — validated DR environment; do not refactor
- `envs/dev/`, `envs/swe-aks/` — live environments
- `modules/network/`, `modules/keyvault/`, `modules/loganalytics/` — live module code
- Azure Arc onboarding playbook
- AKS + ACR resources

## What Is Roadmap Only

- AWS core-network module
- GCP core-network module
- AWS/GCP monitoring modules
- Ansible inventory for AWS/GCP hosts
- Multi-peer WireGuard template (wg0.conf with 3 peers)
- pgBackRest multi-backend variable (currently hardcoded `azure`)
- Actual deployment to AWS or GCP
