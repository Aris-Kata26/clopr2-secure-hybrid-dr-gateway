# Ansible Portability Analysis

**Date:** 2026-03-19 | **Author:** KATAR711 | **Team:** BCLC24

---

## Summary

The existing Ansible roles and DR scripts require **no changes** to operate on AWS or GCP VMs.
They communicate over SSH and configure the Linux OS — they make no cloud API calls.

Adding a new cloud provider requires only:
1. A new inventory file for the new cloud hosts
2. SSH key access to the new VMs (same pattern as current on-prem + Azure)
3. Group vars for the new environment (region-specific values only)

---

## Role Portability Table

| Role | Cloud calls? | OS-specific? | Portable? | Notes |
|---|---|---|---|---|
| `postgres` | None | Ubuntu/Debian (PGDG repo) | ✅ | Works on any Ubuntu/Debian VM — AWS AMI and GCP Ubuntu images qualify |
| `postgres_primary` | None | None — pure SQL | ✅ | `CREATE USER replicator REPLICATION` is provider-agnostic |
| `postgres_standby` | None | None — pg_basebackup | ✅ | pg_basebackup runs over TCP — provider-agnostic |
| `keepalived` | None | On-prem only (VRRP) | ✅ on-prem | Not deployed on cloud VMs; cloud VMs do not need Keepalived |
| `wireguard` | None | Linux kernel module | ✅ | wg-quick works on any Linux kernel ≥ 5.6. AWS/GCP Ubuntu 22.04 qualify |
| `pgbackrest` | None (config only) | None | ✅ | repo-type is a variable; changing to s3 or gcs requires only config update |
| `app_deploy` | None | Docker (installed by role) | ✅ | Standard Docker install + docker run — provider-agnostic |

---

## Playbook Portability Table

| Playbook | Cloud calls? | Portable? | Notes |
|---|---|---|---|
| `pg_ha.yml` | None | ✅ | Full HA stack — works on any SSH target |
| `wg_tunnel.yml` | None | ✅ | WireGuard tunnel setup — works on any Linux VM |
| `app_deploy.yml` | None | ✅ | Docker deploy — works on any Linux VM |
| `pg_dr.yml` | None | ✅ | PostgreSQL DR replication config — works on any Linux VM |
| `pgbackrest.yml` | None | ✅ | pgBackRest install + config — repo backend is variable |
| `app_db_setup.yml` | None | ✅ | Standard SQL — no cloud calls |
| `onprem.yml` | None | ✅ on-prem | Master playbook for on-prem stack |
| `arc-onboard-servers.yml` | **Azure Arc API** | ❌ Azure-only | Azure-specific; skip for AWS/GCP deployments |

---

## What Needs Updating for AWS or GCP

### 1. New inventory file

```ini
# inventories/aws-dr-euc1/hosts.ini

[pg_dr]
pg-dr-aws ansible_host=<AWS_VM_PUBLIC_IP> ansible_user=ubuntu

[all:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519_dr_aws
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### 2. New group_vars

```yaml
# inventories/aws-dr-euc1/group_vars/pg_dr.yml
pg_primary_host: 10.200.0.1        # on-prem tunnel IP
pg_primary_port: 5432
wg_tunnel_ip: 10.200.0.6/30        # AWS DR VM tunnel IP
wg_onprem_public_ip: <ISP_IP>
```

### 3. Run existing playbooks targeting new inventory

```bash
ansible-playbook -i inventories/aws-dr-euc1/hosts.ini wg_tunnel.yml
ansible-playbook -i inventories/aws-dr-euc1/hosts.ini pg_dr.yml
```

No role changes required.

---

## DR Scripts Portability

All scripts in `scripts/dr/` use only:
- `ssh` — works with any SSH target
- `psql` — works with any PostgreSQL server
- `systemctl` — works on any systemd Linux
- `curl` — HTTP health check, provider-agnostic
- `wg show` — WireGuard CLI, provider-agnostic

To use DR scripts with an AWS or GCP DR VM, update the SSH config to add the new host:

```
# ~/.ssh/config addition for AWS DR VM
Host pg-dr-aws
  HostName <ELASTIC_IP>
  User ubuntu
  IdentityFile ~/.ssh/id_ed25519_dr_aws
  ServerAliveInterval 10
```

Then update `dr-preflight.sh` and `fullsite-failover.sh` with the new `DR_HOST` variable pointing to `pg-dr-aws`.

No logic changes required.

---

## pgBackRest Backend Change (one-time config update)

To switch pgBackRest to S3 or GCS, update `/etc/pgbackrest/pgbackrest.conf` on pg-primary:

```ini
# Current (Azure Blob Storage)
[global]
repo1-type=azure
repo1-azure-account=clopr2backupkatar
repo1-azure-container=pgbackrest

# AWS S3 replacement
[global]
repo1-type=s3
repo1-s3-bucket=clopr2-pgbackrest
repo1-s3-region=eu-central-1
repo1-s3-key=<access-key>
repo1-s3-key-secret=<secret-key>

# GCP GCS replacement
[global]
repo1-type=gcs
repo1-gcs-bucket=clopr2-pgbackrest
repo1-gcs-key=/etc/pgbackrest/gcs-key.json
```

The stanza name, backup schedule, and all restore commands are identical.
This is the most portable component in the entire stack.

---

## What Cannot Be Made Ansible-Portable

| Component | Reason |
|---|---|
| Azure Arc onboarding | Azure-specific registration workflow |
| AKS deployment | `az aks` commands and Azure-specific Kubernetes configuration |
| Managed Identity bootstrap | Cloud-specific identity assignment at VM creation time |
| Key Vault secret injection | Azure-specific CLI; replaced by provider's equivalent at deploy time |
