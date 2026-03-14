# Project Overview

**Project:** CLOPR2 Secure Hybrid DR Gateway
**Owner:** KATAR711
**Team tag:** BCLC24
**Scope:** Azure + Proxmox hybrid, AKS, Terraform/Ansible IaC, security (AZ-500 highlights), centralized monitoring, cost governance.

---

## Final validation approach (updated 2026-03-14)

Final DR acceptance is based on direct operational evidence:
PostgreSQL streaming replication health, Keepalived VIP failover/fallback,
WireGuard tunnel continuity, and application health endpoint verification.

**Azure Arc status:** Azure Arc was integrated as a hybrid management enhancement.
Due to extension convergence instability during final validation, Arc-dependent telemetry
is not used as a gate for DR acceptance. Arc resources remain deployed and documented
as an implemented enhancement.

**Validation runbook:** `docs/03-operations/dr-validation-runbook.md`
**Evidence checklist:** `docs/05-evidence/dr-validation-evidence-checklist.md`

