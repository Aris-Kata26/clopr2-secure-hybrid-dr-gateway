# Terraform State Governance
**CLOPR2 Secure Hybrid DR Gateway** | Owner: KATAR711 | Team: BCLC24
**Implemented:** 2026-03-17 | **Status:** Active

---

## Overview

All CLOPR2 Terraform environments use **Azure Blob Storage as the remote state backend**.
Local `terraform.tfstate` files are no longer the source of truth for any active environment.

This change was implemented as part of the architecture hardening phase (S5 Additional tasks) to address:
- WireGuard private key exposure in `dr-fce/terraform.tfstate` via `custom_data` base64 blob
- Lack of state locking (concurrent apply risk)
- No state version history or rollback capability
- Non-enterprise state handling model

---

## Backend Infrastructure

| Resource | Value |
|----------|-------|
| Resource Group | `rg-clopr2-tfstate` |
| Location | `germanywestcentral` |
| Storage Account | `clopr2tfstatekatar` |
| SKU | `Standard_LRS` |
| TLS minimum | `TLS1_2` |
| Public blob access | Disabled |
| Blob versioning | **Enabled** (state rollback) |
| Auth method | Azure AD (`use_azuread_auth = true`) |

### Per-Environment Containers

| Container | Environment | State Key |
|-----------|-------------|-----------|
| `dr-fce` | `envs/dr-fce` (Azure DR VM, francecentral) | `terraform.tfstate` |
| `dev` | `envs/dev` (AKS + ACR + dev VM, germanywestcentral) | `terraform.tfstate` |
| `swe-aks` | `envs/swe-aks` (AKS, swedencentral) | `terraform.tfstate` |
| `onprem` | `envs/onprem` (Proxmox VMs) | `terraform.tfstate` |

---

## Access Model

**Authentication:** Azure AD only. No SAS tokens, no storage account keys.

**Required role:** `Storage Blob Data Contributor` on `rg-clopr2-tfstate`

To grant access to a new team member:
```bash
az role assignment create \
  --assignee <user-object-id> \
  --role "Storage Blob Data Contributor" \
  --resource-group "rg-clopr2-tfstate"
```

**State locking:** Automatic. The `azurerm` backend uses Azure Blob leases to lock state during any `terraform apply` or `terraform plan`. Concurrent operations on the same environment are rejected with a lock error.

---

## State Locking Behavior

When `terraform apply` runs, it acquires an exclusive blob lease (30 seconds, auto-renewed).
If a second `terraform apply` runs concurrently:

```
Error: Error acquiring the state lock
  Lock Info:
    ID:        <lock-id>
    Path:      clopr2tfstatekatar/dr-fce/terraform.tfstate
    Operation: OperationTypeApply
    Who:       katar711@...
    Created:   2026-03-17 ...
```

To force-release a stale lock (e.g., after a crash):
```bash
terraform force-unlock <lock-id>
```

---

## State Version History

Blob versioning is enabled. Every `terraform apply` creates a new blob version.
To list available versions:
```bash
az storage blob list-versions \
  --account-name clopr2tfstatekatar \
  --container-name dr-fce \
  --name terraform.tfstate \
  --auth-mode login \
  --output table
```

To restore a previous state version:
```bash
# Get version ID from list above
az storage blob copy start \
  --source-account-name clopr2tfstatekatar \
  --source-container dr-fce \
  --source-blob terraform.tfstate \
  --source-version-id <version-id> \
  --destination-account-name clopr2tfstatekatar \
  --destination-container dr-fce \
  --destination-blob terraform.tfstate \
  --auth-mode login
```

---

## Bootstrap

The storage account was created via `az` CLI to avoid the chicken-and-egg problem
(you need a backend to store the state of the backend's own Terraform config).

The bootstrap commands (for reproducibility):
```bash
# Resource group
az group create \
  --name "rg-clopr2-tfstate" \
  --location "germanywestcentral" \
  --tags Team=BCLC24 Owner=KATAR711 Purpose=terraform-state

# Storage account
az storage account create \
  --name "clopr2tfstatekatar" \
  --resource-group "rg-clopr2-tfstate" \
  --location "germanywestcentral" \
  --sku "Standard_LRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false \
  --https-only true \
  --tags Team=BCLC24 Owner=KATAR711 Purpose=terraform-state

# Enable versioning
az storage account blob-service-properties update \
  --account-name "clopr2tfstatekatar" \
  --resource-group "rg-clopr2-tfstate" \
  --enable-versioning true

# Containers
for container in onprem dr-fce dev swe-aks; do
  az storage container create \
    --name "$container" \
    --account-name "clopr2tfstatekatar" \
    --auth-mode login
done

# RBAC
az role assignment create \
  --assignee <operator-object-id> \
  --role "Storage Blob Data Contributor" \
  --resource-group "rg-clopr2-tfstate"
```

The Terraform code equivalent is in `infra/terraform/bootstrap/tf-state/main.tf` for documentation.

---

## Migration Summary

| Environment | Migration Date | Resources Migrated | Pre-Migration Sensitive Exposure |
|-------------|---------------|-------------------|----------------------------------|
| `dr-fce` | 2026-03-17 | 21 resources | WireGuard private key in custom_data |
| `dev` | 2026-03-17 | 19 resources | Key Vault secret references |
| `swe-aks` | 2026-03-17 | 4 resources | None identified |
| `onprem` | 2026-03-17 | 3 resources | Proxmox credentials via env vars |

Migration performed via:
```bash
terraform init -migrate-state -force-copy
```

Pre-migration backups stored in: `docs/05-evidence/tf-state-migration/backups/`
(Excluded from git via `*.tfstate.*` rule in `.gitignore`)

---

## Rollback Procedure

To revert a specific environment back to local state:

```bash
cd infra/terraform/envs/<env>

# 1. Restore backup
cp docs/05-evidence/tf-state-migration/backups/<env>-terraform.tfstate.<timestamp>.bak \
   terraform.tfstate

# 2. Replace backend.tf with local backend
cat > backend.tf << 'EOF'
terraform {
  backend "local" {}
}
EOF

# 3. Reinitialize with local backend
terraform init -reconfigure

# 4. Verify state
terraform state list
```

---

## Ongoing Operations

**Before running terraform apply on any environment:**
1. Ensure `az login` is active with an account that has `Storage Blob Data Contributor` on `rg-clopr2-tfstate`
2. Run `terraform plan` first — the backend will be initialized automatically
3. State locking is automatic — no additional steps required

**CI/CD integration (future):**
When a CI/CD pipeline is added, authenticate to Azure using a Service Principal with:
- `Storage Blob Data Contributor` on `rg-clopr2-tfstate`
- `Contributor` (or scoped roles) on the environment-specific resource group

Set the following environment variables in the pipeline:
```bash
ARM_CLIENT_ID=<service-principal-client-id>
ARM_CLIENT_SECRET=<service-principal-secret>
ARM_SUBSCRIPTION_ID=94e5704a-b411-402b-a8f3-ef46309fe5fb
ARM_TENANT_ID=5338e0bc-c9a3-47ba-8dd5-4cf8ae191d99
```

---

## Evidence

- `docs/05-evidence/tf-state-migration/` — migration run outputs
- `docs/05-evidence/tf-state-migration/backups/` — pre-migration tfstate backups (gitignored)
- `infra/terraform/bootstrap/tf-state/main.tf` — bootstrap documentation-as-code
