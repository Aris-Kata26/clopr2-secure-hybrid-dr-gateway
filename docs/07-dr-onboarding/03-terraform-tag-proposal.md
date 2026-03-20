# Terraform Tag Proposal — On-Prem VM DR Metadata

**Document:** 03-terraform-tag-proposal.md
**Status:**   PROPOSAL — NOT YET APPLIED
**Date:**     2026-03-20
**Owner:**    KATAR711 | Team: BCLC24

---

## Purpose

The `bpg/proxmox` provider (v0.97+) supports a `tags` attribute on
`proxmox_virtual_environment_vm` resources. Adding informational DR tags to the
four on-prem VMs would make role and DR status visible in the Proxmox UI without
requiring a query to `dr-inventory.yml`.

Tags are helper metadata only. They are NOT the policy authority. The manifest
(`dr-inventory.yml`) is the gate.

---

## Proposed Tags Per VM

**`pg-primary` (resource: `proxmox_virtual_environment_vm.pg_primary`)**
```hcl
tags = ["dr-managed", "role-db-primary", "env-onprem"]
```

**`pg-standby` (resource: `proxmox_virtual_environment_vm.pg_standby`)**
```hcl
tags = ["dr-protected-by-primary", "role-db-standby", "env-onprem"]
```

**`app-onprem` (resource: `proxmox_virtual_environment_vm.app`)**
```hcl
tags = ["dr-managed", "role-app", "dr-mode-backup-only", "env-onprem"]
```

**`mgmt-jump` (resource: `proxmox_virtual_environment_vm.mgmt_jump`)**
```hcl
tags = ["dr-excluded", "role-management", "env-onprem"]
```

---

## Where Tags Would Be Added

In `infra/terraform/envs/onprem/main.tf`, each `proxmox_virtual_environment_vm`
resource block would receive a `tags` attribute immediately after the `name` field.
Example for `pg_primary`:

```hcl
resource "proxmox_virtual_environment_vm" "pg_primary" {
  name      = "pg-primary"
  node_name = var.pm_target_node
  pool_id   = var.pm_pool != "" ? var.pm_pool : null
  vm_id     = var.pg_primary_vmid
  tags      = ["dr-managed", "role-db-primary", "env-onprem"]   # <-- ADD
  ...
}
```

---

## Required Pre-Application Check

**Before applying this change, run a plan and confirm:**

```bash
terraform -chdir=infra/terraform/envs/onprem plan
```

Expected result for each VM: `~ update in-place` (not `- destroy / + create`).

The `tags` attribute in `bpg/proxmox ~0.97` is an in-place update field. It should
not trigger a VM replacement. However:

- If the Proxmox provider version or VM configuration causes a replacement plan,
  **do not apply**. Document the constraint and leave tags unset.
- If the plan shows `forces replacement` for any VM, the tag change is unsafe and
  must not proceed until the provider behaviour is confirmed.

**This plan MUST be reviewed before `terraform apply` is run.**

---

## Why This Is Not Applied Yet

1. The Proxmox environment (10.0.10.71) is not accessible from the CI pipeline
   and requires local credentials. A plan cannot be run in CI to automatically
   confirm safety.
2. The validated DR platform must not be disturbed before presentation. Any
   Terraform apply to `envs/onprem` — even for tags — touches live VMs and could
   trigger an unintended change if the plan output is misread.
3. Tags provide no functional DR benefit. They are a UI convenience. The risk/reward
   ratio does not justify a live apply before presentation.

---

## Rollback

If tags are applied and need to be removed:
1. Remove the `tags` attribute from all four resource blocks in `main.tf`.
2. Run `terraform plan` — should show `~ update in-place` (tag removal).
3. Run `terraform apply`.

No VM is destroyed or restarted by removing tags.

---

## Status Gate

This proposal moves to APPROVED and can be applied when:
- [ ] Presentation is complete.
- [ ] A `terraform plan` against the live Proxmox environment confirms in-place
      update for all four VMs (no replacement).
- [ ] The plan output is reviewed and signed off.
- [ ] A separate sprint task tracks the apply (to keep the commit history clean).
