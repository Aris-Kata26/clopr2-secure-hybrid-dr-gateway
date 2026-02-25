# On-prem Proxmox (Terraform)

This environment provisions on-prem VMs in Proxmox using a cloud-init template.

## Prereqs
- Proxmox API token for the automation user.
- Template VM ID or name (cloud-init enabled).
- SSH public key to inject via cloud-init.

## Setup
1. Copy terraform.tfvars.example to terraform.tfvars and fill values.
2. Run:
   - terraform init
   - terraform plan
   - terraform apply

## Notes
- Store token secrets in terraform.tfvars or pass as TF_VAR_pm_api_token_secret.
- Cloud-Init drive should be on local-lvm (or another valid storage).
- IPs default to DHCP; change ipconfig0 to static if needed.
