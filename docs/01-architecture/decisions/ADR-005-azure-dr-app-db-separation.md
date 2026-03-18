# ADR-005 — Azure DR App/DB Role Separation

**Status:** Accepted — infrastructure prepared, deployment pending maintenance window
**Date:** 2026-03-18
**Author:** KATAR711 | Team: BCLC24
**Replaces:** Implicit collocated design from full-site DR validation (2026-03-15)

---

## Context

During full-site failover validation (S4/S5 sprint), the FastAPI application was
deployed on the same Azure VM as the promoted PostgreSQL primary (`vm-pg-dr-fce`).
This worked operationally: the app used `--network host` to connect to
`localhost:5432` after promotion. The failover was validated PASS.

However, this collocated design has known architectural weaknesses:

1. **Single point of failure per tier**: A crash in the app process (OOM, port
   conflict, misconfiguration) could interfere with PostgreSQL on the same VM.
2. **Resource contention**: PostgreSQL and Docker share the same B2ats_v2 vCPU/RAM.
   During a DR event (already under stress), contention worsens.
3. **Role clarity**: The "database DR VM" should have a single responsibility.
   Running an application on it violates separation of concerns and makes the
   Ansible/Terraform model harder to reason about.
4. **Scaling independence**: App tier and DB tier have different scaling needs;
   collocating them prevents independent sizing.

---

## Decision

Provision a **dedicated Azure app VM** (`vm-app-dr-fce`) in the dr-fce resource
group and VNet, in the same subnet as the DB VM (`vm-pg-dr-fce`).

During full-site failover, the FastAPI container runs on `vm-app-dr-fce` and
connects to `vm-pg-dr-fce`'s PostgreSQL via the VNet private IP (intra-subnet,
no new NSG rules required — covered by Azure default `AllowVNetInBound`).

The DB VM's sole DR responsibility becomes: receive WAL replication, promote to
primary when triggered. No application workload.

---

## Architecture — Before vs After

### Before (collocated, validated 2026-03-15)

```
Full-site failover active state:

vm-pg-dr-fce (10.20.2.x, Standard_B2ats_v2)
  ├── PostgreSQL 16 PRIMARY (promoted from replica)
  └── Docker: clopr2-app-dr  ← --network host → localhost:5432

WSL → WireGuard → vm-pg-dr-fce:8000/health
```

### After (separated, ADR-005)

```
Full-site failover active state:

vm-pg-dr-fce (10.20.2.x, Standard_B2ats_v2)     ← DB role only
  └── PostgreSQL 16 PRIMARY

vm-app-dr-fce (10.20.2.20, Standard_B1s)          ← App role only
  └── Docker: clopr2-app-dr  → -e DB_HOST=<db-vm-private-ip>:5432

WSL → WireGuard → vm-pg-dr-fce → vm-app-dr-fce:8000/health
       (ProxyJump, intra-VNet)
```

---

## Implementation

### Terraform (`infra/terraform/envs/dr-fce/`)

Three new resources, all gated by `enable_app_dr_vm` (default `false`):

- `azurerm_network_interface.app_dr` — NIC in `dr-mgmt-subnet`, static private IP
  `10.20.2.20`, no public IP
- `azurerm_linux_virtual_machine.app_dr` — `Standard_B1s`, Ubuntu 22.04, Docker
  installed via cloud-init (`app_cloud_init.tftpl`), same SSH key as DB VM
- `azurerm_dev_test_global_vm_shutdown_schedule.app_dr` — auto-shutdown at 23:00

To deploy: set `enable_app_dr_vm = true` in `terraform.tfvars` and run
`terraform apply`.

### Scripts

`fullsite-failover.sh` and `fullsite-fallback.sh` both accept a new optional flag:

```bash
--app-vm <hostname-or-ip>
```

- **Without `--app-vm`** (default): collocated mode, backward compatible, uses
  existing validated paths.
- **With `--app-vm vm-app-dr-fce`**: separated mode. FS-7 transfers the Docker
  image to the app VM via SSH pipe and starts the container with
  `DB_HOST=<db-vm-private-ip>`. H-2 and FB-1 in fallback target the app VM.

SSH routing for `vm-app-dr-fce` uses `vm-pg-dr-fce` as ProxyJump (no new NSG
rules, same pattern as on-prem relay via pg-primary).

---

## Networking

| Path | Protocol | Source | Destination | Gate |
|------|----------|--------|-------------|------|
| WSL → DB VM | SSH (22) | 10.200.0.1/32 (WireGuard) | vm-pg-dr-fce | Existing NSG rule |
| DB VM → App VM (SSH) | SSH (22) | 10.20.2.x (intra-VNet) | vm-app-dr-fce | AllowVNetInBound (default) |
| App VM → DB VM (PG) | TCP (5432) | 10.20.2.20 (intra-VNet) | vm-pg-dr-fce | AllowVNetInBound (default) |
| WSL → App VM (port-fwd) | SSH tunnel via DB VM | 10.200.0.1/32 | vm-app-dr-fce:8000 | ProxyJump |

No new NSG rules required. Azure `AllowVNetInBound` (priority 65000) covers
intra-subnet traffic not matched by the more specific custom rules.

---

## Consequences

### Positive

- DB VM has a single responsibility during DR: PostgreSQL only.
- App tier crash cannot impact PostgreSQL process.
- Independent VM sizing: DB VM can be sized for PG workload; app VM uses cheaper
  `Standard_B1s` (Docker-only, minimal compute).
- Cleaner Ansible/Terraform model — roles match VM names.
- Path is ready for future AKS migration (AKS replaces `vm-app-dr-fce`; no DB VM
  changes required).

### Negative / Trade-offs

- Additional Azure cost: ~€6–8/month for `Standard_B1s` (mitigated by auto-shutdown).
- FS-7 image transfer (docker save/load via SSH) adds ~30s to failover time — still
  within DR RTO targets.
- One more VM to maintain and patch.
- Full validation of the separated path is pending a maintenance window (the
  collocated path remains the validated fallback).

---

## Alternatives Considered

| Option | Reason Rejected |
|--------|----------------|
| AKS as Azure app host | AKS in different VNet from DR VM — requires VNet peering (cross-env) which is a large, risky Terraform change. Ruled out before the 26th. |
| swe-aks | Cross-region + different VNet — same VNet peering problem, plus latency. |
| Documentation only | Does not produce a deployable improvement. |
| Keep collocated | Accepted as current state; ADR-005 defines the migration target. |

---

## Status

- Infrastructure code: READY (`enable_app_dr_vm = false` in tfvars)
- Script support: READY (`--app-vm` flag in both failover/fallback scripts)
- Live deployment: PENDING — requires `terraform apply` with `enable_app_dr_vm=true`
- Validation: PENDING — full-site failover re-test with `--app-vm vm-app-dr-fce`
- Rollback: set `enable_app_dr_vm = false`, `terraform apply` destroys new VM;
  scripts fall back to collocated mode automatically (no `--app-vm` flag)
