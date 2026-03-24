# Terraform Environments

| Environment | Classification | Region | Purpose |
|-------------|---------------|--------|---------|
| `onprem/` | **Active** | On-prem (Proxmox) | 4 VMs: pg-primary, pg-standby, app-onprem, mgmt-jump. Provider: bpg/proxmox ~0.97 |
| `dev/` | **Active** | germanywestcentral | AKS cluster, ACR, pg-dr VM, Key Vault, Log Analytics, alert rules |
| `dr-fce/` | **Active** | francecentral | Azure DR VM, WireGuard public IP, VNet, NSG, Key Vault, Log Analytics |
| `swe-aks/` | **Active** | swedencentral | AKS Free-tier cluster (1–2 nodes, Standard_B2s_v2) for workload demo |
| `aws-proof/` | **Portability proof** | eu-west-1 (Ireland) | AWS EC2 + RDS PostgreSQL — S5 portability validation. Validated and destroyed. |
| `gcp-proof/` | **Portability proof** | europe-west3 (Frankfurt) | GCP Compute Engine + Cloud SQL — S5 portability validation. Validated and destroyed. |
| `onprem-bpg-authcheck/` | **Archived smoke test** | On-prem | bpg/proxmox provider auth verification — smoke test only, not production |
| `onprem-bpg-smokevm/` | **Archived smoke test** | On-prem | Single VM smoke test for Proxmox provider — not production |
| `prod/` | **Placeholder / future** | TBD | Reserved for production promotion. Contains only `.gitkeep`. |

---

## Notes

- All active environments use Azure remote state backend (`backend.tf` → Azure Storage `clopr2tfstatekatar`).
- `aws-proof/` and `gcp-proof/` use local state (resources destroyed post-validation — state reflects destroyed infrastructure).
- `.terraform/` provider cache directories are gitignored in all environments.
- Shared variable interfaces are in `../shared/` — `compute-db/`, `compute-app/`, `core-network/`.
- Reusable modules are in `../modules/` — `keyvault/`, `loganalytics/`, `network/`.
