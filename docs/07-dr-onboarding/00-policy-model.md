# CLOPR2 — DR Onboarding Policy Model

**Document:** 00-policy-model.md
**Sprint:** S5 (post-validation)
**Status:** APPROVED — governs all future on-prem VM onboarding
**Owner:** KATAR711 | Team: BCLC24

---

## 1. Why CLOPR2 Does Not Auto-Replicate Every VM

CLOPR2's validated DR architecture targets a specific, well-understood workload: a
PostgreSQL HA cluster on Proxmox with a live streaming standby on Azure. Every
resource in that path — WireGuard tunnel, Keepalived VIP, pgBackRest stanza,
NSG rules, managed identity, Azure Blob container — was sized and scoped for
exactly that workload.

Blindly replicating every new on-prem VM to Azure would produce:

- **CIDR exhaustion** — the WireGuard tunnel subnet (10.200.0.0/30) has two usable
  IPs. A second VM pair needs a new subnet, new keypairs, and a coordinated NSG
  change.
- **VRID collision** — Keepalived uses VRID 51 for the pg-nodes HA pair. A second
  VRRP instance on the same segment requires a distinct VRID. Without an allocation
  registry, two instances fight and both fail.
- **pgBackRest stanza corruption** — the stanza name `main` is shared by the current
  cluster. Two clusters writing to the same stanza destroy backup metadata. Each
  cluster needs its own stanza and a separate Blob path.
- **Cost without justification** — an Azure VM costs money at runtime. A management
  jump box (mgmt-jump) or a utility VM with no data criticality does not justify a
  live standby.
- **Operational surface area** — more Azure resources mean more monitoring rules,
  more access policies, more Terraform state entries, and more runbook steps. Each
  addition that is not deliberately governed becomes a maintenance liability.
- **Validated path contamination** — the current DR path (pg-primary → Azure DR VM)
  is validated and evidence-backed. Adding unreviewd resources to the same Azure
  environment risks introducing drift that invalidates the evidence.

The policy therefore starts from a default of **exclusion**, not inclusion.

---

## 2. DR Onboarding Is Explicit and Policy-Driven

A VM becomes DR-managed only when:

1. It is listed in `dr-inventory.yml` with `dr_managed: true`.
2. Its `role` field maps to a defined DR pattern (see `01-role-taxonomy.md`).
3. A human operator has reviewed both entries and accepted the DR cost and
   operational scope.
4. An explicit Terraform apply and/or Ansible playbook run has provisioned the
   Azure-side representation — never automatically.

No automation, hook, or discovery mechanism promotes a VM to DR-managed without
going through steps 1–4. A VM created in Proxmox that is not registered in
`dr-inventory.yml` is invisible to all DR tooling.

---

## 3. `dr-inventory.yml` Is the Gate

`dr-inventory.yml` (at the repository root) is the single source of truth for which
VMs are under DR governance. It is:

- **Version-controlled** — every change is a git commit with a review trail.
- **Human-readable** — any team member can understand the policy by reading it.
- **Consumed by tooling** — `scripts/dr/classify-vm.sh` reads it to produce a
  classification report. Future Terraform modules and Ansible playbooks will read it
  to determine whether Azure-side actions are warranted.
- **The only authority** — Proxmox tags, VM names, and Ansible group membership are
  helper metadata. They inform the operator. They do not override the manifest.

Adding a VM to the manifest is a deliberate act. Removing a VM from the manifest
is equally deliberate, and must be accompanied by Azure-side cleanup before the
entry is deleted.

---

## 4. Role Determines the DR Pattern

The `role` field in `dr-inventory.yml` selects the onboarding template. Roles are
defined in `01-role-taxonomy.md`. Summary:

| Role | DR pattern applied |
|------|--------------------|
| `db-primary` | Live Azure standby VM + streaming replication + pgBackRest |
| `db-standby` | Protected by primary's DR path — no independent Azure action |
| `app` | Backup-only (Azure snapshot policy) + rebuildable standby (future) |
| `utility` | Backup-only (Azure snapshot policy) |
| `management` | Excluded — no Azure-side action ever |

A VM with an unrecognised or missing `role` produces status `UNKNOWN_ROLE` in
`classify-vm.sh` and is treated as excluded until the operator assigns a valid role.

---

## 5. Unknown VMs Are Excluded by Default

The default state for any VM is: **not DR-managed**.

This applies to:
- VMs created in Proxmox without a manifest entry.
- VMs present in the Ansible inventory but not in `dr-inventory.yml`.
- VMs with Proxmox tags that do not match any manifest entry.
- VMs whose `dr-inventory.yml` entry has `dr_managed: false`.
- VMs with a recognised role but `dr_managed` not explicitly set to `true`.

The classifier will output status `EXCLUDED` for all such VMs. No Azure action is
taken. No error is raised. The VM continues to run on-prem without any DR
awareness.

This is intentional: operators should have to opt in, not opt out.

---

## 6. Future Extension Points

This policy model is designed to grow without breaking the current validated path:

- **New VM role:** Add an entry to `01-role-taxonomy.md`, update the classifier's
  role-to-status mapping, and create a Terraform module + Ansible playbook for the
  new DR pattern. No existing code is modified.
- **New onboarding level:** Add a `dr_mode` value (e.g., `rebuild-standby`) and
  extend the classifier to label it. Implement the mode in a new Terraform module.
- **GitOps gate (future):** A GitHub Actions workflow triggered by a PR that modifies
  `dr-inventory.yml` can run `classify-vm.sh` and post the report as a PR comment,
  creating an audit trail for every manifest change.

None of these extensions require touching the validated DR runtime.
