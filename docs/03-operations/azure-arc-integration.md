# Azure Arc Hybrid Management Integration

**Status:** Additional sprint task — completed on top of finished core DR implementation  
**Date added:** 2026-03-12  
**Author:** KATAR711  
**Risk to DR stack:** None

---

## Purpose

Azure Arc projects the on-prem Proxmox VMs (pg-primary, pg-standby, app-onprem) into the Azure Resource Manager plane as first-class Azure resources. This enables:

- Single pane of glass: on-prem nodes visible in Azure portal alongside the Azure DR VM
- Azure Policy guest configuration audits on on-prem VMs (AZ-500 compliance posture)
- Defender for Cloud coverage extended to the on-prem tier
- Azure Monitor Agent telemetry from on-prem VMs into the existing Log Analytics workspace
- RBAC governance via the existing BCLC24 role assignments applied to Arc server resources

Azure Arc is a **read-only management projection**. It does not:
- Carry database replication traffic
- Interact with PostgreSQL, Keepalived, or WireGuard
- Modify any network routing, iptables rules, or service configuration
- Replace the WireGuard tunnel or the Azure DR replica

---

## Architecture Impact

```
Before Arc:
  Azure Portal → Azure resources only (AKS, DR VM, Key Vault, etc.)
  On-prem tier → invisible from Azure management plane

After Arc:
  Azure Portal → Azure resources + Arc-enabled servers
                 ├── pg-primary   (Arc-enabled server ← rg-clopr2-katar711-gwc)
                 ├── pg-standby   (Arc-enabled server ← rg-clopr2-katar711-gwc)
                 └── app-onprem   (Arc-enabled server ← rg-clopr2-katar711-gwc)

DR path (UNCHANGED):
  pg-primary → WireGuard (10.200.0.1 ↔ 10.200.0.2) → Azure DR VM
  pg-primary → streaming replication → pg-standby (10.0.96.14)
  Keepalived VIP 10.0.96.10 → transparent HA on-prem
```

The Arc management plane communicates outbound HTTPS (TCP 443) only. It is completely orthogonal to:
- WireGuard (UDP 51820)
- PostgreSQL replication (TCP 5432 on WireGuard tunnel)
- Keepalived VRRP (protocol 112 on LAN)

---

## Prerequisites

### 1. Azure resource providers
Register before first Arc onboarding:
```bash
az provider register --namespace Microsoft.HybridCompute
az provider register --namespace Microsoft.GuestConfiguration
az provider register --namespace Microsoft.HybridConnectivity

# Verify (wait ~2 min for Registered status)
az provider show --namespace Microsoft.HybridCompute \
  --query "registrationState" -o tsv
```

### 2. Outbound HTTPS from on-prem VMs
Each VM must reach the following endpoints on TCP 443:
- `*.his.arc.azure.com`
- `guestnotificationservice.azure.com`
- `management.azure.com`
- `login.microsoftonline.com`
- `*.guestconfiguration.azure.com`
- `*.blob.core.windows.net`

Pre-check from each VM:
```bash
curl -sI --max-time 10 https://management.azure.com
```

### 3. RBAC
No new role assignments needed. The existing `BCLC24-OPS-ADMINS` group has `Contributor` at `rg-clopr2-katar711-gwc` scope, which covers Arc server onboarding.

---

## Onboarding Process

### Phase 1 — Pre-check and baseline capture

Run the Ansible playbook with `precheck` tags:
```bash
cd infra/ansible
ansible-playbook -i inventories/dev playbooks/arc-onboard-servers.yml \
  --tags precheck
```

Save baseline outputs manually:
```bash
# From pg-primary:
ssh pg-primary

sudo systemctl status keepalived --no-pager \
  > /tmp/pre-arc-keepalived-pg-primary.txt

sudo wg show \
  > /tmp/pre-arc-wg-status.txt

sudo -u postgres psql -c \
  "SELECT client_addr, state, write_lag FROM pg_stat_replication;" \
  > /tmp/pre-arc-pg-stat-replication.txt

# From pg-standby:
ssh pg-standby
sudo -u postgres psql -tc "SELECT pg_is_in_recovery();" \
  > /tmp/pre-arc-pg-is-in-recovery.txt
```

Fetch files to evidence store:
```bash
scp pg-primary:/tmp/pre-arc-*.txt \
  docs/05-evidence/outputs/pre-arc/

scp pg-standby:/tmp/pre-arc-pg-is-in-recovery.txt \
  docs/05-evidence/outputs/pre-arc/
```

### Phase 2 — Install Arc agent (Ansible)

```bash
cd infra/ansible
ansible-playbook -i inventories/dev playbooks/arc-onboard-servers.yml \
  --tags install
```

The playbook:
1. Downloads `https://aka.ms/azcmagent` install script to each VM
2. Installs the `azcmagent` binary
3. Enables and starts the `himds` and `gcad` systemd services
4. Asserts that `keepalived` and `postgresql` are still active post-install

Expected output: All tasks green, keepalived assertion passes on pg-primary and pg-standby.

### Phase 3 — Connect to Azure Arc (interactive, per VM)

Run manually on each VM after Ansible install. Device code auth requires a browser.

**pg-primary:**
```bash
ssh pg-primary

sudo azcmagent connect \
  --resource-group rg-clopr2-katar711-gwc \
  --subscription-id <YOUR_SUBSCRIPTION_ID> \
  --location germanywestcentral \
  --tags "project=clopr2,node=pg-primary,env=dev,owner=katar711" \
  --use-device-code
```
When prompted: go to `https://microsoft.com/devicelogin`, enter the displayed code, and authenticate with your BCLC24 account.

**pg-standby:**
```bash
ssh pg-standby

sudo azcmagent connect \
  --resource-group rg-clopr2-katar711-gwc \
  --subscription-id <YOUR_SUBSCRIPTION_ID> \
  --location germanywestcentral \
  --tags "project=clopr2,node=pg-standby,env=dev,owner=katar711" \
  --use-device-code
```

**app-onprem:**
```bash
ssh app-onprem

sudo azcmagent connect \
  --resource-group rg-clopr2-katar711-gwc \
  --subscription-id <YOUR_SUBSCRIPTION_ID> \
  --location germanywestcentral \
  --tags "project=clopr2,node=app-onprem,env=dev,owner=katar711" \
  --use-device-code
```

After each connect: verify in Azure portal → Azure Arc → Servers. Status must show **Connected**.

### Phase 4 — Post-connect validation (Ansible)

```bash
cd infra/ansible
ansible-playbook -i inventories/dev playbooks/arc-onboard-servers.yml \
  --tags postcheck
```

The playbook validates:
- `azcmagent show` returns `Status: Connected` on all 3 VMs
- keepalived active on pg-primary and pg-standby
- VIP `10.0.96.10` still present on pg-primary
- `pg_stat_replication` still shows 2 replicas (10.0.96.14 and 10.200.0.2)
- `pg_is_in_recovery()=t` on pg-standby
- WireGuard shows active peer on pg-primary

Save post-Arc outputs:
```bash
# On pg-primary:
sudo azcmagent show > /tmp/post-arc-agentshow-pg-primary.txt
sudo systemctl status keepalived --no-pager > /tmp/post-arc-keepalived.txt
sudo wg show > /tmp/post-arc-wg-status.txt
sudo -u postgres psql -c \
  "SELECT client_addr, state, write_lag FROM pg_stat_replication;" \
  > /tmp/post-arc-pg-stat-replication.txt

# Fetch to evidence store:
scp pg-primary:/tmp/post-arc-*.txt docs/05-evidence/outputs/post-arc/
scp pg-standby:/tmp/post-arc-agentshow-pg-standby.txt docs/05-evidence/outputs/post-arc/
scp app-onprem:/tmp/post-arc-agentshow-app-onprem.txt docs/05-evidence/outputs/post-arc/
```

---

## Validation Results

> **Fill in after execution:**

| Check | pg-primary | pg-standby | app-onprem |
|---|---|---|---|
| Arc Status | Connected / Not yet | Connected / Not yet | Connected / Not yet |
| keepalived | Active / N/A | Active / N/A | N/A |
| VIP 10.0.96.10 | Present / N/A | N/A | N/A |
| WireGuard 10.200.0.2 | Up / N/A | N/A | N/A |
| pg_stat_replication | N replicas | N/A | N/A |
| pg_is_in_recovery | N/A | t / f | N/A |
| azcmagent show | Connected | Connected | Connected |

---

## Evidence Checklist

### Terminal outputs
Save to `docs/05-evidence/outputs/pre-arc/`:
- [ ] `pre-arc-keepalived-pg-primary-<date>.txt`
- [ ] `pre-arc-wg-status-<date>.txt`
- [ ] `pre-arc-pg-stat-replication-<date>.txt`
- [ ] `pre-arc-pg-is-in-recovery-<date>.txt`

Save to `docs/05-evidence/outputs/post-arc/`:
- [ ] `post-arc-agentshow-pg-primary-<date>.txt`
- [ ] `post-arc-agentshow-pg-standby-<date>.txt`
- [ ] `post-arc-agentshow-app-onprem-<date>.txt`
- [ ] `post-arc-keepalived-<date>.txt`
- [ ] `post-arc-wg-status-<date>.txt`
- [ ] `post-arc-pg-stat-replication-<date>.txt`

### Azure portal screenshots
Save to `docs/05-evidence/screenshots/`:
- [ ] `arc-servers-connected-<date>.png` — Azure Arc → Servers blade (all 3 Connected)
- [ ] `arc-pg-primary-overview-<date>.png` — Individual machine overview (pg-primary)
- [ ] `arc-rg-resources-<date>.png` — Resource group view with Arc + native resources
- [ ] `arc-defender-inventory-<date>.png` — Defender for Cloud → Inventory → Non-Azure

---

## Cost Impact

| Component | Monthly cost |
|---|---|
| Arc-enabled servers (3×) | **$0.00** — management plane is free |
| Azure Monitor Agent extension | **$0.00** |
| Log Analytics ingestion (under 5 GB free tier) | **$0.00** |
| Azure Policy built-in guest config audits | **$0.00** |

**Defender for Servers is NOT enabled.** Do not enable Plans 1 or 2 during or after onboarding.

To verify Defender is not charging:
- Azure portal → Defender for Cloud → Environment settings → your subscription
- Confirm "Defender for Servers" shows **Off**

---

## Rollback Procedure

If you decide to remove Arc after demo, run on each VM:

```bash
# Disconnect and remove from Azure Arc
sudo azcmagent disconnect --force

# This deletes the Arc machine resource from Azure (ARM resource gone within ~5 min).
# azcmagent binary remains installed but inactive — uninstall if desired:
sudo apt remove azcmagent       # Ubuntu/Debian
# or
sudo yum remove azcmagent       # RHEL/CentOS
```

Rollback is clean and complete:
- No DNS changes
- No network routing changes
- No replication configuration changes
- No PostgreSQL changes
- WireGuard tunnel unaffected

---

## DR Terraform Freeze Decision (2026-03-12)

> **Decision: `terraform apply` was NOT executed for `infra/terraform/envs/dr-fce`.**

### Background

On 2026-03-12, a `terraform plan` was run against the DR environment (`envs/dr-fce`) as part of a
pre-Arc infrastructure audit. The plan succeeded with no errors, but proposed the following
destructive change:

```
# azurerm_linux_virtual_machine.pg_dr must be replaced   (-/+)
  ~ custom_data = (sensitive value)  # forces replacement
```

The VM replacement cascade included:
- `azurerm_linux_virtual_machine.pg_dr` — destroy + recreate
- `azurerm_dev_test_global_vm_shutdown_schedule.pg_dr[0]` — cascades from VM ID change
- `azurerm_monitor_data_collection_rule_association.pg_dr` — cascades from VM ID change
- `azurerm_virtual_machine_extension.pg_dr_ama` — cascades from VM ID change
- `azurerm_role_assignment.pg_dr_kv_secrets_user` — cascades from managed identity change

### Root Cause

The `custom_data` field on `azurerm_linux_virtual_machine` contains the cloud-init WireGuard
bootstrap script rendered from `cloud_init.tftpl`, which includes the sensitive `wg_azure_privkey`
variable. Terraform hashes `custom_data` as a base64-encoded sensitive value and cannot diff it
against the live state — any supply of `TF_VAR_wg_azure_privkey` causes it to appear changed,
triggering a forced VM replacement.

This is **expected Terraform behavior** for cloud-init/bootstrap data on existing VMs. The live
value in `terraform.tfstate` (serial 34) was already applied when the DR VM was provisioned. The
tfvars values (`location=francecentral`, `pg_dr_vm_size=Standard_B2ats_v2`,
`pg_dr_allowed_ssh_cidrs=["10.200.0.1/32"]`, `pg_dr_onprem_cidrs=["10.200.0.1/32"]`) are all
correct and match the deployed state exactly. There is no misconfiguration.

### Decision

The DR VM (`vm-pg-dr-fce`) is **operational and stable**:
- WireGuard tunnel between `10.200.0.1` (pg-primary) and `10.200.0.2` (DR VM) is active
- PostgreSQL streaming replication (`10.0.96.14` + `10.200.0.2`) is confirmed running
- Azure Monitor Agent extension is deployed and sending telemetry

Recreating the VM would:
- Drop WireGuard connectivity during the rebuild window
- Interrupt streaming replication (requiring standby re-sync)
- Introduce unnecessary risk to the demo-ready environment
- Produce a new managed identity principal_id, requiring KV role-assignment recreation

**The team intentionally chose not to apply the Terraform plan.** The plan binary was saved at
`/tmp/tfplan-dr-fce-20260312.bin` as reference evidence only.

### Action Required Before Any Future Apply

If the DR VM must be recreated in future, the correct sequence is:

1. Stop `pg_receivewal` / pause streaming replication gracefully
2. Export `TF_VAR_wg_azure_privkey=$(cat /path/to/azure-wg-privkey)` from the stored key
3. Promote pg-standby (Keepalived failover) before VIP loss
4. Run `terraform apply` during a planned maintenance window
5. Re-run Ansible WireGuard setup against new VM IP (public IP may change)
6. Confirm replication resumes and re-validate with `--tags postcheck`

---

## References

- Assessment and planning doc: `docs/99-ai-appendix/azure-arc-assessment.md`
- Ansible playbook: `infra/ansible/playbooks/arc-onboard-servers.yml`
- Evidence index entry: `docs/05-evidence/evidence-index.md` → Arc row
- Architecture diagram: `docs/01-architecture/architecture-diagram.md`
- DR Terraform plan audit: `/tmp/tfplan-dr-fce-20260312.bin` (reference only — not applied)
- Terraform plan output: `docs/05-evidence/outputs/dr-fce-terraform-plan-20260312.txt`
