# DR Orchestration & Control-Plane Flow — CLOPR2 Secure Hybrid DR Gateway

**Date:** 2026-03-19 | **Author:** KATAR711 | **Team:** BCLC24

---

## Control-Plane Overview

```
Operator
   │
   ▼
[dr-preflight.sh] ──── GATE: 10/10 checks must pass ────► STOP (do not proceed)
   │ PASS
   ▼
[onprem-failover.sh]           [fullsite-failover.sh]
        │                               │
        ▼                               ▼
  [evidence-export.sh]          [evidence-export.sh]
        │                               │
        ▼                               ▼
  [onprem-fallback.sh]         (rollback path: manual restore — separate runbook)
        │
        ▼
  [evidence-export.sh]
```

All scripts: bash, operator-invoked, no autonomous trigger, no cloud-based orchestrator.

---

## Stage 1 — Preflight Gate (`dr-preflight.sh`)

**Purpose:** Validate system state before any destructive action is taken.

| Check | Tool | Pass Condition |
|---|---|---|
| SSH reachability — all 4 hosts | ssh -o BatchMode | Exit 0 on all |
| PostgreSQL service — pg-primary | systemctl is-active | active |
| PostgreSQL service — pg-standby | systemctl is-active | active |
| Keepalived — pg-primary | systemctl is-active | active |
| WireGuard — pg-primary | systemctl is-active | active |
| Replication streaming — pg-primary | pg_stat_replication | ≥1 row, state=streaming |
| pg-standby in recovery | pg_is_in_recovery() | true |
| VIP on pg-primary | ip addr show eth0 | 10.0.96.10 present |
| WireGuard tunnel — handshake age | wg show | latest-handshake < 300s |
| Application health | curl /health | HTTP 200, pg_is_in_recovery=false |

**Gate rule:** Any single FAIL aborts the run. Operator must resolve before proceeding.

**Modes:** `dr-preflight.sh onprem-ha` or `dr-preflight.sh fullsite`

---

## Stage 2A — On-Prem HA Failover (`onprem-failover.sh`)

**Scope:** VIP moves from pg-primary to pg-standby. No data loss. Fully reversible.

```
1. [Check]       Assert VIP is on pg-primary (abort if already on standby)
2. [Action]      Stop PostgreSQL on pg-primary
                 → keepalived weight drops 100→80; VIP does NOT move yet (nopreempt)
3. [Destructive] Stop Keepalived on pg-primary  ◄── VRRP advertisements halt
                 → pg-standby wins election → VIP moves in <1 second
4. [Poll]        Wait for VIP on pg-standby eth0 (max 15s, 1s intervals)
5. [Validate]    App /health → pg_is_in_recovery = true (confirms app rerouted)
6. [Capture]     Evidence: VIP location, keepalived state, pg recovery state, app health
```

**RTO achieved:** VRRP < 1s, app-confirmed < 5s

**Rollback:** `onprem-fallback.sh` (separate script, same operator invocation)

---

## Stage 2B — On-Prem HA Fallback (`onprem-fallback.sh`)

**Scope:** Return VIP to pg-primary. Validate replication resumes.

```
1. [Check]       Assert pg-primary services are stopped (fallover precondition)
2. [Action]      Start PostgreSQL on pg-primary
3. [Action]      Start Keepalived on pg-primary (priority 100 > standby 90)
                 → pg-primary advertises, standby yields, VIP returns
4. [Poll]        Wait for VIP on pg-primary (max 20s)
5. [Poll]        Wait for replication resume (max 60s — advisory warning if timeout)
6. [Validate]    App /health → pg_is_in_recovery = false
7. [Capture]     Evidence: replication state, VIP location, app health
```

**Elapsed (measured):** ~24s end-to-end

---

## Stage 3 — Full-Site Failover (`fullsite-failover.sh`)

**Scope:** Promote Azure DR VM to primary. On-prem goes dark. One-way until restore.

```
FS-1  [Action]       Stop app container on app-onprem
FS-2  [Capture]      Record final LSN on pg-primary (primary_lsn, replay_lsn)
FS-3  [DESTRUCTIVE]  Stop PostgreSQL + Keepalived on pg-primary  ◄── ON-PREM DB DOWN
                     WireGuard (wg-quick@wg0) intentionally left running
FS-4  [Poll]         Azure DR VM: pg_last_wal_replay_lsn unchanged × 3 consecutive
                     readings (max 120s) → confirm WAL fully replayed
                     → compute RPO bytes = primary_lsn − replay_lsn
FS-5  [DESTRUCTIVE]  Promote Azure DR VM via pg_promote()
                     → removes standby.signal → pg_is_in_recovery transitions false
FS-6  [Validate]     Write test: CREATE TABLE / INSERT / DROP on promoted DR VM
FS-7  [Action]       Start app container on Azure DR VM
FS-8  [Poll]         App /health on Azure host (max 60s)
FS-9  [Validate]     SSH port-forward: WSL → Azure VM → localhost:8000/health
FS-10 [Capture]      RTO/RPO summary + full evidence snapshot to /tmp
```

**Destructive confirmation gates:** FS-3 and FS-5 are the only points of no-return.
FS-3 can be reversed (restart services). FS-5 (promotion) requires full pg_basebackup to rebuild on-prem replica.

---

## Evidence Capture (`evidence-export.sh`)

**Triggered:** After every failover/fallback run.

| Evidence File | Source | Content |
|---|---|---|
| `fs-ha-preflight-*.txt` | WSL local | 10-point preflight result |
| `fs-ha-vip-*.txt` | WSL local (via SSH) | VIP location at each stage |
| `fs-ha-replication-*.txt` | WSL local (via SSH) | pg_stat_replication output |
| `fs-ha-keepalived-*.txt` | WSL local (via SSH) | keepalived status |
| `fs-ha-app-health-*.txt` | WSL local (via SSH relay) | /health JSON at each stage |
| `fsdr-rto-rpo-*.txt` | WSL local | RTO/RPO summary with timestamps |
| `fsdr-write-test-*.txt` | WSL local | CREATE/INSERT/DROP result on promoted VM |

**Collection mechanism:** All evidence written locally via `tee /tmp/...` during script execution. `evidence-export.sh` copies files to `docs/05-evidence/` and commits. No remote write access required.

---

## Dry-Run Capability

`dr-preflight.sh` is safe to run at any time — read-only, no state changes.

All destructive scripts (`onprem-failover.sh`, `fullsite-failover.sh`) include preflight assertions at the top that abort on unexpected state. Running preflight before every operation is the documented dry-run equivalent.

---

## What Is NOT Automated

| Function | Why Manual |
|---|---|
| DR decision (invoke failover) | Human gate — requires situational assessment |
| Full-site rollback (after FS-5) | Requires pg_basebackup rebuild — documented in runbook, not scripted |
| Alert response | Alerts notify; they do not trigger DR scripts |
| Secret rotation | Manual — Key Vault holds; rotation requires platform admin |

---

*Speaker notes: The control plane is intentionally operator-driven. Every destructive step is preceded by a validation check that aborts on unexpected state. The preflight script is the single mandatory gate — nothing runs unless all 10 checks pass. Evidence is captured automatically so the operator can focus on the procedure, not the logging. The design trades autonomy for auditability and predictability, which is appropriate for a platform managed by a single operator team.*
