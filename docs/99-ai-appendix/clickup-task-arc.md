# ClickUp Task: Azure Arc Hybrid Management Integration

> **Reminder:** Create this as an **additional task** in the current sprint.
> Label it `[ADDITIONAL]` to distinguish it from the completed core sprint tasks.
> Do NOT reopen US1–US11 or any completed infrastructure tasks.

---

## Task metadata

| Field | Value |
|---|---|
| **Title** | `[ADDITIONAL] Azure Arc Hybrid Management Integration` |
| **Sprint** | Current sprint (same sprint as US1–US11) |
| **Priority** | Medium |
| **Estimated effort** | 3–4 hours |
| **Assignee** | KATAR711 |
| **Labels / tags** | `azure-arc`, `hybrid-management`, `additional-sprint-task`, `governance`, `az-500`, `no-dr-impact` |
| **Type** | Enhancement |

---

## Description

```
## Summary
Add Azure Arc as a hybrid management layer for the CLOPR2 project.

This is an ADDITIONAL sprint task added at sprint close.
It does NOT modify, reopen, or destabilize any completed core infrastructure
(PostgreSQL HA, WireGuard tunnel, Azure DR replica, AKS, or IaC).

## Goal
Onboard the 3 on-prem Proxmox VMs (pg-primary, pg-standby, app-onprem) as
Azure Arc-enabled servers to achieve:
  - Unified Azure portal visibility of on-prem nodes alongside Azure DR VM
  - Extended Defender for Cloud + Azure Policy coverage to on-prem tier
  - AZ-500 hybrid governance demonstration for assessment
  - Evidence of enterprise-grade hybrid management capability

## Scope
IN SCOPE:
  - pg-primary       → Arc-enabled server
  - pg-standby       → Arc-enabled server
  - app-onprem       → Arc-enabled server

OUT OF SCOPE:
  - Arc-enabled Kubernetes (AKS is already native Azure)
  - Arc data services / Arc PostgreSQL (conflicts with existing HA)
  - Defender for Servers paid plans (student budget)
  - Any changes to PostgreSQL replication, WireGuard, or Keepalived

## Approach
Phase 1 — Pre-checks: Verify outbound HTTPS 443 + capture DR baseline
Phase 2 — Azure prereqs: Register HybridCompute / GuestConfiguration providers
Phase 3 — Ansible install: Run arc-onboard-servers.yml --tags install
Phase 4 — Connect: azcmagent connect --use-device-code on each VM
Phase 5 — Validate: Ansible postcheck + portal screenshots
Phase 6 — Document: Update evidence index + architecture diagram
Phase 7 — Commit: feat: add Azure Arc hybrid management layer

## Cost
$0.00/month — Arc core management plane, AMA extension, and built-in Policy audits are all free.
Defender for Servers plans explicitly NOT enabled.

## References
- docs/99-ai-appendix/azure-arc-assessment.md (full planning doc)
- docs/03-operations/azure-arc-integration.md (runbook)
- infra/ansible/playbooks/arc-onboard-servers.yml (automation)
```

---

## Acceptance Criteria

```
AC1  pg-primary shows Status: Connected in Azure Arc → Servers
AC2  pg-standby shows Status: Connected in Azure Arc → Servers
AC3  app-onprem shows Status: Connected in Azure Arc → Servers
AC4  azcmagent show returns "Status: Connected" on each VM
AC5  Keepalived VIP 10.0.96.10 remains active on pg-primary post-install
AC6  pg_stat_replication shows 2 replicas (10.0.96.14 + 10.200.0.2) streaming post-install
AC7  pg_is_in_recovery()=t on pg-standby post-install
AC8  sudo wg show confirms WireGuard tunnel to 10.200.0.2 still active post-install
AC9  Zero unexpected cost increase (Defender for Servers plans remain OFF)
AC10 Evidence screenshots captured and added to evidence index
AC11 Architecture diagram updated to include Arc layer
AC12 docs/03-operations/azure-arc-integration.md committed to repo
```

---

## Definition of Done

```
[ ] All 3 VMs enrolled and showing Connected in Azure Arc portal blade
[ ] azcmagent show saved as evidence file for each VM
[ ] Pre-Arc baseline outputs saved to docs/05-evidence/outputs/pre-arc/
[ ] Post-Arc validation outputs saved to docs/05-evidence/outputs/post-arc/
[ ] Azure portal screenshots captured and saved to docs/05-evidence/screenshots/
[ ] Defender for Cloud inventory screenshot showing non-Azure machines
[ ] az connectedmachine list output saved as evidence
[ ] evidence-index.md updated with US-ARC row
[ ] architecture-diagram.md updated with Arc management layer section
[ ] docs/03-operations/azure-arc-integration.md committed to repo
[ ] infra/ansible/playbooks/arc-onboard-servers.yml committed to repo
[ ] Commit pushed: "feat: add Azure Arc hybrid management layer for on-prem VMs"
[ ] ClickUp task closed with all ACs checked
```

---

## Sprint note

> ⚠️ **ADDITIONAL TASK NOTE (to be added in ClickUp task description or comment):**
>
> This task is added to the current sprint as a post-implementation enhancement.
> It was NOT part of the original sprint backlog and does NOT invalidate or
> reopen any previously completed tasks (US1–US11, PostgreSQL HA, AKS,
> WireGuard, IaC, or the evidence pack).
>
> The existing architecture is complete and working. Azure Arc is a
> presentation-quality governance layer added at sprint close to demonstrate
> hybrid management capability for the final assessment.
>
> All existing evidence remains valid and unchanged.

---

## Demo talking points (for presentation)

1. "Our on-prem Proxmox VMs now appear in Azure portal alongside the Azure DR VM — single pane of glass."
2. "Azure Policy guest configuration runs compliance audits on our lab VMs without a cloud migration."
3. "Defender for Cloud now covers the full hybrid stack — on-prem tier included — demonstrating AZ-500 end-to-end security posture."
4. "Arc is purely additive: WireGuard, Keepalived, and PostgreSQL replication are completely untouched."
5. "Total cost of this enhancement: $0.00/month."
