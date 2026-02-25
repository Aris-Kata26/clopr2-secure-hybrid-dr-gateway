# Troubleshooting log (issue -> root cause -> fix -> evidence).

## US8 Terraform baseline (EU region policy)
**Issue:** Terraform apply failed with `RequestDisallowedByAzure` for VNet/NSG/Log Analytics/Key Vault in `westeurope` and `belgiumcentral`.

**Root cause:** Subscription policy `sys.regionrestriction` allowed only specific regions (swedencentral, polandcentral, germanywestcentral, francecentral, spaincentral). Regions outside this list were blocked.

**Fix:** Switched location to `germanywestcentral`, updated `terraform.tfvars` values (RG/VNet/Log Analytics/Key Vault names), removed old RG from state, and re-ran `terraform apply`.

**Evidence:**
- [docs/05-evidence/outputs/terraform-validate.txt](docs/05-evidence/outputs/terraform-validate.txt)
- [docs/05-evidence/screenshots/rg-resources-gwc.png](docs/05-evidence/screenshots/rg-resources-gwc.png)

## US8 Terraform baseline (pre-existing RG)
**Issue:** Apply failed with “resource already exists” for RG.

**Root cause:** RG was created earlier via Azure CLI, so Terraform needed to import it.

**Fix:** `terraform import azurerm_resource_group.this /subscriptions/.../resourceGroups/rg-clopr2-katar711-weu`, then re-applied.

**Evidence:**
- [docs/05-evidence/outputs/terraform-validate.txt](docs/05-evidence/outputs/terraform-validate.txt)

## US8 Terraform baseline (Key Vault name validation)
**Issue:** Key Vault name rejected because it exceeded 24 chars or had invalid characters.

**Root cause:** Azure Key Vault naming rules (3-24 chars, lowercase letters/numbers only).

**Fix:** Updated `keyvault_name` to a valid value (`kvclopr2katarweu01gwc`) and re-applied.

**Evidence:**
- [docs/05-evidence/outputs/terraform-validate.txt](docs/05-evidence/outputs/terraform-validate.txt)

## US9 Defender recommendations (initially empty)
**Issue:** Defender recommendations list was empty after baseline enablement.

**Root cause:** CSPM evaluation had not completed yet.

**Fix:** Waited for evaluation after enabling Defender CSPM; recommendations populated.

**Evidence:**
- [docs/05-evidence/screenshots/recommendations-by-title.png](docs/05-evidence/screenshots/recommendations-by-title.png)

## US4/US5 On-prem provisioning (Proxmox RBAC: VM.Clone)
**Issue:** `terraform apply` failed with `received an HTTP 403 response - Reason: Permission check failed (/vms/200, VM.Clone)`.

**Root cause:** The Proxmox API token/user had enough rights to read cluster info (plan/authcheck), but did not have `VM.Clone` permission on the cloud-init template VM (VMID 200).

**Fix:** In Proxmox UI, grant the token/user a role containing `VM.Clone` on `/vms/200` (template VM) or at a higher scope (e.g., the pool containing the template, or Datacenter `/`). Then re-run `terraform apply`.

**Evidence:**
- [docs/05-evidence/outputs/terraform-onprem-apply.txt](docs/05-evidence/outputs/terraform-onprem-apply.txt)
