# Proxmox smoke VM (Terraform)

This environment creates a **brand-new empty VM** (no clone) in a Proxmox pool.

Purpose:
- Quickly validate that the API token has permission to **allocate** a VM in the pool/node/storage.
- If this succeeds but cloning fails, the problem is specifically `VM.Clone` permission on the template VM.

## Usage
1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill values.
2. Run:
   - `terraform init`
   - `terraform plan -var-file="terraform.tfvars"`
   - `terraform apply -auto-approve -var-file="terraform.tfvars"`

## Cleanup
- `terraform destroy -auto-approve -var-file="terraform.tfvars"`
