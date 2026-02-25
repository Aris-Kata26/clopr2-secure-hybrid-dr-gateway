# On-prem Proxmox (Terraform)

This environment provisions on-prem VMs in Proxmox using a cloud-init template.

Provider: `bpg/proxmox` (preferred for Proxmox VE 8/9+).

## Prereqs
- Proxmox API token for the automation user.
- Template VM ID (cloud-init enabled).
- SSH public key to inject via cloud-init.

## Setup
1. Copy terraform.tfvars.example to terraform.tfvars and fill values.
2. Run:
    - terraform init
    - terraform fmt -recursive
    - terraform validate

## Token format (important)
- pm_api_token_id must look like: user@realm!tokenname (example: katar711@pve!terraform)
- pm_api_token_secret must be the token secret value shown once in the Proxmox UI

## Proxmox RBAC / privilege separation
If you get an error like:
"has valid credentials but cannot retrieve user list, check privilege separation of api token"

Fix in Proxmox UI (one of these approaches):
- Recommended (least surprise): create a new API token with Privilege Separation OFF.
- If keeping Privilege Separation ON: add explicit permissions for the token under Datacenter -> Permissions -> API Tokens.

The token/user must also have sufficient permissions to clone and configure VMs in the target pool/node/storage.

If you get:
"received an HTTP 403 response - Reason: Permission check failed (/vms/200, VM.Clone)"

Fix in Proxmox UI by granting the token/user `VM.Clone` on the template VM (VMID 200), or granting a role that includes `VM.Clone` at a higher scope (e.g., the pool that owns the template, or Datacenter `/`).

## Plan / Apply with evidence capture
From this folder (infra/terraform/envs/onprem):

- Create outputs folder (first time only):
   - mkdir -p ../../../../docs/05-evidence/outputs

- Plan (saves output for evidence):
   - terraform plan -no-color -var-file="terraform.tfvars" | tee ../../../../docs/05-evidence/outputs/terraform-onprem-plan.txt

- Apply (only after plan looks correct):
   - terraform apply -no-color -var-file="terraform.tfvars" | tee ../../../../docs/05-evidence/outputs/terraform-onprem-apply.txt

## Notes
- Store token secrets in terraform.tfvars or pass as TF_VAR_pm_api_token_secret.
- Cloud-Init drive should be on local-lvm (or another valid storage).
- IPs default to DHCP; change ipconfig0 to static if needed.
- Proxmox endpoint should typically be `https://<host>:8006/` (this env also accepts `.../api2/json` and strips it).
