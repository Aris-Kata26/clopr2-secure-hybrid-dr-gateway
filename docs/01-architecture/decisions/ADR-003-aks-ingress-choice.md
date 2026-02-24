# ADR-003: AKS ingress choice (NGINX) + Sprint-1 AKS design notes

## Status
Accepted (Sprint 1 baseline)

## Context
This project must deploy the application on **Azure Kubernetes Service (AKS)** and expose a reachable endpoint for the demo and later failover tests.  
We need an ingress solution that is:
- fast to implement (Sprint 1–2 constraints),
- stable for demos and evidence capture,
- compatible with a cost-aware Azure for Students subscription,
- aligned with security and least-privilege goals (AZ-500 highlights).

We also need to stay **EU-compliant** and remain consistent with our networking design.

## Decision
We will use **NGINX Ingress Controller** for AKS during Sprint 1/Sprint 2 as the ingress layer.

### Scope / Where it applies
- **Region:** Germany West Central (EU)
- **Resource Group:** `rg-clopr2-katar711-gwc`
- **Tags (mandatory on all Azure resources):**
  - `Team = BCLC24`
  - `Owner = KATAR711`

### AKS Design Notes (baseline)
**Networking**
- **VNet CIDR:** `10.10.0.0/16` (defined in `infra/terraform/envs/dev/terraform.tfvars`)
- **AKS subnet:** `snet-aks` → `10.10.0.0/22`  
  Rationale: provides enough IP space for nodes + Azure CNI pod IPs while keeping room for future services.
- **Management subnet (optional):** `snet-mgmt` → `10.10.4.0/24`  
  Rationale: reserve space for later operational needs (jumpbox, utilities, monitoring helpers).
- **Network model:** **Azure CNI (VNet-integrated)** to align with enterprise patterns and NSG control.

**Security boundaries**
- NSGs applied at subnet level with **least-privilege** rules (baseline now, tightened later).
- No direct public administration access (SSH restricted or avoided; management via controlled paths).
- Ingress will be the only intended public entry point for the application demo.

**Sizing (cost-aware)**
- 1 node pool (system) with **1–2 nodes**.
- Start with the smallest reliable VM size available (e.g., B-series if allowed; otherwise small D-series).
- Autoscaling disabled initially to avoid unexpected cost spikes during baseline.

**Ingress**
- NGINX Ingress Controller deployed in AKS.
- Ingress resources route HTTP traffic to the app `Service`.
- TLS can be added later (either via cert-manager or managed certificates) once the baseline is stable.

## Rationale (Why NGINX)
NGINX Ingress is chosen because it:
- is quick to deploy and easy to validate for evidence (kubectl outputs + URL screenshots),
- is cloud-agnostic and portable (useful for optional AWS/GCP later),
- keeps the baseline architecture simple and cost-aware,
- allows explicit control of routing rules and exposure surface.

## Alternatives Considered
### Alternative A: AGIC (Application Gateway Ingress Controller)
**Pros**
- Azure-native integration and can pair well with WAF capabilities.
- Centralized ingress and routing through Application Gateway.

**Cons**
- More moving parts and setup complexity.
- Typically higher cost and longer troubleshooting time for a school sprint.

**Decision:** not selected for Sprint 1; remains an optional upgrade if required.

### Alternative B: Service type LoadBalancer (no ingress controller)
**Pros**
- Simplest exposure path.

**Cons**
- Less structured routing, weaker “real-world” ingress story, and can become messy as services grow.

**Decision:** not selected as the target approach (may be used temporarily only if ingress troubleshooting blocks progress).

## Consequences
### Positive
- Fast implementation and stable evidence path for US3 (AKS runs the app).
- Portable ingress design supports optional multi-cloud readiness.
- Clear separation of app routing rules and future TLS hardening steps.

### Negative / Risks
- TLS and advanced routing policies require additional configuration (manual or cert-manager).
- Requires careful NSG and exposure control to remain least-privilege.

### Mitigations
- Start with HTTP for baseline validation, then harden:
  - TLS termination,
  - restrict admin access,
  - tighten NSG rules and monitoring alerts (later sprints).

## Implementation Notes (Evidence for US3)
Evidence expected after deployment:
- `kubectl get nodes -o wide`
- `kubectl get deploy,po,svc,ing -n clopr2`
- Browser/curl proof of `/health` endpoint via ingress URL
- Screenshots stored under `docs/05-evidence/screenshots/` and outputs under `docs/05-evidence/outputs/`