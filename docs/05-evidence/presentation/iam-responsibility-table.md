# IAM & Responsibility Model — CLOPR2 Secure Hybrid DR Gateway

**Date:** 2026-03-19 | **Author:** KATAR711 | **Team:** BCLC24

---

## Identity & Role Table

| Identity / Role | Type | Scope | Permissions | What It Cannot Do |
|---|---|---|---|---|
| **KATAR711** (Platform Admin) | Human — Azure AD | Subscription | Deploy infra (Terraform), run DR scripts, push secrets to Key Vault, manage RBAC assignments | No standing write access to production DB |
| **pg-dr VM — dr-fce** | System-Assigned Managed Identity | Key Vault (dr-fce) | `Key Vault Secrets User` — read secrets only | Write/delete secrets, access other vaults, any compute/network ops |
| **pg-dr VM — dev** | System-Assigned Managed Identity | Key Vault (dev) | `Key Vault Secrets User` — read secrets only | Write/delete secrets, cross-environment access |
| **AKS Kubelet** | System-Assigned Managed Identity | ACR (existing, cross-region) | `AcrPull` — pull container images only | Push images, manage registry, any non-ACR resource |
| **Ops Viewer** (role, not yet assigned) | Human — Azure AD | Log Analytics, Azure Monitor | Read metrics, query logs, view alert rules | Modify infra, access Key Vault, run DR scripts |

---

## Key Vault Access Boundaries

| Vault | Environment | Who Can Read Secrets | Who Can Write Secrets | Secret Stored |
|---|---|---|---|---|
| `kv-clopr2-dr-fce-*` | dr-fce (germanywestcentral) | pg-dr VM managed identity | Platform Admin (KATAR711) only | `pg-replication-password` |
| `kv-clopr2-dev-*` | dev (germanywestcentral) | pg-dr VM managed identity | Platform Admin (KATAR711) only | `pg-replication-password` |

**Key Vault configuration:**
- RBAC authorization enabled (`rbac_authorization_enabled = true`) — no legacy access policies
- Soft delete: 7-day retention
- Public network access: enabled (NSG restricts at VM level; vault does not hold credentials for external access)

---

## Monitoring Access Boundaries

| Resource | Who Can View | Who Can Modify | Notes |
|---|---|---|---|
| Log Analytics Workspace | Platform Admin + Ops Viewer (read) | Platform Admin only | Deployed per environment (dr-fce, dev) |
| Azure Monitor Alert Rules (5) | Platform Admin + Ops Viewer (read) | Platform Admin only | auto_mitigation_enabled=true; no human in loop for evaluation |
| Arc-connected VM telemetry | Platform Admin | Platform Admin only | pg-primary, pg-standby, app-onprem — all Connected |
| Application /health endpoint | Anyone with network path | N/A (read-only endpoint) | Returns pg_is_in_recovery; no auth required (internal network only) |

---

## Least-Privilege Logic

```
Managed Identity:  read one vault → one secret → one credential
                   cannot modify infrastructure, cannot access other environments

AKS Kubelet:       pull one registry → cannot push, cannot modify registry

Human (DR ops):    SSH keys scoped to on-prem hosts only
                   Azure access via Terraform CLI — no standing portal write access

Alerts:            evaluate and auto-mitigate — do NOT call external APIs or execute code
```

---

## What No Identity Has

- No service principal with subscription-level Owner/Contributor standing access
- No shared credentials or passwords in environment variables
- No cross-environment Key Vault access (each env has its own vault, its own managed identity binding)
- No DR VM with SSH public access (port 22 closed to internet; SSH only via WireGuard tunnel from on-prem)

---

*Speaker notes: The model follows three principles — machine identities are scoped to one resource and one operation; human access is credential-based with no standing portal rights; and environments are fully isolated at the vault level. No identity in the system can perform a destructive cross-environment action.*
