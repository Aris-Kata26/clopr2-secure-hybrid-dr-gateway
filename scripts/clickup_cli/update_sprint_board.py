"""
update_sprint_board.py
======================
Sprint 4 cleanup + Sprint 5 portability task.
Run from: scripts/clickup_cli/
Usage:   python update_sprint_board.py
"""

import json
import os
import sys
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

TOKEN   = os.environ["CLICKUP_API_TOKEN"]
BASE    = "https://api.clickup.com/api/v2"
S5_LIST = "901521353818"

HEADERS = {
    "Authorization": TOKEN,
    "Content-Type": "application/json",
}


def get(path, **kwargs):
    r = requests.get(f"{BASE}/{path}", headers=HEADERS, timeout=30, **kwargs)
    r.raise_for_status()
    return r.json()


def post(path, body):
    r = requests.post(f"{BASE}/{path}", headers=HEADERS, json=body, timeout=30)
    if not r.ok:
        print(f"  ERROR {r.status_code}: {r.text[:300]}")
        return None
    return r.json()


def put(path, body):
    r = requests.put(f"{BASE}/{path}", headers=HEADERS, json=body, timeout=30)
    if not r.ok:
        print(f"  ERROR {r.status_code}: {r.text[:300]}")
        return None
    return r.json()


def add_comment(task_id, text):
    result = post(f"task/{task_id}/comment", {
        "comment_text": text,
        "notify_all": False,
    })
    if result:
        print(f"  Comment added to {task_id}")
    return result


def close_task(task_id):
    result = put(f"task/{task_id}", {"status": "closed"})
    if result:
        print(f"  Status -> closed: {task_id}")
    return result


def set_status(task_id, status):
    result = put(f"task/{task_id}", {"status": status})
    if result:
        print(f"  Status -> {status}: {task_id}")
    return result


def create_task(list_id, name, description, status, tags=None):
    body = {
        "name": name,
        "description": description,
        "status": status,
        "tags": tags or [],
    }
    result = post(f"list/{list_id}/task", body)
    if result:
        print(f"  Task created: {result['id']} — {name}")
    return result


# ─────────────────────────────────────────────────────────────────────────────
# S4-09 | End-to-End flow validation (demo scenario)
# Task ID: 86c8u3pwy | Current: Open → Close
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== S4-09 | End-to-End flow validation ===")

S4_09_COMMENT = """COMPLETED — 2026-03-19

End-to-end DR scenario fully validated across two separate drill sequences:

ON-PREM HA FAILOVER / FALLBACK (S4-03, 2026-03-14):
  - Failover RTO: <1 second (VRRP) / <5 seconds (app-confirmed)
  - Fallback elapsed: ~24 seconds (replication resumed automatically)
  - Evidence: 29 files in docs/05-evidence/dr-validation/
  - Commit: 12a6374

FULL-SITE FAILOVER / FAILBACK (S4-09 completion):
  - Full-site failover PASS: on-prem DB stopped, Azure DR VM promoted, app running on Azure
  - Full-site fallback PASS: pg_basebackup rebuild, replication resumed, VIP returned to primary
  - Evidence: docs/05-evidence/dr-validation/ + docs/05-evidence/full-site-dr-validation/
  - pg-standby rebuild completed 2026-03-16 after TL mismatch resolved

VALIDATED DR PATH (final runtime):
  WireGuard tunnel (pg-primary → Azure DR VM) + Keepalived VIP (on-prem HA) + pgBackRest backup to Azure Blob

NOTE: Traffic Manager was evaluated but de-scoped from the final validated DR path.
The accepted runtime uses WireGuard + Keepalived VIP for failover — no Traffic Manager dependency.
Traffic Manager de-scoping documented in S4-04.

Runbook: docs/03-operations/dr-validation-runbook.md v1.2
Evidence checklist: docs/05-evidence/dr-validation-evidence-checklist.md"""

add_comment("86c8u3pwy", S4_09_COMMENT)
close_task("86c8u3pwy")


# ─────────────────────────────────────────────────────────────────────────────
# S4-02 | Alerting: trigger alert during outage
# Task ID: 86c8b2b9y | Current: Open → Close
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== S4-02 | Alerting: trigger alert during outage ===")

S4_02_COMMENT = """COMPLETED — 2026-03-19

Alerting fully implemented and validated:

ALERT RULES DEPLOYED (5 rules across dev + dr-fce environments):
  1. cpu-high — CPU utilisation > 85% for 5 min
  2. mem-high — Available memory < 15% for 5 min
  3. disk-high — Disk usage > 80% for 10 min
  4. pg-connections-high — PostgreSQL connections > 80 threshold
  5. wg-tunnel-silent — WireGuard handshake age > 300 seconds

TUNING COMPLETED:
  - Initial deployment had noisy / mis-scoped alert conditions
  - Tuned thresholds, query windows, and evaluation frequencies
  - All 5 rules set to auto_mitigation_enabled=true
  - Alert noise audit documented in docs/05-evidence/alert-tuning/

NOTIFICATIONS RECEIVED:
  - Real Azure Monitor email notifications confirmed during outage simulation
  - Outage-triggered alert visibility objective achieved
  - Evidence: docs/05-evidence/alerting/ + docs/05-evidence/alert-tuning/

KQL QUERIES VALIDATED:
  - VRRP keepalived query confirmed against live S4-03 DR test data
  - 2 priority drop / 2 restore cycles recorded
  - docs/05-evidence/alerting/07-kql-keepalived-validation.json

Architecture: docs/03-operations/alerting-architecture.md"""

add_comment("86c8b2b9y", S4_02_COMMENT)
close_task("86c8b2b9y")


# ─────────────────────────────────────────────────────────────────────────────
# S4-01 | Monitoring: onboard on-prem signals to Log Analytics
# Task ID: 86c8b2bb6 | Current: Open → Close (scoped)
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== S4-01 | Monitoring: onboard on-prem signals to Log Analytics ===")

S4_01_COMMENT = """CLOSED (scoped) — 2026-03-19

Monitoring architecture fully deployed. Closing with documented constraint.

WHAT WAS ACHIEVED:
  - Log Analytics workspace deployed in dr-fce and dev environments
  - Azure Monitor Agent (AMA) + DCR deployed on Azure DR VM (vm-pg-dr-fce)
  - Full telemetry: syslog, heartbeat, performance counters on Azure DR VM
  - Azure Arc agent installed and Connected on all 3 on-prem VMs:
      pg-primary (10.0.96.11)   — Connected
      pg-standby (10.0.96.14)   — Connected
      app-onprem (10.0.96.13)   — Connected
  - 5 alert rules deployed and tuned (see S4-02)
  - KQL dashboards + workbooks validated against live data

DOCUMENTED CONSTRAINT (not a DR acceptance gate):
  - Arc Extension convergence (HCRP409) blocked AMA extension propagation
    to pg-standby and app-onprem after the Arc agent connected
  - pg-standby and app-onprem Arc agents show Connected but extension
    status did not reach Succeeded on these nodes
  - Root cause: HCRP409 is a known transient Arc extension provisioning issue
  - pg-primary extension: Succeeded + telemetry flowing normally
  - Decision: This constraint was explicitly de-scoped from DR acceptance.
    The monitoring objective (outage visibility, alerting, KQL evidence) was
    achieved through the final observability layer.

FINAL MONITORING STORY:
  Azure DR VM → AMA → DCR → Log Analytics → 5 Alert Rules → Email notification
  On-prem → Arc agent (Connected) → Log Analytics (pg-primary full parity;
    pg-standby + app-onprem extension convergence constrained but agents connected)

Evidence: docs/03-operations/monitoring-architecture.md
          docs/05-evidence/monitoring/
          docs/05-evidence/alert-tuning/"""

add_comment("86c8b2bb6", S4_01_COMMENT)
close_task("86c8b2bb6")


# ─────────────────────────────────────────────────────────────────────────────
# S4-04 | Traffic routing + health checks (Traffic Manager)
# Task ID: 86c8b2b93 | Current: planning → keep planning, add de-scope comment
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== S4-04 | Traffic routing + health checks (Traffic Manager) ===")

S4_04_COMMENT = """DE-SCOPED — not part of the final validated DR path (2026-03-19)

Traffic Manager was evaluated as a candidate for DNS-based failover routing but
was explicitly de-scoped from the accepted runtime architecture.

REASON FOR DE-SCOPING:
  The validated DR failover mechanism is:
    - On-prem HA: Keepalived VRRP VIP (10.0.96.10) between pg-primary and pg-standby
    - Full-site DR: WireGuard tunnel (pg-primary ↔ Azure DR VM) + pg_promote()
  These mechanisms are direct, testable, and already validated in S4-03 and S4-09.
  Traffic Manager would add DNS TTL latency and a cloud-only dependency to
  a path that works cleanly without it.

FINAL RUNTIME ARCHITECTURE (no Traffic Manager):
  WireGuard tunnel: pg-primary (10.200.0.1) ↔ vm-pg-dr-fce (10.200.0.2)
  Keepalived VIP:   10.0.96.10 floats between pg-primary (MASTER) and pg-standby (BACKUP)
  Failover trigger: systemctl stop keepalived on pg-primary (VRRP election <1s)
  Full-site:        pg_promote() on Azure DR VM after WAL drain confirmation

TERRAFORM NOTE:
  VPN gateway and Traffic Manager scaffolding remains in envs/dr-fce/main.tf
  as commented/conditional code. It was not applied to the validated environment.

This task is intentionally left in planning/de-scoped state.
Do not close as Completed — Traffic Manager was not implemented or validated."""

add_comment("86c8b2b93", S4_04_COMMENT)
# Keep status as "planning" — it is de-scoped, not completed
print("  Status unchanged (planning — de-scoped, not completed)")


# ─────────────────────────────────────────────────────────────────────────────
# Sprint 5 — Create portability task (no existing task found)
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== Sprint 5 | Create portability task ===")

S5_PORTABILITY_DESC = """[ADDITIONAL] Multi-cloud portability proof (AWS/GCP)
Sprint: S5 | Owner: KATAR711 | Team: BCLC24

IMPORTANT: This is a portability demonstration, not production multi-cloud DR.
The validated Azure DR platform (envs/dr-fce) remains completely unchanged.
All portability work is additive — zero modifications to live Azure resources.

SCOPE:
1. Shared portability layer (interface contracts)
   - infra/terraform/shared/compute-db/
   - infra/terraform/shared/compute-app/
   - infra/terraform/shared/secrets-interface/
   - infra/terraform/shared/monitoring/
   - infra/terraform/shared/core-network/

2. Provider mapping documentation
   - Azure Key Vault → AWS Secrets Manager → GCP Secret Manager
   - Azure managed identity → EC2 IAM profile → GCP service account
   - Azure VM → EC2 → Compute Engine
   - Azure Monitor/Log Analytics → CloudWatch → Cloud Logging
   - pgBackRest: repo1-type=azure → s3 → gcs (config-only change)
   - docs/06-portability/01-provider-mapping.md

3. AWS isolated proof deployment
   - infra/terraform/envs/aws-proof/
   - EC2 t3.micro, Ubuntu 22.04, us-east-1
   - VPC 10.21.0.0/16 (isolated — no CIDR overlap with Azure or on-prem)
   - WireGuard + postgresql-client-16 installed via user_data
   - terraform apply COMPLETE — instance running

4. GCP isolated proof deployment
   - infra/terraform/envs/gcp-proof/
   - Compute Engine e2-micro, Ubuntu 22.04, europe-west3
   - VPC 10.22.0.0/16 (isolated)
   - scripts/portability/gcp-proof-deploy.sh — deploy script for GCP Cloud Shell
   - STATUS: Terraform files complete, pending Cloud Shell execution

EVIDENCE:
  docs/05-evidence/portability/aws-proof-deploy.txt  — AWS deployment record
  docs/05-evidence/portability/gcp-proof-pending.txt — GCP pending record
  docs/06-portability/00-portability-overview.md
  docs/06-portability/02-portability-audit.md (34-component classification)

COMMITS:
  d8ff447 — portability layer + provider mapping
  0bc05e0 — AWS + GCP proof envs

AZURE IMPACT: ZERO. All envs/, modules/ unchanged."""

portability_task = create_task(
    list_id=S5_LIST,
    name="[ADDITIONAL] S5 | Multi-cloud portability proof (AWS/GCP)",
    description=S5_PORTABILITY_DESC,
    status="Open",
    tags=["portability", "aws", "gcp", "s5"],
)

if portability_task:
    S5_PORTABILITY_ID = portability_task["id"]

    # Add initial progress comment
    S5_COMMENT = """PARTIAL PASS — 2026-03-19

COMPLETED:
  [x] Portability audit — 34 components classified across cloud-neutral / Azure-specific / tightly-coupled
  [x] Shared interface contracts — 5 modules (compute-db, compute-app, secrets-interface, monitoring, core-network)
  [x] Provider mapping — Azure ↔ AWS ↔ GCP full table (docs/06-portability/01-provider-mapping.md)
  [x] Provider scaffolds — AWS and GCP compute-db + secrets stubs committed
  [x] AWS proof deployment — LIVE (i-03819fe1f280bece1, 44.215.122.180, running)
      EC2 t3.micro | Ubuntu 22.04 | wireguard + postgresql-client-16 installed
      terraform apply COMPLETE | 8 resources created
  [x] GCP proof Terraform — complete (envs/gcp-proof/, scripts/portability/gcp-proof-deploy.sh)

PENDING:
  [ ] GCP proof execution — files ready, awaiting Cloud Shell execution
      Deploy command: bash scripts/portability/gcp-proof-deploy.sh
      Resources: Compute Engine e2-micro, europe-west3, VPC 10.22.0.0/16

AZURE PLATFORM: UNTOUCHED
  Zero modifications to envs/dr-fce, envs/dev, envs/swe-aks, modules/

OVERALL STATUS: PARTIAL PASS (AWS done, GCP pending)
Task will be closed when GCP proof is executed and evidence committed."""

    add_comment(S5_PORTABILITY_ID, S5_COMMENT)
    print(f"  Portability task ID: {S5_PORTABILITY_ID}")


print("\n=== All ClickUp updates complete ===\n")
