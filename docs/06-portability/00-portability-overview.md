# Cloud Portability Layer — CLOPR2 Secure Hybrid DR Gateway

**Date:** 2026-03-19 | **Author:** KATAR711 | **Team:** BCLC24

---

## Purpose

This document describes the controlled cloud-portability layer added to CLOPR2 in Sprint 5.
The goal is to package the infrastructure design as cloud-agnostic without breaking the current
validated Azure platform.

**What was done:** interface contracts + provider scaffolding + documentation
**What was NOT done:** migration of existing Azure resources, deployment to AWS/GCP

---

## Portability Principle

> The validated Azure DR path is a correct, working implementation of a logical DR pattern.
> The portability layer expresses that same pattern as provider-neutral contracts,
> then maps those contracts to each cloud's native primitives.

The architecture is **design-portable**. Deployment to AWS or GCP requires:
1. Provider credentials and accounts
2. Uncomment provider stubs in `providers/aws/` or `providers/gcp/`
3. Ansible inventory update for new cloud hosts
4. WireGuard peer entry added to on-prem pg-primary wg0.conf

---

## Repository Structure After Phase 5

```
infra/terraform/
│
├── envs/                         ← UNCHANGED — current Azure environments
│   ├── dr-fce/                   LIVE — validated DR environment
│   ├── dev/                      LIVE — dev/test
│   ├── swe-aks/                  LIVE — AKS
│   └── onprem/                   LIVE — Proxmox VMs
│
├── modules/                      ← UNCHANGED — existing Azure modules
│   ├── network/                  azurerm VNet + NSG
│   ├── keyvault/                 azurerm Key Vault
│   └── loganalytics/             azurerm Log Analytics
│
├── shared/                       ← NEW — provider-neutral interface contracts
│   ├── compute-db/               DR DB VM interface (variables + README)
│   ├── compute-app/              App VM interface (variables)
│   ├── secrets-interface/        Secret store interface (variables)
│   ├── monitoring/               Log/alert sink interface (variables)
│   └── core-network/             Network layer interface (variables)
│
└── providers/                    ← NEW — provider-specific adapters
    ├── azure/                    README — maps to existing envs/ + modules/
    ├── aws/
    │   ├── README.md             Role mapping, equivalence notes, deploy roadmap
    │   ├── compute-db/           EC2 stub (commented — NOT deployed)
    │   └── secrets/              Secrets Manager stub (commented — NOT deployed)
    └── gcp/
        ├── README.md             Role mapping, equivalence notes, deploy roadmap
        ├── compute-db/           Compute Engine stub (commented — NOT deployed)
        └── secrets/              Secret Manager stub (commented — NOT deployed)
```

---

## What Is Live vs Scaffold vs Roadmap

| Component | Status |
|---|---|
| Azure `envs/dr-fce` | **LIVE — validated** |
| Azure `envs/dev` | **LIVE** |
| Azure `envs/swe-aks` | **LIVE** |
| `shared/` interface modules | **CREATED — interface contracts only, no deployment** |
| `providers/azure/` | **DOCUMENTED — maps to existing live envs** |
| `providers/aws/compute-db` | **SCAFFOLD — commented Terraform, not applied** |
| `providers/aws/secrets` | **SCAFFOLD — commented Terraform, not applied** |
| `providers/gcp/compute-db` | **SCAFFOLD — commented Terraform, not applied** |
| `providers/gcp/secrets` | **SCAFFOLD — commented Terraform, not applied** |
| AWS core-network, monitoring | **ROADMAP — not created** |
| GCP core-network, monitoring | **ROADMAP — not created** |
| Ansible AWS/GCP inventory | **ROADMAP — existing roles are reusable as-is** |

---

## Ansible Portability

The existing Ansible roles require **zero changes** to work on AWS or GCP VMs.
They are already cloud-agnostic — they operate over SSH and configure the OS,
not cloud APIs.

See: [03-ansible-portability.md](03-ansible-portability.md)

---

## Key Design Decisions

1. **Existing `envs/` and `modules/` are not touched.** The shared/providers structure is additive.
2. **Provider stubs are commented Terraform.** They do not affect `terraform plan` on existing envs.
3. **Shared interface modules are variables-only.** They have no resource blocks and no providers.
4. **WireGuard tunnel plan extends naturally.** Each new cloud DR VM gets its own /30 subnet in 10.200.0.0/24.
5. **The Ansible control plane (dr-preflight, onprem-failover, etc.) is target-agnostic.** SSH + pg_isready work on any Linux VM.
