# ADR-007 — Policy-Driven DR Onboarding via Manifest Model

**Document:**  02-adr-manifest-model.md
**Type:**      Architecture Decision Record
**Status:**    ACCEPTED
**Date:**      2026-03-20
**Authors:**   KATAR711 | Team: BCLC24
**Supersedes:** None
**Context:**   Sprint 5 post-validation, pre-presentation

---

## Context

CLOPR2's validated DR architecture was designed for a specific, well-understood
set of four on-prem VMs with static roles. As the project matures, new on-prem
VMs will be created. The question is: how should new VMs be brought into the DR
governance model?

Several models were evaluated:
- Automatic discovery (Proxmox API, VM naming, tags)
- Inventory-manifest gate
- Role-based template selection
- Blind replication of every VM

This ADR records the decisions made and the reasoning behind them.

---

## Decision 1 — Manifest-Driven Onboarding Was Chosen

**Decision:** A VM becomes DR-managed only when it is explicitly listed in
`dr-inventory.yml` with `dr_managed: true`. No other signal is sufficient on
its own.

**Alternatives considered:**

| Alternative | Why rejected |
|-------------|-------------|
| Proxmox API auto-discovery | Discovers all VMs including management and template VMs. No natural filter for "should this be DR-managed?" without additional classification logic. Risk: a test VM provisioned by a team member is accidentally replicated to Azure. |
| Naming-convention detection | Names can be changed accidentally or inconsistently. Governance by naming convention breaks silently. A VM named `pg-test` would match a `pg-` prefix rule and be onboarded incorrectly. |
| Opt-out model (replicate by default) | Maximally unsafe. Every new VM produces Azure cost and operational overhead without review. Impossible to maintain in a small team. |
| Tag-only model | Tags are mutable, easy to add by accident, and invisible to tooling that doesn't query the Proxmox API. Tags are not version-controlled. |

**Why the manifest model wins:**
- It is version-controlled. Every change to DR governance is a git commit.
- It is explicit. An operator must make a deliberate decision for each VM.
- It is auditable. `git log dr-inventory.yml` shows who added what and when.
- It is read by tooling. `classify-vm.sh` and future Terraform modules read
  `dr-inventory.yml` as their authoritative input.
- It fails safe. A VM not in the manifest is excluded — the default is correct.

---

## Decision 2 — Role-Based Classification Was Chosen

**Decision:** The `role` field in `dr-inventory.yml` determines which DR
template is applied. Roles are defined in `01-role-taxonomy.md`. Unknown roles
produce `UNKNOWN_ROLE` status and are treated as excluded.

**Why role-based:**
- The infrastructure is already role-structured. Ansible uses role-specific
  playbooks (`pg_ha.yml`, `app_deploy.yml`, `wg_tunnel.yml`). Terraform uses
  per-VM resource blocks. Role classification is not a new concept — it is
  making the existing implicit structure explicit.
- Different roles have fundamentally different DR requirements. A database primary
  needs streaming replication and pgBackRest. An application VM needs a snapshot
  policy and a rebuild playbook. A management VM needs nothing. A single
  "replicate everything" template cannot serve all three correctly.
- Role changes are rare. A VM's role is stable after initial deployment. The
  manifest entry for a VM does not need to be updated frequently.

---

## Decision 3 — Tags Are Helper Metadata, Not the Authority

**Decision:** Proxmox VM tags (e.g., `dr-managed`, `role-db-primary`) are
informational labels that assist operators in the Proxmox UI. They are not
consumed by DR automation as a policy signal. The manifest is the authority.

**Rationale:**
- Tags in the Proxmox `bpg/proxmox` Terraform provider are a flat list of
  strings. They are not structured, not queryable without API calls, and not
  version-controlled outside of Terraform state.
- Adding tags to existing VM resources requires a Terraform plan review to
  confirm no replacement is triggered. Until that plan has been reviewed and
  confirmed safe, tags must not be applied to the validated VMs.
- If tags and manifest entries ever disagree (e.g., a tag says `dr-managed`
  but the manifest has `dr_managed: false`), the manifest wins. No tooling
  should act on tags alone.

**Future use:** Once the Terraform plan impact is confirmed as in-place (no
replacement), tags will be added to all four on-prem VM resources as an
informational aid. The proposal is documented in
`docs/07-dr-onboarding/03-terraform-tag-proposal.md`.

---

## Decision 4 — Blind Replication Was Rejected

**Decision:** CLOPR2 will never automatically replicate every on-prem VM to
Azure without explicit classification and review.

**Technical reasons:**

1. **WireGuard /30 subnet exhaustion.** The current tunnel uses 10.200.0.0/30,
   providing exactly two usable IPs. Each new VM pair requiring a WireGuard tunnel
   needs a new /30 subnet allocated from 10.200.0.0/24, new keypairs generated,
   and the Azure NSG updated. This cannot be automated safely without an IP
   allocation registry that does not yet exist.

2. **Keepalived VRID collision.** VRID 51 is in use for the pg-nodes HA pair. A
   second VRRP instance on the same network segment with the same VRID would cause
   both HA pairs to fail unpredictably. Each new HA pair requires a unique VRID
   registered before deployment.

3. **pgBackRest stanza namespace.** The stanza name `main` is in use for the
   current PostgreSQL cluster. Two clusters sharing a stanza will corrupt each
   other's backup metadata. Each cluster requires a unique stanza name and a
   separate Azure Blob path.

4. **Azure Key Vault access boundary.** The Azure DR VM's managed identity is
   scoped to its specific Key Vault instance. A new DR VM requires its own
   managed identity and an explicit access grant. There is no inheritance.

5. **Validated path contamination.** The current DR path (pg-primary →
   vm-pg-dr-fce) is validated with evidence. Adding unreviewd resources to the
   same Azure environment (`envs/dr-fce`) introduces drift that could invalidate
   the evidence baseline.

**Operational reasons:**
- Each Azure DR VM incurs ongoing compute cost.
- More DR paths mean more runbook steps, more alert rules, and more failure modes.
- A team of two cannot maintain an automatically-growing set of Azure resources
  without investing in automation that does not currently exist.

---

## Decision 5 — Azure Site Recovery Is Not Used for PostgreSQL

**Decision:** Azure Site Recovery (ASR) is permanently excluded as a DR
mechanism for PostgreSQL workloads. Backup-level and streaming-replication-based
approaches are used instead.

**Rationale:**

ASR replicates VM disks continuously and produces a bootable Azure VM on failover.
For most stateless workloads this is operationally clean. For PostgreSQL it is
problematic:

1. **Crash-consistent vs. application-consistent snapshots.** ASR's crash-consistent
   replication does not guarantee a valid PostgreSQL data directory on the recovered
   disk. PostgreSQL crash recovery can handle this in many cases, but it is not the
   same as a clean checkpoint-flushed backup that pgBackRest provides.

2. **Competing failover mechanisms.** The validated DR path uses `pg_promote()` on
   the Azure DR VM after WAL drain confirmation. ASR's failover produces a separate
   VM from a replicated disk. Running two failover mechanisms targeting the same
   cluster is a split-brain risk.

3. **No WAL visibility.** ASR does not understand PostgreSQL WAL. It cannot report
   replication lag in meaningful units (bytes, LSN). The validated preflight check
   (`dr-preflight.sh`) uses `pg_stat_replication.write_lag` — a metric that ASR
   does not expose.

4. **Agent installation on live VMs.** ASR's Mobility Service agent must be
   installed on each source VM. This modifies the validated on-prem VMs, changing
   their state from the validated baseline.

5. **Cost.** ASR adds continuous replication egress cost on top of the existing
   WireGuard WAL streaming traffic.

**Alternative used:** pgBackRest to Azure Blob (WAL archiving + full backup) for
PITR, combined with streaming replication to a pre-provisioned Azure standby VM.
This is already validated in the current platform.

---

## Decision 6 — Validated Platform Remains Frozen Before Presentation

**Decision:** No changes to `infra/terraform/envs/dr-fce/`, `scripts/dr/`,
`infra/ansible/playbooks/`, or the Keepalived/WireGuard/pgBackRest configurations
of the four existing VMs will be made before the project presentation.

**Rationale:**
- The current platform is validated with 30+ evidence items in
  `docs/05-evidence/dr-validation/`.
- Any change to the live runtime — even an additive one — requires a new
  validation cycle to confirm the DR path still works.
- The pre-presentation period does not have capacity for a new validation cycle.
- The policy-driven onboarding work is preparatory and additive. It does not
  require touching the validated runtime to be useful.

**What this means in practice:**
- `dr-inventory.yml` is a new file at the repository root. It does not modify
  any existing file.
- `scripts/dr/classify-vm.sh` is a new read-only script. It does not modify
  any existing DR script.
- Ansible group additions in `hosts.ini` are additive. No existing group is
  removed or renamed.
- Terraform tag proposals are documented in
  `docs/07-dr-onboarding/03-terraform-tag-proposal.md` and not applied until
  a plan review confirms safety.

---

## Consequences

**Positive:**
- DR onboarding governance is explicit, auditable, and version-controlled.
- The validated platform is not disturbed.
- The architecture is extensible: new roles, new DR modes, and new VMs can be
  added without modifying core validated components.
- The manifest model supports a future GitOps gate (PR-triggered classify run)
  with no structural changes.

**Negative / Trade-offs:**
- Onboarding a new VM requires manual steps (manifest entry, Terraform module
  call, Ansible playbook run). There is no zero-touch automation. This is
  intentional.
- Operators must know to add new VMs to the manifest. A VM created in Proxmox
  without a manifest entry is silently excluded from DR — which is correct
  behaviour but requires team awareness.

---

## References

- `dr-inventory.yml` — authoritative manifest
- `docs/07-dr-onboarding/00-policy-model.md` — policy overview
- `docs/07-dr-onboarding/01-role-taxonomy.md` — role definitions
- `docs/07-dr-onboarding/03-terraform-tag-proposal.md` — pending tag proposal
- `scripts/dr/classify-vm.sh` — read-only classifier
- `docs/05-evidence/dr-validation/` — validation evidence baseline
- `docs/03-operations/dr-validation-runbook.md` v1.2 — operational runbook
