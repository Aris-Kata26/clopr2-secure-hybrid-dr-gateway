# Azure Arc Assessment & Implementation Plan
**Project:** CLOPR2 Secure Hybrid DR Gateway  
**Date:** 2026-03-12  
**Status:** Additional sprint task — does NOT reopen completed core infrastructure  
**Author note:** AI-assisted assessment; review and validate before execution.

---

## ⚠️ Important framing notice

This document covers Azure Arc as an **additional enhancement** on top of the completed core architecture. The following are **complete, stable, and must not be touched** by Arc onboarding:

- PostgreSQL 16 HA on-prem (pg-primary → pg-standby streaming replication, Keepalived VIP 10.0.96.10)
- Azure DR PostgreSQL replica (France Central) fed via WireGuard tunnel (10.200.0.1 ↔ 10.200.0.2)
- Prototype A: FastAPI on app-onprem, pointing at DB VIP only
- Prototype B: AKS cluster `aks-b2clc-katar-swe` in `rg-b2clc-katar-aks-swe` (Sweden Central)
- All evidence already captured and indexed

Arc is introduced purely as a **hybrid management/governance layer**. It replicates nothing, routes no database traffic, and does not touch replication or HA configuration.

---

## 1. Executive Summary

Azure Arc is a Microsoft hybrid management plane that projects non-Azure resources (on-prem VMs, VMs in other clouds, Kubernetes clusters) into the Azure Resource Manager (ARM) graph. Once a machine is "Arc-enabled", it appears as a first-class Azure resource: it gains a resource ID, can be governed by Azure Policy, monitored via Azure Monitor / Defender for Cloud, targeted by role assignments, and queried in Azure Resource Graph.

For CLOPR2, Arc offers the following value **without any change to the existing DR path**:

| What Arc adds | Value to this project |
|---|---|
| On-prem VMs visible in Azure portal | Single pane of glass — Proxmox VMs alongside Azure DR VM |
| Defender for Cloud coverage on on-prem VMs | AZ-500 security story becomes end-to-end |
| Azure Policy guest configuration on on-prem VMs | Compliance scanning without cloud migration |
| Azure Monitor Agent on on-prem VMs | On-prem logs into Log Analytics (extends existing workspace) |
| RBAC-governed access to on-prem machine resources | BCLC24 RBAC model now extends to on-prem tier |
| Arc-enabled Kubernetes on AKS | NOT needed — AKS is already in Azure |

**Recommended minimum scope for this sprint:**  
Onboard **pg-primary**, **pg-standby**, and **app-onprem** as Arc-enabled servers only. Optionally also onboard the Azure DR VM for completeness. Skip Arc-enabled Kubernetes.

**Risk to existing architecture:** Near-zero when implemented correctly. The Arc agent runs as a background daemon, opens outbound HTTPS only, and does not modify networking, replication, or service configuration.

---

## 2. Where Azure Arc Fits (and Where It Does Not)

### 2.1 What Arc IS in this project

```
Azure Portal (ARM)
│
├── rg-clopr2-katar711-gwc (Germany West Central)
│   ├── [existing] Azure DR VM (pg-dr-replica)
│   ├── [existing] AKS aks-b2clc-katar-swe
│   ├── [NEW - Arc] pg-primary (Arc-enabled server)
│   ├── [NEW - Arc] pg-standby (Arc-enabled server)
│   └── [NEW - Arc] app-onprem (Arc-enabled server)
│
└── Arc management plane reads metadata, policies, logs
    — does NOT touch PostgreSQL data, WireGuard, or Keepalived
```

Arc is a **management projection**, not a connectivity or routing layer.

### 2.2 What Arc is NOT in this project

| Common misconception | Reality |
|---|---|
| Arc replaces WireGuard tunnel | FALSE — Arc uses outbound HTTPS 443 only. WireGuard tunnel is for DB replication and must stay. |
| Arc replaces PostgreSQL replication | FALSE — Arc has no database awareness at this scope |
| Arc is needed to onboard AKS | FALSE — AKS is already a native Azure resource; Arc-enabled Kubernetes adds multi-cluster federation features not needed here |
| Arc requires Site-to-Site VPN | FALSE — Arc only needs outbound internet HTTPS from the on-prem VMs (port 443) |
| Arc changes Keepalived VIP behavior | FALSE — Arc agent is OS-level, doesn't interact with network VIPs |
| Arc-enabled data services (PostgreSQL for Arc) | OUT OF SCOPE — this is a paid, complex add-on that would duplicate your existing HA setup |

### 2.3 Arc applicability per machine

| Machine | Arc type | Recommended | Reason |
|---|---|---|---|
| pg-primary | Arc-enabled server | ✅ YES | HIGH VALUE: most important on-prem node; Defender + Monitor coverage |
| pg-standby | Arc-enabled server | ✅ YES | Completes HA coverage in Azure portal |
| app-onprem | Arc-enabled server | ✅ YES | Full on-prem tier visible from Azure |
| Azure DR VM (pg-dr-azure) | Arc-enabled server | ⚡ OPTIONAL | It's already a native Azure VM — Arc adds little; skip unless you want uniform coverage story |
| AKS cluster | Arc-enabled Kubernetes | ❌ SKIP | Already native Azure; no added value for this project scope |
| Azure Arc-enabled data services | Arc PostgreSQL | ❌ SKIP | Paid, heavyweight, conflicts with existing HA design |

---

## 3. Full Audit Findings

### 3.1 Architecture impact assessment

#### 3.1.1 PostgreSQL HA and Keepalived

**Risk: NONE**  
- Arc agent (`azcmagent`) runs as a systemd service on the host OS
- It has zero interaction with PostgreSQL processes, `pg_hba.conf`, replication slots, or keepalived/haproxy configuration
- Verification: After Arc agent install, run `systemctl status keepalived postgresql` — both must remain unchanged
- The VIP `10.0.96.10` is unaffected; Arc does not modify iptables, routing tables, or ARP behavior

#### 3.1.2 WireGuard tunnel (10.200.0.1 ↔ 10.200.0.2)

**Risk: NONE**  
- WireGuard uses UDP 51820 for its own encrypted channel
- Arc uses only outbound TCP 443 to Azure endpoints
- These are completely orthogonal tunnels on separate ports/protocols
- The only theoretical risk would be if NSG rules on the Azure side blocked Arc agent outbound — this is addressed in prerequisites below

#### 3.1.3 Existing NSGs and firewall rules

**Risk: LOW — requires outbound rule addition**  
- Arc-enabled servers require outbound HTTPS (TCP 443) from on-prem VMs to:
  - `*.his.arc.azure.com`
  - `guestnotificationservice.azure.com`
  - `management.azure.com`
  - `login.microsoftonline.com`
  - `*.guestconfiguration.azure.com`
  - `*.blob.core.windows.net` (for agent updates)
- If the Proxmox environment has a restrictive outbound firewall (iptables/ufw), these destinations must be allowed on port 443
- If Proxmox VMs already have unrestricted outbound internet (common in lab environments), no changes are needed
- The Azure DR VM's NSG already allows outbound 443 (required for yum/apt updates), so no change needed there

#### 3.1.4 Terraform/Ansible conflicts

**Risk: LOW with hybrid approach**  
- Terraform: The `azurerm_arc_machine` resource does not exist for bootstrapping (you cannot push an agent from Terraform to an on-prem VM). Terraform CAN manage the Azure-side Arc resources AFTER onboarding (policies, extensions, role assignments).
- Ansible: Arc provides an official Linux installation script (`azcmagent`). This is an ideal Ansible task.
- **Conclusion:** Onboarding is Ansible-driven; post-onboarding Azure governance is Terraform-driven. This is the cleanest split.

#### 3.1.5 Identity and RBAC

- Arc onboarding requires the executing identity (the person/SP running the install script) to have `Azure Connected Machine Onboarding` role **or** `Contributor` at the resource group scope
- Your existing `BCLC24-OPS-ADMINS` group has `Contributor` at RG scope — no new role assignments needed for onboarding
- Post-onboarding, Arc server resources inherit the existing RBAC model automatically
- For Defender for Cloud extension deployment, `Azure Connected Machine Resource Administrator` may be needed — Contributor covers this

#### 3.1.6 Cost strategy

- Arc-enabled servers (core): **FREE** — no charge for the Arc management plane itself
- Azure Monitor Agent (AMA) extension on Arc servers: **FREE** (data ingestion into Log Analytics has a free tier of 5 GB/month per workspace; existing workspace `log-clopr2-dev-gwc` already exists)
- Defender for Servers Plan 1 on Arc servers: ~$0.02/server/hour = ~$14.40/server/month — **opt-in only, skip for student budget**
- Defender for Servers Plan 2: ~$0.04/server/hour = ~$28.80/server/month — **definitely skip**
- Azure Policy guest configuration: **FREE** built-in policies; custom policies have audit costs
- **Bottom line:** Zero incremental cost if you only enable Arc core + AMA + built-in policies

#### 3.1.7 Evidence pack consistency

- Arc onboarding creates new Azure resources in your RG — these will appear in cost analysis, resource inventory, and Defender recommendations
- The evidence pack is already marked complete for US1–US11; Arc evidence should be captured under a new user story (US12 or Arc sprint item)
- No existing evidence is invalidated by adding Arc

### 3.2 Dependencies introduced by Arc

| Dependency | Impact |
|---|---|
| Outbound internet from on-prem VMs | Required — see endpoint list above |
| Azure Active Directory identity | Already exists (BCLC24 tenant) |
| Contributor or Onboarding role | Already covered by BCLC24-OPS-ADMINS |
| `azcmagent` package (~70 MB) | Installed on each on-prem VM |
| systemd | Already present on Ubuntu/Debian on Proxmox |
| Python 3 (for Ansible) | Already installed (Ansible prerequisite) |

---

## 4. Recommended Implementation Scope

### Minimum viable Arc scope for this sprint:

**Onboard 3 on-prem VMs as Arc-enabled servers only.**

```
IN SCOPE:
  ✅ pg-primary    → Arc-enabled server (with AMA extension for Log Analytics)
  ✅ pg-standby    → Arc-enabled server
  ✅ app-onprem    → Arc-enabled server

OUT OF SCOPE (this sprint):
  ❌ Azure DR VM            → already native Azure VM, skip
  ❌ Arc-enabled Kubernetes → AKS is native Azure, skip
  ❌ Defender for Servers   → paid add-on, skip for student budget
  ❌ Arc data services      → heavyweight, conflicts with existing HA, skip
```

### Why this exact scope:

1. **Maximum presentation value per effort unit** — three machines onboarded creates a compelling "unified hybrid view" in Azure portal with zero cost
2. **Zero DR risk** — Arc agent is read/metrics-only, not in the data path
3. **Extends existing investments** — the existing Log Analytics workspace gains on-prem telemetry, the RBAC model extends automatically, Defender for Cloud baseline improves
4. **Demonstrably on-topic for AZ-500** — guest configuration, policy compliance, and Defender coverage on on-prem servers are core AZ-500 themes

### Why NOT Arc-enabled Kubernetes on AKS:

AKS is already a native Azure resource with full Azure management plane integration. Arc-enabled Kubernetes is designed for clusters *outside* Azure (on-prem Kubernetes, EKS, GKE). Applying it to AKS would create redundant management overhead with no added value and would confuse reviewers.

---

## 5. Step-by-Step Implementation Plan

### Phase 0 — Audit / Pre-check (estimated: 30 min)

#### 0.1 Verify outbound internet from on-prem VMs
```bash
# Run from pg-primary, pg-standby, app-onprem
curl -sI https://management.azure.com | head -5
curl -sI https://login.microsoftonline.com | head -5
# Expect HTTP/1.1 4xx or redirect — confirms TCP 443 reachable
```

#### 0.2 Confirm Azure identity/role
```bash
# From your local terminal with az CLI
az role assignment list --assignee <your-UPN-or-group-id> \
  --resource-group rg-clopr2-katar711-gwc \
  --output table
# Confirm Contributor or Azure Connected Machine Onboarding role
```

#### 0.3 Confirm no existing Arc agents
```bash
# On each on-prem VM
which azcmagent && azcmagent show || echo "Arc agent not installed"
```

#### 0.4 Verify PostgreSQL and Keepalived baseline BEFORE Arc install
```bash
# Record pre-Arc state as evidence baseline
systemctl status keepalived --no-pager
systemctl status postgresql --no-pager
psql -U postgres -c "SELECT pg_is_in_recovery();"
# Save output to docs/05-evidence/outputs/pre-arc-baseline-<date>.txt
```

---

### Phase 1 — Azure Prerequisites (estimated: 15 min)

#### 1.1 Register required Azure resource providers
```bash
az provider register --namespace Microsoft.HybridCompute
az provider register --namespace Microsoft.GuestConfiguration
az provider register --namespace Microsoft.HybridConnectivity
# Verify registration
az provider show --namespace Microsoft.HybridCompute --query "registrationState"
```

#### 1.2 Generate Arc onboarding script from Azure portal

Option A — Azure portal:
1. Navigate to: Azure Arc → Servers → Add → Add multiple servers → Generate script
2. Select resource group: `rg-clopr2-katar711-gwc`
3. Region: `France Central` (match DR VM region) or `Germany West Central` (match main RG)
4. OS: Linux
5. Download or copy the generated `install_linux_azcmagent.sh`

Option B — Azure CLI:
```bash
# The portal script generator is the cleanest approach for a one-time onboarding
# Use Option A for the install script; Terraform can manage extensions afterward
```

#### 1.3 (Optional) Create a dedicated service principal for Arc onboarding
For a lab/student project, using your personal credentials interactively is fine. If you want to demonstrate automation:
```bash
az ad sp create-for-rbac \
  --name "sp-arc-onboard-clopr2" \
  --role "Azure Connected Machine Onboarding" \
  --scopes "/subscriptions/<sub-id>/resourceGroups/rg-clopr2-katar711-gwc"
# Save the appId, password, tenant to Key Vault or .env (never commit to git)
```

---

### Phase 2 — Implementation (estimated: 45 min)

#### 2.1 Ansible playbook for Arc agent installation

Create: `infra/ansible/playbooks/arc-onboard-servers.yml`

```yaml
---
# Azure Arc onboarding for on-prem servers
# Prerequisites: outbound HTTPS 443 confirmed, resource providers registered
# Run: ansible-playbook -i inventories/dev/hosts.ini playbooks/arc-onboard-servers.yml

- name: Onboard on-prem servers as Azure Arc-enabled servers
  hosts: onprem_servers  # pg-primary, pg-standby, app-onprem
  become: true
  vars:
    arc_resource_group: "rg-clopr2-katar711-gwc"
    arc_subscription_id: "{{ lookup('env', 'ARM_SUBSCRIPTION_ID') }}"
    arc_tenant_id: "{{ lookup('env', 'ARM_TENANT_ID') }}"
    arc_region: "germanywestcentral"
  tasks:
    - name: Download Azure Arc agent install script
      get_url:
        url: "https://aka.ms/azcmagent"
        dest: /tmp/install_linux_azcmagent.sh
        mode: '0755'

    - name: Install Azure Arc Connected Machine agent
      command: /tmp/install_linux_azcmagent.sh
      args:
        creates: /usr/bin/azcmagent

    - name: Connect machine to Azure Arc
      command: >
        azcmagent connect
        --resource-group "{{ arc_resource_group }}"
        --tenant-id "{{ arc_tenant_id }}"
        --subscription-id "{{ arc_subscription_id }}"
        --location "{{ arc_region }}"
        --tags "project=clopr2,env=dev,owner=katar711"
      environment:
        HIMDS_AZCMAGENT_INSTALLATION_ACCESS_TOKEN: "{{ arc_access_token }}"

    - name: Verify Arc agent status
      command: azcmagent show
      register: arc_status
      changed_when: false

    - name: Display Arc agent status
      debug:
        var: arc_status.stdout_lines
```

**Note:** For interactive use (student lab), run `azcmagent connect` with `--use-device-code` flag to authenticate via browser instead of using a service principal token.

#### 2.2 Interactive onboarding (manual approach — recommended for lab)

```bash
# SSH into pg-primary
ssh pg-primary

# Download and install agent
wget -q https://aka.ms/azcmagent -O /tmp/install_linux_azcmagent.sh
sudo bash /tmp/install_linux_azcmagent.sh

# Connect to Azure using device code auth (opens browser flow)
sudo azcmagent connect \
  --resource-group "rg-clopr2-katar711-gwc" \
  --subscription-id "<your-subscription-id>" \
  --location "germanywestcentral" \
  --tags "project=clopr2,node=pg-primary,env=dev" \
  --use-device-code

# Verify
sudo azcmagent show

# Repeat for pg-standby and app-onprem
```

#### 2.3 Terraform — post-onboarding extensions (optional enhancement)

After Arc server resources appear in ARM, Terraform can manage extensions:

```hcl
# infra/terraform/modules/arc/main.tf (create this module)
resource "azurerm_arc_machine_extension" "log_analytics" {
  name               = "AzureMonitorLinuxAgent"
  location           = var.location
  arc_machine_id     = var.arc_machine_id  # from arc machine resource ID after onboard
  publisher          = "Microsoft.Azure.Monitor"
  type               = "AzureMonitorLinuxAgent"
  type_handler_version = "1.0"
}
```

---

### Phase 3 — Validation (estimated: 20 min)

#### 3.1 Confirm Arc server resources in Azure portal
- Navigate to: Azure Arc → Servers
- Verify pg-primary, pg-standby, app-onprem appear with status "Connected"
- Confirm resource group, tags, and OS version are correct

#### 3.2 Confirm existing services unaffected
```bash
# ON EACH ON-PREM VM immediately after Arc install
systemctl status keepalived --no-pager
systemctl status postgresql --no-pager

# On pg-primary specifically:
psql -U postgres -c "SELECT client_addr, state FROM pg_stat_replication;"
# Should still show 10.0.96.14 (standby) and 10.200.0.2 (Azure DR) streaming

# Check VIP still active on pg-primary
ip addr show | grep 10.0.96.10
```

#### 3.3 Validate Arc agent health
```bash
sudo azcmagent show
# Expect: Status: Connected
# Expect: Resource Name: pg-primary (or respective hostname)
# Expect: Resource Group: rg-clopr2-katar711-gwc
```

#### 3.4 Confirm Azure portal view
- Azure portal → Resource Group `rg-clopr2-katar711-gwc` → should show Arc server resources
- Defender for Cloud → Inventory → filter by "Non-Azure" → should show all 3 machines
- Log Analytics workspace `log-clopr2-dev-gwc` → if AMA extension installed → Heartbeat table should start receiving entries

---

### Phase 4 — Documentation Updates (estimated: 20 min)

- [ ] Update `docs/01-architecture/architecture-diagram.md` — add Arc management plane notation
- [ ] Update `docs/02-security/defender-for-cloud.md` — add note about Arc-extended coverage
- [ ] Update `docs/02-security/rbac-model.md` — add Arc server resource type to RBAC scope
- [ ] Update `docs/05-evidence/evidence-index.md` — add Arc user story row
- [ ] Copy `infra/ansible/playbooks/arc-onboard-servers.yml` to repo
- [ ] Capture all screenshots listed in Section 9

---

### Phase 5 — Demo/Presentation Usage (estimated: 10 min prep)

Demo talking points:
1. "Our on-prem PostgreSQL HA cluster is now visible from Azure alongside our Azure DR VM — single pane of glass"
2. "Azure Policy can audit compliance on our Proxmox VMs without an agent VM in every subnet"
3. "Defender for Cloud now reports security recommendations for our physical lab VMs — demonstrating AZ-500 hybrid security posture"
4. "The Arc management plane is purely additive — WireGuard, Keepalived, and PostgreSQL replication are untouched"

---

## 6. Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| `azcmagent connect` fails due to blocked outbound 443 | Low (lab VMs usually have unrestricted outbound) | Medium | Pre-check in Phase 0.1; open required endpoints if needed |
| Arc agent conflicts with existing systemd services | Very Low | Low | Arc installs as a separate daemon with no shared ports or PID namespaces |
| Arc agent consumes CPU/memory affecting PG performance | Very Low | Low | Agent is lightweight (~50 MB RAM); PG on Proxmox has its own vCPUs |
| Keepalived VIP changes after Arc install | Near Zero | High | Validate VIP immediately post-install (Phase 3.2); rollback by stopping agent |
| Replication lag spike during install | Near Zero | Medium | Install during low-traffic period; monitor `pg_stat_replication` lag column |
| Cost overrun from Defender for Servers auto-provisioning | Low | Medium | Do NOT enable Defender for Servers during onboarding; explicitly decline Plans 1 & 2 in Defender for Cloud settings |
| Git secret exposure from Arc service principal credentials | Medium (if not careful) | High | Use device code auth for interactive sessions; store SP credentials in Key Vault if automating |
| Evidence pack integrity — new resources confuse reviewers | Low | Low | Clearly label Arc resources as "additional sprint task" in all evidence captures |

### 6.1 Rollback plan

If you decide not to keep Arc after demo:

```bash
# On each Arc-enrolled VM:
sudo azcmagent disconnect --force

# This:
# 1. Removes the machine from Azure Arc (Azure resource is deleted)
# 2. Leaves azcmagent installed but disconnected
# Optionally uninstall the agent:
sudo apt remove azcmagent  # Debian/Ubuntu
# or
sudo yum remove azcmagent  # RHEL/CentOS

# In Azure:
# az resource delete (Arc machine resources auto-delete on disconnect)
```

Rollback is clean and complete — no residue in DNS, replication config, or network routing.

---

## 7. Cost Impact

### 7.1 Zero-cost tier (recommended for this sprint)

| Component | Cost |
|---|---|
| Arc-enabled servers (3 machines) — management plane | **FREE** |
| Azure Monitor Agent extension | **FREE** |
| Log Analytics data ingestion (first 5 GB/month) | **FREE** (existing workspace) |
| Azure Policy built-in guest configuration audits | **FREE** |
| Resource Graph queries | **FREE** |
| Azure portal visibility | **FREE** |
| **Total** | **$0.00/month** |

### 7.2 Optional paid add-ons (DO NOT enable for student budget)

| Component | Cost/month | Recommendation |
|---|---|---|
| Defender for Servers Plan 1 | ~$14.40/server = ~$43.20 for 3 servers | SKIP |
| Defender for Servers Plan 2 | ~$28.80/server = ~$86.40 for 3 servers | SKIP |
| Arc data services (PostgreSQL) | ~$0.50/vCore/hour | SKIP — duplicates existing HA |
| Log Analytics >5 GB ingestion | ~$2.76/GB | Monitor; should stay under free tier |

### 7.3 Cost spike protection

- In **Defender for Cloud → Environment settings**, ensure "Defender for Servers" is set to **OFF** for your subscription or resource group before onboarding Arc servers
- Arc's own auto-provisioning may try to enable Defender plans — explicitly disable during onboarding
- Check cost analysis in Azure portal 24 hours after onboarding to confirm zero new charges

---

## 8. ClickUp Task Proposal

### Suggested title:
`[ADDITIONAL] Azure Arc - Hybrid Management Layer for On-Prem VMs`

### Suggested description:
```
## Summary
Add Azure Arc as a hybrid management enhancement to the CLOPR2 project. 
This is an additional sprint task and does NOT reopen or modify any completed 
core infrastructure (PostgreSQL HA, WireGuard tunnel, Azure DR replica, AKS, or IaC).

## Goal
Onboard the 3 on-prem Proxmox VMs (pg-primary, pg-standby, app-onprem) as 
Azure Arc-enabled servers to achieve:
- Unified Azure portal visibility of on-prem nodes
- Extended Defender for Cloud and Azure Policy coverage to on-prem tier
- Demonstration of hybrid governance for AZ-500 assessment
- Evidence of enterprise-grade hybrid management capability

## Out of scope
- Arc-enabled Kubernetes (AKS is already native Azure)
- Arc data services / Azure Arc PostgreSQL (conflicts with existing HA)
- Defender for Servers paid plans (student budget constraint)
- Any changes to PostgreSQL replication, WireGuard, or Keepalived configuration

## Approach
1. Pre-check outbound connectivity from on-prem VMs (Phase 0)
2. Register Azure resource providers (Phase 1)
3. Install azcmagent and connect each VM (Phase 2 — Ansible or manual)
4. Validate Arc status and confirm no impact to existing services (Phase 3)
5. Update documentation and capture evidence (Phase 4)
6. Demo prepared with talking points (Phase 5)

## References
- docs/99-ai-appendix/azure-arc-assessment.md
- infra/ansible/playbooks/arc-onboard-servers.yml
```

### Suggested acceptance criteria:
```
AC1: pg-primary appears in Azure Arc → Servers with status "Connected"
AC2: pg-standby appears in Azure Arc → Servers with status "Connected"
AC3: app-onprem appears in Azure Arc → Servers with status "Connected"
AC4: Keepalived VIP (10.0.96.10) remains active on pg-primary after Arc install
AC5: PostgreSQL streaming replication to both replicas (10.0.96.14, 10.200.0.2) continues uninterrupted
AC6: azcmagent show returns "Status: Connected" on all 3 VMs
AC7: All 3 Arc server resources visible in resource group rg-clopr2-katar711-gwc
AC8: Zero unexpected cost increase attributable to Arc (Defender plans remain OFF)
AC9: Evidence screenshots captured and added to evidence index
AC10: Architecture diagram updated to reflect Arc management plane
```

### Suggested definition of done:
```
- [ ] All 3 VMs enrolled and showing Connected in Azure Arc portal
- [ ] PostgreSQL HA health verified post-enrollment (VIP, replication lag, pg_is_in_recovery)
- [ ] WireGuard tunnel connectivity verified post-enrollment
- [ ] azcmagent show output saved as evidence file
- [ ] Azure portal screenshots captured (Arc Servers blade, resource group view)
- [ ] Defender for Cloud inventory screenshot showing non-Azure machines
- [ ] evidence-index.md updated with new Arc user story row
- [ ] architecture-diagram.md updated
- [ ] docs/99-ai-appendix/azure-arc-assessment.md committed to repo
- [ ] Rollback procedure tested (optional) or documented
- [ ] Ansible playbook committed to infra/ansible/playbooks/
- [ ] ClickUp task closed with all ACs verified
```

### Suggested sprint note:
```
⚠️ ADDITIONAL TASK NOTE:
This task is added to the current sprint as an enhancement item. 
It was NOT part of the original sprint backlog and does NOT invalidate 
or reopen any previously completed tasks (US1–US11, PostgreSQL HA, AKS, 
WireGuard, IaC). The existing architecture is complete and working.
Azure Arc is a presentation-quality governance layer added at sprint close 
to demonstrate hybrid management capability for the final assessment.
All existing evidence remains valid.
```

### Suggested label / tags:
`azure-arc`, `hybrid-management`, `additional-sprint-task`, `governance`, `az-500`, `no-dr-impact`

### Priority: Medium (enhancement, not critical path)

### Estimated effort: 3–4 hours total

---

## 9. Evidence / Screenshots to Capture

### Azure portal screenshots

| Screenshot | When to capture | File name suggestion |
|---|---|---|
| Azure Arc → Servers blade showing all 3 machines Connected | After Phase 2 | `arc-servers-connected-<date>.png` |
| Individual machine overview (pg-primary) | After Phase 2 | `arc-pg-primary-overview-<date>.png` |
| Resource group view showing Arc resources alongside native resources | After Phase 2 | `arc-rg-resources-<date>.png` |
| Defender for Cloud → Inventory → Non-Azure filter | After Phase 2 | `arc-defender-inventory-<date>.png` |
| Arc machine properties / tags | After Phase 2 | `arc-machine-properties-<date>.png` |

### Terminal outputs to save

| Output | Command | File name suggestion |
|---|---|---|
| azcmagent show (pg-primary) | `sudo azcmagent show` | `arc-agentshow-pg-primary-<date>.txt` |
| azcmagent show (pg-standby) | `sudo azcmagent show` | `arc-agentshow-pg-standby-<date>.txt` |
| azcmagent show (app-onprem) | `sudo azcmagent show` | `arc-agentshow-app-onprem-<date>.txt` |
| pg_stat_replication post-Arc | `psql -U postgres -c "SELECT client_addr, state, write_lag FROM pg_stat_replication;"` | `pg-stat-replication-post-arc-<date>.txt` |
| Keepalived status post-Arc | `systemctl status keepalived --no-pager` | `keepalived-status-post-arc-<date>.txt` |
| WireGuard status post-Arc | `sudo wg show` | `wg-status-post-arc-<date>.txt` |
| Azure CLI Arc resource list | `az connectedmachine list -g rg-clopr2-katar711-gwc -o table` | `arc-machine-list-<date>.txt` |

---

## 10. Automation Approach Recommendation

### Verdict: **Hybrid — Ansible for install, manual connect, Terraform for extensions**

| Phase | Tool | Justification |
|---|---|---|
| Agent install (`azcmagent` binary) | Ansible playbook | Idempotent, loops over all 3 hosts, consistent with existing automation style |
| Initial `azcmagent connect` | Manual (device code auth) | Fastest for 1-time lab onboarding; SP creation adds complexity not worth the time at sprint close |
| Extension deployment (AMA etc.) | Terraform | Keeps Azure-side resource lifecycle in Terraform state; consistent with existing IaC patterns |
| Validation | Ansible + manual | Ansible for batch health checks; manual for Azure portal screenshot capture |

**Why not fully Terraform:** Terraform cannot push an agent to an on-prem VM (it can only manage Azure-side Arc resources after the machine is already connected). There is no `azurerm` resource that SSHes into a Proxmox VM to install the agent.

**Why not fully manual:** Agent install on 3 VMs is repetitive and error-prone manually; Ansible is already in use and reduces human error.

**Why not fully Ansible:** Ansible can install the agent and invoke `azcmagent connect` using environment variable-based SP credentials, but for a lab project at sprint close, the device code auth flow is faster, simpler, and avoids SP secret management overhead.

**Time estimate with hybrid approach:**
- Ansible playbook write + test: ~30 min
- 3 x interactive `azcmagent connect` via device code: ~15 min
- Validation + screenshots: ~20 min
- Total: ~65–90 min implementation

---

## 11. Final Recommendation

**Go ahead with Arc onboarding. The risk is near-zero, the cost is zero, and the presentation value is significant.**

The recommended scope — Arc-enabled servers for pg-primary, pg-standby, and app-onprem — achieves a compelling hybrid management story without touching any of the working DR infrastructure. You get:

- A genuine "single pane of glass" moment in your demo where a reviewer sees Proxmox VMs inside the Azure portal alongside the Azure DR VM
- Extended Defender for Cloud and Policy coverage that directly maps to AZ-500 assessment criteria
- A concrete example of cloud-portable hybrid governance
- Evidence artifacts that complement (not duplicate) existing evidence

**The correct framing for your teacher and ClickUp:**
> "We completed the full DR implementation as planned. As an additional sprint enhancement, we layered Azure Arc to demonstrate enterprise hybrid management governance — showing that the on-prem and Azure tiers can be managed from a single control plane without disrupting the working DR path."

This is the right narrative for a final packaging sprint.

---

## ⚠️ ClickUp Reminder

> **This analysis should be created as an ADDITIONAL task in the current sprint on ClickUp.**  
> It should carry a clear label such as `[ADDITIONAL]` or `[ENHANCEMENT]` in the task title.  
> It must **NOT** reopen, modify, or destabilize any already completed core infrastructure tasks (US1–US11, PostgreSQL HA, WireGuard, AKS, IaC).  
> The existing sprint closure work and evidence pack remain valid and complete.  
> Arc onboarding is additive only.

---

*Document generated: 2026-03-12 | Review before execution | AI-assisted planning — validate all commands in your environment*
