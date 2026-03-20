# CLOPR2 — On-Prem VM Role Taxonomy

**Document:** 01-role-taxonomy.md
**Sprint:** S5 (post-validation)
**Status:** APPROVED
**Owner:** KATAR711 | Team: BCLC24

---

## Overview

Every on-prem VM managed by CLOPR2 must have a declared `role` in `dr-inventory.yml`.
The role controls which DR onboarding template is applied, whether an Azure-side
resource is created, and what monitoring and backup policies attach.

This document defines the authoritative role taxonomy. New roles require an update
to this document and an Architecture Decision Record before they can be used in the
manifest.

---

## Role Definitions

---

### `db-primary`

**Description:**
The write-primary node of a PostgreSQL HA cluster. Holds the active dataset,
accepts writes, and streams WAL to one or more standbys. Has a WireGuard tunnel
to the Azure DR VM.

**Is it DR-managed?** Yes — highest priority.

**Recommended DR mode:** `live-standby`

**Azure-side action expected:** Yes.
- Azure DR VM provisioned from the `dr-vm` Terraform module.
- Streaming replication from on-prem primary to Azure DR VM via WireGuard tunnel.
- pgBackRest archiving to Azure Blob Storage (dedicated stanza per cluster).
- Azure Monitor alert rules for replication lag and WireGuard handshake age.
- Keepalived VIP documented; VRID must be registered to avoid collision.

**Current example:** `pg-primary` (10.0.96.11, VRID 51, WireGuard 10.200.0.1)

**Prerequisites before Azure-side action:**
- WireGuard keypair generated and distributed (manual step — see ADR-002).
- New WireGuard /30 subnet allocated from 10.200.0.0/24 (must not overlap existing).
- New VRID registered in VRID registry (must not overlap VRID 51).
- New pgBackRest stanza name chosen and Blob path allocated.
- Azure DR VM sizing reviewed.

---

### `db-standby`

**Description:**
A hot standby replica in a PostgreSQL HA cluster. Streams WAL from `db-primary`.
Never independently promoted in the current validated design. Protected by its
primary's DR path — if the primary has a live-standby on Azure, the standby
is implicitly covered.

**Is it DR-managed?** No — protected by primary.

**Recommended DR mode:** `protected-by-primary`

**Azure-side action expected:** None independently. The primary's Azure DR VM
can be promoted to cover this entire cluster (primary + standby).

**Monitoring note:** Replication lag from primary to this node is monitored as
part of the primary's DR preflight (`dr-preflight.sh`). No independent alert
rule is needed unless the standby takes on a separate workload.

**Current example:** `pg-standby` (10.0.96.14, BACKUP priority 90, nopreempt)

**Note:** `pg-standby` is NEVER directly promoted in the current design. The
correct on-prem failover trigger is `systemctl stop keepalived` on `pg-primary`,
not any action on `pg-standby` itself.

---

### `app`

**Description:**
An application host running containerised or process-based workloads. Connects
to the database via VIP rather than direct host address. Stateless or
near-stateless from a replication perspective (application state is in the DB,
not on the VM disk).

**Is it DR-managed?** Yes — medium priority.

**Recommended DR mode:** `backup-only` (Phase 2); `rebuild-standby` (Phase 3 future)

**Azure-side action expected:**
- Phase 2: Azure Recovery Services Vault backup policy attached to the VM's
  OS disk snapshot. Recovery creates a new Azure VM from the snapshot.
- Phase 3 (future): Azure VM pre-provisioned from an app role Terraform module.
  Ansible `app_deploy.yml` re-runs on DR event with updated `DB_HOST` pointing
  to the Azure DR database endpoint.

**Current example:** `app-onprem` (10.0.96.13, Docker port 8080, connects to VIP 10.0.96.10)

**RTO implication:** `backup-only` mode has a higher RTO (hours) than `live-standby`.
This is acceptable because the application tier is stateless — data recovery depends
on the database DR path, not the app VM.

**Prerequisites before Azure-side action:**
- `db-primary` Azure DR path must be operational (app needs a DB to connect to).
- Backup policy retention period agreed (default: 7 daily, 4 weekly).
- Ansible `app_deploy.yml` must accept `DB_HOST` as an external variable.

---

### `utility`

**Description:**
A VM running supporting infrastructure: log aggregators, monitoring agents,
build servers, CI runners, or other non-critical workloads. Has no stateful
data that is irreplaceable (logs can be re-ingested; build caches can be
rebuilt). Not part of the application data path.

**Is it DR-managed?** Optionally — low priority.

**Recommended DR mode:** `backup-only` (snapshot-based; recovery is best-effort)

**Azure-side action expected:**
- Azure Recovery Services Vault backup policy (if `dr_managed: true`).
- No live standby. Rebuild from backup or re-provision from scratch on DR event.
- No streaming replication, no WireGuard tunnel, no Keepalived.

**No current examples in CLOPR2.** This role is defined for future VMs.

**When to set `dr_managed: false`:**
- If the utility VM can be rebuilt from scratch in < 1 hour with no data loss
  (e.g., a monitoring scraper that re-reads metrics from its sources), there is
  no practical benefit to backup policy. Set `dr_managed: false`.

---

### `management`

**Description:**
A management, jump box, or administrative VM. Used exclusively for SSH access,
Ansible execution, or Terraform operations. Has no application data. Should be
the last VM restored in a DR scenario because it is not needed for the
application to serve traffic.

**Is it DR-managed?** Never.

**Recommended DR mode:** `excluded`

**Azure-side action expected:** None. Ever.

**Rationale:** A management VM that fails during a DR event does not prevent
application recovery. The Terraform and Ansible tooling runs from WSL or any
other workstation with SSH access to the Proxmox host. Providing a DR path for
the management VM adds cost and complexity with no benefit to RTO or RPO.

**Current example:** `mgmt-jump` (VM ID 204, on_boot=false, DHCP, firewall=true)

**Hard rule:** No `dr_managed: true` for the `management` role is ever valid.
The classifier (`classify-vm.sh`) will output `EXCLUDED` regardless of the
`dr_managed` field value.

---

## Role-to-DR-Mode Matrix

| Role | DR managed | DR mode | Azure VM | Streaming replication | Backup | Monitoring |
|------|-----------|---------|----------|----------------------|--------|-----------|
| `db-primary` | Yes | `live-standby` | Yes (future: per cluster) | Yes | pgBackRest | Full alerts |
| `db-standby` | No | `protected-by-primary` | No | N/A (secondary) | Via primary | Replication lag only |
| `app` | Yes | `backup-only` → `rebuild-standby` | Phase 3 | No | Azure snapshot | Basic |
| `utility` | Optional | `backup-only` | No | No | Azure snapshot | Optional |
| `management` | Never | `excluded` | No | No | No | No |

---

## Adding a New Role

To add a new role:

1. Open a PR that modifies this document with:
   - Role name (lowercase, hyphenated)
   - Description
   - DR-managed decision
   - Recommended DR mode
   - Azure-side action specification
   - Prerequisites
2. Update `dr-inventory.yml` schema comment to reference the new role.
3. Update `scripts/dr/classify-vm.sh` to handle the new role in the `case`
   statement.
4. Create a Terraform module and Ansible playbook for the new DR pattern (only
   if `dr_managed: true`).
5. Add an ADR in `docs/07-dr-onboarding/` documenting the decision.

New roles must NOT be added to `dr-inventory.yml` before steps 1–3 are complete.
