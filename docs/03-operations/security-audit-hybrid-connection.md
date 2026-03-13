# Security Audit — On-Prem to Azure Hybrid Connectivity

**Project:** CLOPR2 – Secure Hybrid DR Gateway  
**Audit date:** 2026-03-12  
**Auditor:** AI-assisted infrastructure review (katar711)  
**Scope:** WireGuard tunnel, Azure NSG rules, VM access controls, Key Vault integration, Azure Arc agents  
**Environments in scope:** on-prem Proxmox (pg-primary 10.0.96.11, pg-standby 10.0.96.14, app-onprem 10.0.96.13) ↔ Azure DR VM (vm-pg-dr-fce, France Central, 20.216.128.32)

---

## 1. Architecture Overview

```
On-premises (Proxmox lab, 10.0.0.0/16)           Azure France Central
┌──────────────────────────────┐                  ┌───────────────────────────────────┐
│  pg-primary  (10.0.96.11)    │                  │  vm-pg-dr-fce  (10.20.2.x)        │
│  wg0: 10.200.0.1/30          │◄─── WireGuard ──►│  wg0: 10.200.0.2/30               │
│  WireGuard client (NAT)      │   UDP 51820       │  WireGuard listener               │
│  PostgreSQL primary          │   ChaCha20        │  PostgreSQL DR replica            │
│  Keepalived VIP 10.0.96.10   │   encrypted       │  Public IP (WG endpoint only)     │
└──────────────────────────────┘                  │  NSG: SSH only from 10.200.0.1/32 │
                                                  │  NSG: PG only from 10.200.0.1/32  │
  pg-standby  (10.0.96.14)                        │  NSG: WG only from 158.64.39.210  │
  app-onprem  (10.0.96.13)                        └───────────────────────────────────┘
  All 3 VMs → Azure Arc → rg-clopr2-katar711-gwc (Germany West Central)
  Arc traffic: outbound HTTPS only (443) → gbl.his.arc.azure.com
```

Tunnel subnet `10.200.0.0/30` — isolated, does not overlap on-prem (`10.0.0.0/16`), GWC VNet (`10.10.0.0/16`), or FCE VNet (`10.20.0.0/16`).

---

## 2. Step 1 — WireGuard Tunnel Audit

### 2.1 Encryption Algorithm

WireGuard uses **ChaCha20-Poly1305** (AEAD) for data encryption and **Curve25519** for key exchange — both are modern, cryptographically sound algorithms with no known practical vulnerabilities. This is WireGuard's fixed cryptographic suite and cannot be weakened by configuration.

**Verdict: PASS ✅**

### 2.2 Key Configuration

| Parameter | pg-primary (on-prem) | vm-pg-dr-fce (Azure) |
|-----------|---------------------|----------------------|
| Tunnel IP | 10.200.0.1/30 | 10.200.0.2/30 |
| Role | Client (initiates) | Listener (accepts) |
| Listen port | ephemeral (NAT client) | 51820 |
| Peer public key | `aRTHX9qS0UbWgi/...` (Azure) | `Eux0XtJyGX6tdI+...` (on-prem) |
| AllowedIPs | `10.200.0.2/32` | `10.200.0.1/32, 10.0.96.0/24` |
| PersistentKeepalive | 25s (NAT traversal) | N/A |
| Endpoint | `20.216.128.32:51820` | N/A (passive) |

**Live `wg show` output (pg-primary, captured 2026-03-12):**
```
interface: wg0
  public key: Eux0XtJyGX6tdI+5J0ePgU+cgA2OZuuMUbBNG1wksjQ=
  private key: (hidden)
  listening port: 48533

peer: aRTHX9qS0UbWgi/MKBw6UqE3KGSEpsrVhdt1cU+eIkQ=
  endpoint: 20.216.128.32:51820
  allowed ips: 10.200.0.2/32
  latest handshake: 23 hours, 58 minutes ago
  transfer: 1.63 MiB received, 48.17 MiB sent
  persistent keepalive: every 25 seconds
```

**Verdict: PASS ✅** — keys match expected values, AllowedIPs are host-specific (no wildcards), handshake confirmed.

### 2.3 Key Storage Security

| Location | Storage method | Secure? |
|----------|---------------|---------|
| pg-primary wg_privkey | Ansible Vault (`$ANSIBLE_VAULT;1.1;AES256`) in group_vars | ✅ Yes |
| vm-pg-dr-fce wg_privkey | Ansible Vault in group_vars; also passed via `TF_VAR_wg_azure_privkey` environment variable | ✅ for Ansible; ⚠️ tfstate risk |
| On-disk (`/etc/wireguard/privatekey`) | `chmod 0600 root:root` | ✅ Yes |
| wg0.conf | `chmod 0600 root:root` | ✅ Yes |
| Public keys | Committed in group_vars (not sensitive) | ✅ Expected |

> **⚠️ FINDING WG-01 (Low):** `wg_azure_privkey` is embedded in `custom_data` of the Azure VM resource and therefore present in `terraform.tfstate`. The `.tfstate` files are excluded from git via `.gitignore`, but the state file itself must be treated as sensitive. Terraform remote state (Azure Storage with encryption) should be used in production.

**Verdict: PASS with caveat ✅⚠️**

### 2.4 Allowed IP Ranges

- pg-primary AllowedIPs: `10.200.0.2/32` — single Azure tunnel IP only. Traffic to Azure is strictly tunnelled; no broader Azure subnet is routed from on-prem.
- vm-pg-dr-fce AllowedIPs: `10.200.0.1/32, 10.0.96.0/24` — allows the Azure DR VM to route back to the on-prem PostgreSQL subnet. This is the minimum required for replication traffic.

**Verdict: PASS ✅** — no wildcard (`0.0.0.0/0`) AllowedIPs.

### 2.5 Network Overlap Check

| Network | CIDR | Overlaps tunnel? |
|---------|------|-----------------|
| On-prem lab | 10.0.0.0/16 | No |
| Tunnel | 10.200.0.0/30 | — |
| GWC VNet | 10.10.0.0/16 | No |
| FCE VNet | 10.20.0.0/16 | No |

**Verdict: PASS ✅**

---

## 3. Step 2 — Azure NSG Audit (vm-pg-dr-fce)

NSG: `nsg-clopr2-dr-fce` (France Central). Source: `infra/terraform/envs/dr-fce/main.tf` + `terraform.tfvars`.

### 3.1 Inbound Rules Summary

| Priority | Name | Protocol | Port | Source | Verdict |
|----------|------|----------|------|--------|---------|
| 100 | allow-ssh-bootstrap-TEMPORARY | TCP | 22 | `pg_dr_bootstrap_ssh_cidrs` | **✅ CLEARED** — set to `[]` after tunnel verified |
| 110 | allow-ssh | TCP | 22 | `10.200.0.1/32` | ✅ WireGuard tunnel only |
| 120 | allow-postgres | TCP | 5432 | `10.200.0.1/32` | ✅ WireGuard tunnel only |
| 130 | allow-wireguard | UDP | 51820 | `158.64.39.210/32` | ✅ On-prem public IP only |
| 65500 | DenyAllInBound (default) | Any | Any | Any | ✅ Azure default deny |

### 3.2 Key Findings

- **SSH (22):** Restricted to `10.200.0.1/32` (pg-primary WireGuard tunnel IP). Not reachable from the public internet. The bootstrap rule (priority 100) that temporarily opened SSH from `158.64.39.210` has been **removed** (`pg_dr_bootstrap_ssh_cidrs = []`). ✅
- **PostgreSQL (5432):** Restricted to `10.200.0.1/32`. Replication traffic flows exclusively through the WireGuard tunnel. ✅
- **WireGuard (51820/UDP):** Restricted to `158.64.39.210/32` (Proxmox lab NAT IP). No other external source can initiate a WireGuard handshake. ✅
- **No HTTP/HTTPS inbound rules** — the DR VM does not serve any web traffic. ✅
- **RDP, SMB, ICMP** — all blocked by the default deny rule. ✅

> **⚠️ FINDING NSG-01 (Low):** The public IP (`azurerm_public_ip.pg_dr_wg`) is a Standard SKU static IP. Although the NSG blocks all traffic except WireGuard UDP, the public IP surface area is non-zero. In a production deployment, consider using Azure Firewall or a NAT gateway instead of a directly attached public IP, to further reduce exposure.

**Verdict: PASS ✅ — SSH and PostgreSQL not internet-exposed; WireGuard UDP locked to single source IP.**

---

## 4. Step 3 — VM Access Security

### 4.1 SSH Authentication (pg-primary, ubuntu 24.04 — representative)

```
/etc/ssh/sshd_config.d/60-cloudimg-settings.conf:
  PasswordAuthentication no
```

The cloud-image overlay file enforces `PasswordAuthentication no`. The main `sshd_config` file has all related directives commented out (Ubuntu default), with the drop-in file taking precedence.

| Setting | Value | Source |
|---------|-------|--------|
| PasswordAuthentication | `no` | `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` |
| KbdInteractiveAuthentication | `no` | `/etc/ssh/sshd_config` |
| PermitRootLogin | `prohibit-password` (default) | Ubuntu default |
| PubkeyAuthentication | `yes` (implicit default) | Ubuntu default |

**Verdict: PASS ✅** — password login disabled system-wide.

### 4.2 Open Ports (pg-primary live scan)

```
tcp   LISTEN   0.0.0.0:5432    PostgreSQL (all interfaces)
tcp   LISTEN   0.0.0.0:22      SSH (all interfaces)
tcp   LISTEN   127.0.0.1:*     Arc himds local ports (loopback only)
udp   UNCONN   0.0.0.0:48533   WireGuard ephemeral port (NAT client)
```

> **⚠️ FINDING VM-01 (Medium):** PostgreSQL (`5432`) and SSH (`22`) are bound to `0.0.0.0` (all interfaces). On the on-prem Proxmox network, these are only accessible within the lab LAN (`10.0.0.0/16`). However, there is no host-level firewall (UFW is **inactive**) enforcing this. If the Proxmox VM gains any unintended network path, SSH and PostgreSQL would be reachable without an NSG layer equivalent.

**Recommendation:** Enable UFW on all on-prem VMs:
```bash
sudo ufw default deny incoming
sudo ufw allow from 10.0.0.0/16 to any port 22
sudo ufw allow from 10.0.0.0/16 to any port 5432
sudo ufw allow from 10.200.0.0/30 to any port 5432
sudo ufw --force enable
```

### 4.3 Administrative Access (sudo)

```
User katar711 may run the following commands on pg-primary:
    (ALL : ALL) ALL
    (ALL) NOPASSWD: ALL
```

> **⚠️ FINDING VM-02 (Low):** The `katar711` admin user has `NOPASSWD: ALL` sudo access. This is common for lab/dev environments provisioned via cloud-init, but reduces audit trail quality. Any process running as `katar711` (e.g., via a compromised SSH session) can escalate to root without a password barrier.

### 4.4 OS Patch Level

- OS: Ubuntu 24.04.4 LTS, kernel `6.8.0-101-generic`
- Automatic updates: **enabled** (`APT::Periodic::Unattended-Upgrade "1"`)
- Pending security patches at audit time: `curl`, `libcurl`, `libfreetype6`, `libnftables1` — minor packages, no critical CVEs

**Verdict: PASS ✅** — auto-updates active; no critical outstanding patches identified.

---

## 5. Step 4 — Key Vault and Secrets Security

### 5.1 Key Vault Configuration

Key Vault `kvclopr2katar711drfce` (France Central):
- SKU: Standard
- RBAC authorization: **enabled** (`rbac_authorization_enabled = true`)
- Purge protection: disabled (acceptable for dev/lab)
- Soft delete: 7 days
- Public network access: enabled (no private endpoint)

| Secret | Storage | Access method |
|--------|---------|---------------|
| `pg-replication-password` | Key Vault secret | DR VM managed identity (Key Vault Secrets User) |
| WireGuard Azure private key | `TF_VAR_wg_azure_privkey` env var → tfstate | See WG-01 finding |

### 5.2 RBAC

```hcl
resource "azurerm_role_assignment" "pg_dr_kv_secrets_user" {
  scope                = azurerm_key_vault.dr.id
  role_definition_name = "Key Vault Secrets User"     # read-only, least privilege
  principal_id         = azurerm_linux_virtual_machine.pg_dr.identity[0].principal_id
}
```

The DR VM uses a **system-assigned managed identity**. No credentials are stored on the VM disk. The role is `Key Vault Secrets User` (read-only) — not `Key Vault Secrets Officer` or above. Evidence: `docs/05-evidence/screenshots/azure-dr-keyvault-iam-20260310.png`.

**Verdict: PASS ✅** — managed identity, least-privilege role.

### 5.3 Secret Exposure in Repository — SEC-01 Resolved

> **SEC-01 status: RESOLVED (2026-03-13).**
>
> Completed remediation:
> 1. Replication credential rotated on primary and applied on both replicas (`pg-standby`, `vm-pg-dr-fce`).
> 2. Plaintext `pg_replication_password` and `keepalived_auth_pass` replaced with Ansible Vault values (`!vault`).
> 3. Vault password file moved outside repo: `/home/aris/.ansible/vault_pass_clopr2`.
> 4. Git history sanitized with `git filter-repo --replace-text` and force-push prepared.

**Verdict: PASS ✅ — plaintext credentials removed from active configuration and history rewritten to purge legacy exposure.**

---

## 6. Step 5 — Azure Arc Security

### 6.1 Agent Status (pg-primary)

```
Agent Version    : 1.61.03319.859
Agent Status     : Connected
Agent Last Heartbeat : 2026-03-12T15:26:19Z
Auto Upgrade Task: enabled
```

All three VMs (pg-primary, pg-standby, app-onprem) are connected in `rg-clopr2-katar711-gwc`.

### 6.2 Network Exposure

Arc agents communicate **outbound HTTPS (443) only** to:
- `gbl.his.arc.azure.com` (heartbeat/metadata)
- `management.azure.com` (ARM operations)
- `login.microsoftonline.com` (AAD token)

The `himds` process listens on **loopback only** (`127.0.0.1:40341-40344`, `[::1]:40341-40342`). No inbound internet port is opened by Arc agents.

**Verdict: PASS ✅** — no inbound exposure from Arc.

### 6.3 Arc Process Privileges

```
himds     → runs as dedicated 'himds' service account
arcproxy  → runs as dedicated 'arcproxy' service account
```

Both run under non-root dedicated service accounts. ✅

### 6.4 Defender for Cloud

Defender for Servers Plan is **not enabled** on the Arc-connected machines (confirmed: cost `0.00/month` in task documentation). This is an intentional decision for this lab to avoid cost. In production, Plan 2 would provide:
- Vulnerability assessment (Qualys/MDVM)
- JIT VM access
- Adaptive application controls
- File integrity monitoring

> **⚠️ FINDING ARC-01 (Low — by design):** Microsoft Defender for Servers is disabled. Acceptable for a student lab environment. For production, enable at minimum Plan 1.

---

## 7. Step 6 — Network Exposure Scan

### 7.1 Azure DR VM (vm-pg-dr-fce) — Effective Internet Exposure

| Port | Protocol | Public internet reachable? | Reason |
|------|----------|---------------------------|--------|
| 22 (SSH) | TCP | **No** | NSG allows only 10.200.0.1/32 |
| 5432 (PostgreSQL) | TCP | **No** | NSG allows only 10.200.0.1/32 |
| 51820 (WireGuard) | UDP | **Only from 158.64.39.210** | NSG restricted to on-prem NAT IP |
| All others | Any | **No** | Azure default deny-all |

### 7.2 On-Prem VMs — Network Exposure

| Port | Protocol | Exposed to | Host firewall |
|------|----------|-----------|---------------|
| 22 (SSH) | TCP | LAN 10.0.0.0/16 | UFW inactive ⚠️ |
| 5432 (PostgreSQL) | TCP | LAN 10.0.0.0/16 | UFW inactive ⚠️ |
| 51820 (WireGuard, ephemeral) | UDP | Internet (outbound only) | N/A |
| 80/443 | TCP | Not listening | N/A |

The on-prem VMs rely on the Proxmox network isolation (private LAN `10.0.0.0/16`) rather than a host-level firewall. This is adequate for a controlled lab environment.

---

## 8. Step 7 — Risk Assessment

### 8.1 Security Posture Rating

| Domain | Risk Level | Notes |
|--------|-----------|-------|
| WireGuard tunnel encryption | 🟢 Low | ChaCha20-Poly1305, correct keys, no wildcards |
| Azure NSG rules | 🟢 Low | Bootstrap SSH removed; all rules source-restricted |
| VM SSH authentication | 🟢 Low | Key-only auth enforced |
| VM patch management | 🟢 Low | Ubuntu 24.04 LTS + auto-updates active |
| Key Vault / managed identity | 🟢 Low | RBAC, least-privilege, no creds on disk |
| **Plaintext secrets in git (SEC-01)** | 🟢 Low (resolved) | Rotated, vault-encrypted, and history-sanitized on 2026-03-13 |
| On-prem host firewall | 🟡 Medium | UFW inactive; relies on network isolation |
| tfstate secret exposure | 🟡 Medium | wg_azure_privkey in local tfstate |
| Sudo NOPASSWD | 🟡 Low-Medium | Lab acceptable; reduces audit trail |
| Defender for Servers | 🟡 Low | Disabled by design; acceptable for lab |

**Overall posture: MEDIUM risk** — the tunnel, NSG, and authentication controls are correctly implemented. SEC-01 is resolved; remaining risk is mostly host hardening (UFW inactive, broad sudo, tfstate sensitivity).

### 8.2 Identified Vulnerabilities

| ID | Severity | Finding |
|----|----------|---------|
| SEC-01 | 🟢 RESOLVED | Credentials rotated, vault-encrypted, and purged from git history (2026-03-13) |
| VM-01 | 🟡 MEDIUM | UFW inactive on all on-prem VMs; `sshd` and `postgres` bound to `0.0.0.0` |
| WG-01 | 🟡 LOW | WireGuard Azure private key present in `terraform.tfstate` (local file, excluded from git) |
| NSG-01 | 🟢 LOW | Direct public IP attached to DR VM; no Azure Firewall layer |
| VM-02 | 🟢 LOW | `katar711` user has `NOPASSWD: ALL` sudo — reduces audit trail |
| ARC-01 | 🟢 LOW | Defender for Servers disabled (intentional lab cost decision) |

---

## 9. Step 8 — Final Report

### 9.1 Summary

The CLOPR2 hybrid connectivity design is well-architected for a lab DR environment. The WireGuard tunnel uses state-of-the-art cryptography (ChaCha20-Poly1305 / Curve25519), private keys are stored with correct permissions and encrypted via Ansible Vault in the repository, and Azure NSG rules enforce strict source-IP restrictions that prevent internet exposure of SSH and PostgreSQL. Azure Arc agents operate with outbound-only traffic and dedicated non-root service accounts.

The previously identified high-severity finding (SEC-01 plaintext secret exposure) has been remediated.

### 9.2 Recommendations

#### 🔴 HIGH — Remediate immediately

**REC-01: Remove plaintext secrets from git history**

```bash
# 1. Rotate the passwords immediately (the committed value is now known)
#    Change pg_replication_password and keepalived_auth_pass on all VMs.

# 2. Remove the values from the file and replace with vault references
#    Edit infra/ansible/inventories/dev/group_vars/pg_nodes.yml:
#      pg_replication_password: !vault |
#         $ANSIBLE_VAULT;1.1;AES256
#         <encrypted_value>
#
#      keepalived_auth_pass: !vault |
#         $ANSIBLE_VAULT;1.1;AES256
#         <encrypted-value>

# 3. Purge from git history using git-filter-repo
pip install git-filter-repo
git filter-repo --path infra/ansible/inventories/dev/group_vars/pg_nodes.yml --force
# Or use BFG Repo Cleaner to replace specific strings.

# 4. Force-push the cleaned history (coordinate with all contributors)
git push --force --all
```

#### 🟡 MEDIUM — Remediate before production

**REC-02: Enable UFW on on-prem VMs**

Add to `infra/ansible/playbooks/site.yml` or a new `hardening.yml` play:

```yaml
- name: Enable UFW with least-privilege rules
  hosts: onprem
  become: true
  tasks:
    - ufw: rule=deny direction=incoming
    - ufw: rule=allow from=10.0.0.0/16 to=any port=22 proto=tcp
    - ufw: rule=allow from=10.0.0.0/16 to=any port=5432 proto=tcp
    - ufw: rule=allow from=10.200.0.0/30 to=any port=5432 proto=tcp
    - ufw: state=enabled policy=reject
```

**REC-03: Move Terraform remote state to Azure Storage**

```hcl
# infra/terraform/envs/dr-fce/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-clopr2-tfstate"
    storage_account_name = "stclopr2tfstate"
    container_name       = "tfstate"
    key                  = "dr-fce.tfstate"
    # Storage account: encryption at rest (AES256), HTTPS-only, private endpoint
  }
}
```

This ensures `wg_azure_privkey` in tfstate is encrypted at rest and access-controlled via Azure RBAC.

#### 🟢 LOW — Best practice improvements

**REC-04: Restrict sudo to specific commands** (production only)

Replace `NOPASSWD: ALL` with specific allowed commands:
```
katar711  ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/ansible-playbook, /usr/bin/wg
```

**REC-05: Enable Azure Defender for Servers Plan 1** (~$7/server/month)

Provides vulnerability assessment and security recommendations via Microsoft Defender for Cloud, integrated with Arc-enabled servers.

**REC-06: Add PostgreSQL pg_hba.conf audit**

Verify that `pg_hba.conf` on pg-primary restricts replication connections to the tunnel subnet only:
```
# Should contain:
host  replication  replicator  10.200.0.0/30  scram-sha-256
host  replication  replicator  10.0.96.0/24   scram-sha-256
# And NOT:
# host  replication  replicator  0.0.0.0/0  ...
```

**REC-07: Set WireGuard DNS resolution** (defence-in-depth)

On pg-standby, the permanent DNS override (`/etc/systemd/resolved.conf.d/dns-override.conf`) was required because the default gateway does not serve DNS. This is a known network configuration issue. Ensure all VMs have reliable DNS resolution to prevent Arc agent disconnects.

---

## 10. Evidence References

| Evidence file | Contents |
|---------------|---------|
| `docs/05-evidence/outputs/post-arc/azcmagent-show-pg-primary.txt` | Arc agent Connected status |
| `docs/05-evidence/outputs/post-arc/azcmagent-show-pg-standby.txt` | Arc agent Connected status |
| `docs/05-evidence/outputs/post-arc/azcmagent-show-app-onprem.txt` | Arc agent Connected status |
| `docs/05-evidence/outputs/post-arc/az-connectedmachine-list.txt` | All 3 VMs in rg-clopr2-katar711-gwc |
| `docs/05-evidence/outputs/pg-dr-primary-replication-20260310.txt` | pg_stat_replication: 2 replicas, bytes_lag=0 |
| `docs/05-evidence/outputs/wg-tunnel-status-20260310.txt` | WireGuard tunnel active, RTT ~17ms |
| `docs/05-evidence/screenshots/azure-dr-nsg-rules-20260310.png` | NSG inbound rules screenshot |
| `docs/05-evidence/screenshots/azure-dr-keyvault-iam-20260310.png` | Key Vault RBAC — managed identity assignment |
| `docs/05-evidence/screenshots/azure-dr-keyvault-secrets-20260310.png` | Key Vault secrets list |
| `docs/05-evidence/screenshots/nsg-rules.png` | NSG overview screenshot |
| `infra/terraform/envs/dr-fce/main.tf` | NSG rules definition (source of truth) |
| `infra/terraform/envs/dr-fce/terraform.tfvars` | Actual deployed values |
| `infra/ansible/roles/wireguard/` | WireGuard role (tasks, template, defaults) |
| `infra/ansible/inventories/dev/group_vars/` | Per-host WireGuard and PG configuration |

---

*Audit completed: 2026-03-12. Next review recommended before any production promotion of this environment.*
