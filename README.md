# Secure Hybrid DR Gateway

A hybrid disaster recovery platform connecting an on-premises Proxmox environment to Microsoft Azure. The primary workload is a PostgreSQL 16 database protected by on-premises high availability (Keepalived + streaming replication) and cross-site DR to an Azure VM over a WireGuard-encrypted tunnel. All core failure scenarios were tested under live conditions with timestamped evidence.

---

## What this project demonstrates

- Hybrid DR architecture from infrastructure provisioning through live validation
- PostgreSQL streaming replication across two independent sites (on-prem → Azure)
- Keepalived VRRP failover with a validated virtual IP, including the operational impact of `nopreempt`
- Infrastructure as Code with Terraform and Ansible across on-prem and cloud environments
- Containerized application deployment on Docker and Azure Kubernetes Service
- Secrets handling with Azure Key Vault and Managed Identity
- Hybrid observability with Azure Monitor, Log Analytics, and Azure Arc
- CI/CD discipline with GitHub Actions and ClickUp task traceability

---

## Validated results

- **On-prem HA — VRRP convergence:** < 1 second
- **On-prem HA — app-confirmed reconnection:** < 5 seconds
- **Full-site DR failover to Azure:** 32 seconds, **RPO = 0 bytes**
- **Full-site DR fallback to on-prem:** ~103 seconds

All results are based on timestamped evidence files in `docs/05-evidence/`.

---

## Tech stack

**Infrastructure:** Proxmox VE, Microsoft Azure, Terraform, Ansible
**Database:** PostgreSQL 16, streaming replication, Keepalived, pgBackRest
**Connectivity:** WireGuard
**Application:** FastAPI, Docker, Azure Kubernetes Service
**Security:** Azure Key Vault, Managed Identity, RBAC, NSGs, pod securityContext
**Observability:** Azure Monitor, Log Analytics, Azure Arc
**CI/CD:** GitHub Actions, ClickUp task traceability

---

## Repository map

- `app/` — FastAPI application and Docker assets
- `deploy/k8s/` — Kubernetes manifests for the AKS workload
- `infra/terraform/envs/` — Terraform environments
- `infra/ansible/` — Playbooks, roles, and inventories
- `scripts/dr/` — DR automation scripts and helpers
- `docs/01-architecture/` — Architecture diagram and ADRs
- `docs/03-operations/` — Runbooks, monitoring notes, and audits
- `docs/05-evidence/` — Validation evidence and screenshots
- `docs/06-portability/` — AWS and GCP portability documentation

---

## Scope note

This repository contains three distinct layers:

**Validated DR runtime** — on-prem PostgreSQL HA and full-site Azure DR failover/fallback. All RTO/RPO figures above apply to this layer only.

**Supporting workload** — AKS in Sweden Central running the application with security hardening. Live and functional, but not part of the validated DR runtime.

**Portability appendix** — AWS and GCP Terraform proofs showing the same VM/network/bootstrap pattern on other providers. These are appendix demonstrations, not active DR targets.

## Project metadata

- **Owner (IAMCODE):** KATAR711
- **Team:** BCLC24
- **Compliance target:** EU regions/services only
- **Hybrid scope:** Azure + on-prem Proxmox
