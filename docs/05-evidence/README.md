# Evidence Directory

This directory contains all validation evidence produced during the project.

Start here: **[evidence-index.md](evidence-index.md)** — master index of all 30+ evidence items with descriptions and file references.

See also: **[dr-validation-evidence-checklist.md](dr-validation-evidence-checklist.md)** and **[full-site-dr-evidence-checklist.md](full-site-dr-evidence-checklist.md)** for structured checklists.

---

## Key Subdirectories

| Folder | Contents |
|--------|----------|
| [dr-validation/](dr-validation/) | On-premises HA failover/fallback evidence — 47 timestamped files. RTO <1s, fallback 24s. Validated 2026-03-14. |
| [full-site-dr-validation/](full-site-dr-validation/) | Full-site DR failover/fallback evidence — 37 files. RTO 32s, RPO 0 bytes. Validated 2026-03-16. |
| [app-resilience/](app-resilience/) | FastAPI /health endpoint responses during failover — db_role, pg_is_in_recovery, latency_ms. |
| [aks-workload/](aks-workload/) | AKS workload deployment verification — pod Running, LB IP, /health confirmed. |
| [monitoring/](monitoring/) | Azure Arc agent status, AMA extension install, Log Analytics heartbeat checks. |
| [portability-live/](portability-live/) | AWS (eu-west-1) and GCP (europe-west3) portability proof evidence. |
| [screenshots/](screenshots/) | 37 PNG screenshots used in the technical report — Azure portal, Proxmox, Kubernetes, Defender. |
| [backup-pitr/](backup-pitr/) | pgBackRest WAL archiving and PITR configuration evidence. |
| [security-hardening/](security-hardening/) | NSG rules, Key Vault IAM, RBAC, pod security context validation. |
| [alerting/](alerting/) | Azure Monitor alert rules JSON and notification evidence. |
| [tf-state-migration/](tf-state-migration/) | Terraform remote state backend migration to Azure Storage. |
| [outputs/](outputs/) | Raw script output logs — pre-Arc and post-Arc baselines. Archive in outputs/archive/. |
