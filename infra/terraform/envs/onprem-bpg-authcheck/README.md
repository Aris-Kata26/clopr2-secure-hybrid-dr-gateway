# On-prem Proxmox (bpg provider auth check)

This is a minimal environment to verify authentication/permissions using the `bpg/proxmox` provider.
It does **not** provision VMs.

## What it checks
- Can Terraform authenticate to Proxmox using the bpg token format (`user@realm!token=secret`)
- Can it read:
  - cluster nodes (`proxmox_virtual_environment_nodes`)
  - version info (`proxmox_virtual_environment_version`)

## Setup
1. Copy `terraform.tfvars.example` to `terraform.tfvars` and set values.
2. Run:
   - `terraform init`
  - `terraform plan -var-file="terraform.tfvars"`

If you run `terraform plan` without a tfvars file, Terraform will prompt for variables.
Be careful not to paste the API token into the `endpoint` prompt (endpoint must be a URL).

## Notes
- `endpoint` must NOT include `/api2/json`.
- Avoid committing secrets: `.tfvars` are already ignored by the repo `.gitignore`.
- If you use a privilege-separated token, you still must grant ACLs to the token (Datacenter → Permissions → API Tokens).

## Security
If a token secret was pasted into chat or logs, revoke that token in Proxmox and create a new one.
