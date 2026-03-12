# DR France Central (dr-fce)

## Goal
Deploy a cost-aware PostgreSQL DR VM in France Central because Germany West Central blocks low-cost SKUs for this subscription.

## What this env deploys now
- Resource Group: `rg-clopr2-katar711-dr-fce`
- VNet: `vnet-clopr2-dr-fce` + subnet `dr-mgmt-subnet`
- NSG: `nsg-clopr2-dr-fce` with SSH + Postgres restricted rules
- DR VM: `vm-pg-dr-fce` (no public IP)
- Key Vault (RBAC) + secret `pg-replication-password`
- Log Analytics workspace + AMA + DCR association
- RG budget alert (monthly)

## Gated by IT approval
- VPN Gateway + public IP
- Local Network Gateway
- VPN connection and shared key

## Security notes
- DR VM has no public IP.
- SSH is restricted to admin /32 or VPN CIDRs only.
- Postgres (5432) is restricted to on-prem/VPN CIDRs only.
- No secrets in git: `terraform.tfvars` stays local and is gitignored.
- `tfstate` stays local and is gitignored.
- Key Vault uses RBAC (no access policies).

## Usage (no apply without approval)
- `terraform fmt -recursive`
- `terraform init -backend=false`
- `terraform validate`
