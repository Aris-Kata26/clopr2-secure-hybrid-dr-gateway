# Infrastructure Security Hardening — CLOPR2 Secure Hybrid DR Gateway

**Owner:** KATAR711 | **Team:** BCLC24
**Implemented:** 2026-03-18 (architecture hardening phase)
**Sprint:** S5-07

---

## Overview

This document records the security hardening pass performed on the CLOPR2 hybrid DR
infrastructure. Three areas were reviewed and addressed: NSG rules, PostgreSQL
pg_hba.conf access controls, and secrets handling.

---

## 1. NSG Audit

### dr-fce environment

| Rule | Before | After | Status |
|------|--------|-------|--------|
| Bootstrap SSH | `pg_dr_bootstrap_ssh_cidrs = ["X.X.X.X/32"]` | `= []` | Cleared (prior sprint) |
| SSH inbound | N/A (was bootstrap only) | `10.200.0.1/32` only | PASS |
| PostgreSQL inbound | Tunnel peer | `10.200.0.1/32` only | PASS |
| WireGuard UDP 51820 | Internet (required) | Internet (required) | OK |

Bootstrap SSH was already cleared in a previous sprint. The DR VM (vm-pg-dr) is
not reachable via SSH or PostgreSQL from the public internet — only from the
WireGuard peer.

### dev environment

AKS NSG is managed by AKS. No application-level public inbound rules in Terraform.
pg-dr VM in dev follows the same pattern as dr-fce.

---

## 2. PostgreSQL pg_hba.conf Tightening

### Problem

The Ansible-managed pg_hba.conf blocks contained catch-all rules permitting any
authenticated user to connect to any database from broad CIDR ranges:

```
host    all    all    10.0.0.0/16      scram-sha-256   # ~65K on-prem addresses
host    all    all    10.200.0.0/30    scram-sha-256   # entire WireGuard tunnel
```

This meant any valid PostgreSQL user (including `postgres` superuser) with a known
password could connect from any host on the on-prem network or over the WireGuard
tunnel.

### Fix

Replaced catch-all rules with scoped entries:

```
# On-prem subnet (postgres role: roles/postgres/tasks/main.yml)
host    replication    replicator    10.0.0.0/16      scram-sha-256
host    appdb          appuser       10.0.96.13/32    scram-sha-256

# WireGuard tunnel (pg_dr.yml playbook)
host    replication    replicator    10.200.0.0/30    scram-sha-256
host    appdb          appuser       10.200.0.0/30    scram-sha-256
```

**Principle:** Only allow what is explicitly required:
- Replication: `replicator` user, `replication` pseudo-database, subnet CIDR
- Application: `appuser`, `appdb` database, exact app IP (`/32`) on-prem; tunnel CIDR for WireGuard

### Operational steps

1. Applied live on pg-primary via `sed` + `systemctl reload postgresql`
2. `reload` re-reads pg_hba.conf without disconnecting existing sessions
3. Updated Ansible:
   - `infra/ansible/roles/postgres/tasks/main.yml` — on-prem HA block
   - `infra/ansible/playbooks/pg_dr.yml` — WireGuard block (Play 1 + Play 4)

### Validation

- App `/health` → HTTP 200, `db=ok` immediately after reload
- `pg_stat_replication` → 2 streaming replicas (pg-standby + pg-dr) unaffected
- No PostgreSQL restart required; zero downtime

---

## 3. Secrets Handling

### Finding

`infra/terraform/envs/dev/terraform.tfvars` contains a plaintext
`pg_replication_password = "test..123"`.

### Mitigating controls

- `terraform.tfvars` files are gitignored via `*.tfvars` in `.gitignore`
- The password is a non-production test credential (not used in any public-facing path)
- Azure Key Vault is deployed in both dr-fce and dev environments (available for migration)

### Current status

Annotated with a TODO comment. Accepted as a **known limitation** for the current
dev/demo scope.

### Future remediation

Replace the tfvars plaintext password with one of:
1. `TF_VAR_pg_replication_password` environment variable (CI/CD secrets)
2. Terraform `data "azurerm_key_vault_secret"` reference to the existing Key Vault
3. Ansible Vault-encrypted variable passed at playbook run time

---

## 4. Remaining Limitations

| Item | Status |
|------|--------|
| `pg_replication_password` plaintext in `dev/terraform.tfvars` | Known limitation — gitignored, test cred |
| `postgres` superuser accessible from localhost | Default PostgreSQL — acceptable, no remote risk |
| WireGuard private key stored on VM filesystem | Standard WireGuard deployment pattern |
| SSH keys in project repo (public keys only) | Public keys only — no secret exposure |

---

## Evidence

`docs/05-evidence/security-hardening/`

| File | Contents |
|------|----------|
| `00-summary.txt` | Task summary and AC results |
| `01-nsg-audit.txt` | NSG rule inventory for dr-fce and dev |
| `02-pg-hba-before.txt` | pg_hba.conf state before tightening |
| `03-pg-hba-after.txt` | pg_hba.conf state after tightening |
| `04-replication-check.txt` | pg_stat_replication + app health post-reload |
