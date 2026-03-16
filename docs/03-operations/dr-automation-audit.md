# DR Automation Audit — CLOPR2 Secure Hybrid DR Gateway
<!-- CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24 -->

## Document status

| Field | Value |
|---|---|
| Version | 1.0 |
| Created | 2026-03-16 |
| Status | DRAFT — planning only, no scripts executed |
| Sprint | S5-01 |
| Scope | All 4 DR workflows, audit-first, no destructive changes |
| Runbooks audited | dr-validation-runbook.md v1.2, full-site-failover-runbook.md v1.0, full-site-failback-runbook.md v1.0 |

---

## 1. Executive summary

All four DR workflows are currently **entirely manual** — human-driven command sequences
across multiple terminal windows, SSH hops, and timing waits. The runbooks are solid and
the evidence proves they work. The goal of this audit is to identify where automation
can reduce RTO, reduce human error, and simplify repeat drills.

**Key finding:** The full-site failover RTO of 48m 42s was not caused by a slow process —
it was caused by a single preventable failure (SSH ControlMaster socket going stale in WSL).
The underlying operation is ~3-5 minutes. **A 5-second pre-check script eliminates that
risk entirely.**

**RTO targets vs. reachable:**

| Workflow | Achieved RTO | Clean RTO | Target | Reachable |
|---|---|---|---|---|
| On-prem failover | <1s VRRP / <5s app | <5s | <5s | Already achieved |
| On-prem fallback | 24s | 24s | <30s | Already achieved |
| Full-site failover | 48m 42s (ssh failure) | ~3-5 min | <5 min | YES |
| Full-site failback | 20m 53s | ~8-12 min | <10 min | Partial (pg_basebackup is the floor) |

---

## 2. Workflow-by-workflow manual step analysis

### 2.1 On-Prem HA Failover

**Source:** `dr-validation-runbook.md` sections 3 and 4

| Step | Manual action | Risk | Automation potential |
|---|---|---|---|
| Pre-checks | 4+ terminal commands | Skipped under pressure | Script |
| Record start timestamp | Manual echo + tee | Forgotten | Script |
| Stop postgresql on pg-primary | `systemctl stop postgresql` | Wrong host/service | Script with host verification |
| Stop keepalived on pg-primary | `systemctl stop keepalived` | Skipped (easy to forget) | Script |
| Verify VIP moved to pg-standby | `ip addr show` on pg-standby | Not checked | Script with assertion |
| Confirm app via /health | `curl` from WSL | Not checked | Script with assertion |
| Capture 10+ evidence files | Manual tee + scp | Missed files | Script |
| SSH to pg-standby | ProxyCommand via pg-primary relay | Stale socket | Pre-check script |

**Total manual commands:** ~25 across 3+ terminal windows
**Critical finding documented in runbook:** Must stop keepalived, NOT just postgresql.
Stopping postgresql alone drops priority 100->80 but with `nopreempt`, pg-standby will
NOT preempt a still-advertising MASTER. The runbook has this correct; the risk is
an operator reverting to intuition and only stopping postgresql.

**Automation risk level: LOW** — all operations are local SSH commands, no infrastructure
state is ambiguous. Safe to script.

---

### 2.2 On-Prem HA Fallback

**Source:** `dr-validation-runbook.md` section 5

| Step | Manual action | Risk | Automation potential |
|---|---|---|---|
| Start postgresql on pg-primary | `systemctl start postgresql` | Wrong host | Script |
| Start keepalived on pg-primary | `systemctl start keepalived` | Skipped (causes VIP not to return) | Script |
| Wait for replication to resume | Visual poll of pg_stat_replication | Times out waiting | Script with timeout |
| Verify VIP returned | `ip addr show` on pg-primary | Not verified | Script with assertion |
| Confirm app via /health | `curl` from WSL | Not checked | Script |
| Capture evidence | Manual tee + scp | Missed files | Script |

**Total manual commands:** ~15
**RTO achieved:** 24s. No significant gains possible here — the 24s is the actual
replication resume latency. Automation value is about reliability and evidence capture,
not RTO reduction.

---

### 2.3 Full-Site Failover to Azure

**Source:** `full-site-failover-runbook.md` v1.0

| Step | Manual action | Risk | Automation potential |
|---|---|---|---|
| SSH pre-check (not in runbook) | None — NOT currently a step | +45m RTO if socket stale | ADD as mandatory Step 0 |
| Prerequisite checks H-1..H-9 | 9 separate SSH commands | Any can be skipped | Script |
| Record start timestamp | Manual | Forgotten | Script |
| Open persistent SSH to DR VM | SSH via WireGuard | Stale socket kills later steps | Pre-check + session persistence |
| Stop app on app-onprem (FS-2) | SSH multi-hop to 10.0.96.13 | SSH relay fail | Script with retry |
| Capture LSN from pg-primary (FS-3) | psql command | Forgotten | Script |
| Stop postgresql + keepalived (FS-5) | Two systemctl commands | Wrong order | Script with sequence lock |
| Poll DR VM WAL replay (FS-6) | Manual polling loop | Operator moves too fast | Script with assertion loop |
| Promote DR VM (FS-7) | psql pg_promote() | Done before replay complete | Script with lag gate |
| Start app on DR VM (FS-8) | SSH + docker run | Env var omitted | Script |
| Validate health (FS-9) | curl | Not validated | Script with assertion |
| Capture 14 evidence files | Manual tee scattered across steps | Missed files | Script |

**The single biggest RTO risk:** SSH ControlMaster socket stale (~45 min added in S4-09).
The fix is a mandatory 5-second pre-check. This is the highest-priority automation item
in the entire audit.

**Pre-test-day setup** (Docker install, app source, image build on DR VM) is NOT in the
RTO window and is already a one-time operation. No automation needed there.

---

### 2.4 Full-Site Failback to On-Prem

**Source:** `full-site-failback-runbook.md` v1.0

| Step | Manual action | Risk | Automation potential |
|---|---|---|---|
| Pre-checks H-1..H-7 | 7 SSH commands | Skipped | Script |
| Stop app on DR VM (FB-1) | SSH + docker stop/rm | Container not stopped = dirty writes during basebackup | Script with verification |
| Set DR VM read-only (FB-2) | ALTER SYSTEM + reload | Skipped = possible write loss | Script with assertion |
| pg_basebackup on pg-primary (FB-3) | SSH + long command | Wrong flags, wrong source | Script |
| Start pg-primary as standby (FB-4) | systemctl start | Started before basebackup completes | Script with dependency check |
| Poll catchup lag (FB-6) | Manual for-loop | Operator skips wait | Script with lag gate |
| Promote pg-primary (FB-7) | SELECT pg_promote() | Done before lag=0 | Script with lag assertion |
| Rebuild DR VM as standby (FB-8) | pg_basebackup on vm-pg-dr-fce | Most complex step | Script |
| Start keepalived on pg-primary (FB-10) | systemctl start | Forgotten = VIP stays on pg-standby | Script |
| Start app on app-onprem (FB-11) | SSH multi-hop 3-hop | SSH relay fail | Script with retry |
| Validate health (FB-12) | curl | Not validated | Script with assertion |
| Capture 17 evidence files | Manual tee | Missed files | Script |

**RTO floor:** pg_basebackup runs twice (FB-3 and FB-8). At ~500 MB data volume each run
at LAN speeds (~100 MB/s over WireGuard), that is ~5-10 seconds per run — negligible.
At larger data volumes (e.g. 10 GB), each run is ~100s. The actual S4-09 RTO of 20m 53s
reflects manual coordination overhead between the two basebackup operations.

**Automation value here is highest of all 4 workflows** — scripting FB-1 through FB-13
as a single orchestrator with proper sequencing can bring failback RTO from ~20 min
to ~8-10 min (dominated by two pg_basebackup runs + replication catchup wait).

---

## 3. Root cause analysis — S4-09 RTO overrun

**Observed:** 48m 42s full-site failover RTO
**Expected:** ~3-5 min

**Root causes in order of contribution:**

1. **SSH ControlMaster socket stale — ~45 min** (primary cause)
   - WSL changed network context after a period of inactivity
   - All SSH commands silently hung waiting for the dead mux
   - Recovery: manually found and killed the stale socket, re-established sessions
   - Impact: this pause happened mid-execution, after pg-primary was already stopped
   - Fix: mandatory `rm -f ~/.ssh/ctl/pve && ssh pve 'echo ok'` at the very start

2. **DR VM SSH via WireGuard used via Azure run-command workaround — ~3 min**
   - The WSL -> PVE -> pg-primary -> DR VM SSH chain was disrupted
   - Used Azure portal run-command as a fallback to complete the failover
   - This is slower and requires portal access

3. **Manual evidence capture scattered across steps — ~2 min**
   - 14 separate tee commands across the runbook
   - Some required re-SSHing after the socket was restored

**The process itself works and is fast.** The human-in-the-loop coordination is the
only delay. All actual PostgreSQL operations completed in seconds.

---

## 4. Automation opportunities — prioritized

### Priority 1: CRITICAL — SSH ControlMaster pre-check
**Effort:** 15 min | **RTO impact:** eliminates 45 min risk | **Risk:** None

```
scripts/dr/ssh-precheck.sh
```

Mandatory first step before ANY DR operation. Clears the stale socket and tests
connectivity to all required hosts. If any host is unreachable, abort with clear error.

This single script is the highest-value change in this entire audit.

---

### Priority 2: HIGH — On-prem HA failover/fallback scripts
**Effort:** 1-2 hours | **RTO impact:** minimal (already fast), reduces human error | **Risk:** Low

```
scripts/dr/onprem-failover.sh
scripts/dr/onprem-fallback.sh
```

These are the simplest workflows to script. Mostly SSH commands with assertions.
The critical safety gate: assert `--confirm` flag required before stopping keepalived.

---

### Priority 3: HIGH — Full-site failover script
**Effort:** 2-3 hours | **RTO impact:** ~45 min -> <5 min (eliminates SSH risk) | **Risk:** Medium

```
scripts/dr/fullsite-failover.sh
```

Must include:
- SSH pre-check as Step 0 (mandatory, cannot be skipped)
- Prerequisite assertion loop (all H-1..H-9 pass or abort)
- Persistent DR VM session management
- WAL lag polling loop with timeout and threshold
- Promote only when lag < 1024 bytes (configurable)
- Evidence capture at each step

---

### Priority 4: MEDIUM — Full-site failback script
**Effort:** 3-4 hours | **RTO impact:** ~20 min -> ~8-10 min | **Risk:** Medium-High

```
scripts/dr/fullsite-failback.sh
```

This is the highest-complexity script. Contains the most irreversible operations
(rm -rf pg data directory x2). Must have explicit `--confirmed` gate with clear
warning text before FB-3 (rm + pg_basebackup on pg-primary) and FB-8 (rm + pg_basebackup
on DR VM).

---

### Priority 5: MEDIUM — Evidence export batch script
**Effort:** 1 hour | **RTO impact:** 0 (not in RTO window) | **Risk:** None

```
scripts/dr/evidence-export.sh
```

Collects all /tmp/fs* and /tmp/fsdb* files from all hosts, copies to
docs/05-evidence/<phase>/, prints diff summary. Run after any drill completion.

---

### Priority 6: LOW — Pre-flight check script
**Effort:** 1 hour | **RTO impact:** saves ~5-10 min prep time | **Risk:** None

```
scripts/dr/dr-preflight.sh <workflow>
```

Validates steady-state readiness before any drill begins. Checks replication lag,
WireGuard handshake age, VIP location, app health, PostgreSQL roles. Outputs
pass/fail per prerequisite.

---

## 5. Script design specifications

### 5.1 `scripts/dr/ssh-precheck.sh`

```
Purpose:    Clear stale SSH ControlMaster sockets and verify connectivity to all DR hosts
Inputs:     None (reads SSH config)
Outputs:    PASS/FAIL per host, non-zero exit on any failure
Safety:     Read-only, non-destructive (rm on socket files only)
Hosts:      pve (10.0.10.71), pg-primary (10.0.96.11), pg-standby (10.0.96.14),
            app-onprem (10.0.96.13), vm-pg-dr-fce (10.200.0.2)
```

Logic:
1. `rm -f ~/.ssh/ctl/pve ~/.ssh/ctl/pg-primary`
2. Test each host with `ssh <host> 'hostname && date'` with 10s timeout
3. For WireGuard hosts (DR VM): test via pg-primary relay after confirming pg-primary up
4. Print connectivity table, exit 1 if any host unreachable

---

### 5.2 `scripts/dr/onprem-failover.sh`

```
Purpose:    Execute on-prem HA failover with evidence capture
Inputs:     --confirm (required)
Outputs:    Evidence files in /tmp/fs-ha-*, exit 0 on PASS
Safety:     Stops postgresql and keepalived on pg-primary only
Reversible: Yes — onprem-fallback.sh restores
```

Logic:
1. ssh-precheck.sh (abort if any host unreachable)
2. Assert pg-primary keepalived=active (or abort)
3. Assert pg-standby keepalived=active (or abort)
4. `--confirm` gate: print warning, require explicit yes
5. Record FS_START timestamp
6. Stop postgresql on pg-primary
7. Stop keepalived on pg-primary
8. Poll VIP on pg-standby (up to 10s, assert 10.0.96.10 present)
9. Poll /health (up to 30s, assert pg_is_in_recovery=true)
10. Capture evidence: pg_stat_replication (both nodes), keepalived state, /health
11. Record FS_END timestamp
12. Print PASS with RTO

---

### 5.3 `scripts/dr/onprem-fallback.sh`

```
Purpose:    Execute on-prem HA fallback (restore pg-primary to MASTER)
Inputs:     --confirm (required)
Outputs:    Evidence files in /tmp/fs-ha-*, exit 0 on PASS
Safety:     Starts postgresql and keepalived on pg-primary only
Reversible: Yes — onprem-failover.sh re-triggers
```

Logic:
1. ssh-precheck.sh
2. Assert pg-primary postgresql=inactive, keepalived=inactive
3. Assert pg-standby has VIP (10.0.96.10 on eth0)
4. `--confirm` gate
5. Record FSB_START timestamp
6. Start postgresql on pg-primary
7. Start keepalived on pg-primary
8. Poll VIP returned to pg-primary (up to 15s)
9. Poll replication lag on pg-primary (up to 60s, target < 65536 bytes)
10. Poll /health (up to 30s, assert pg_is_in_recovery=false)
11. Capture evidence
12. Print PASS with elapsed time

---

### 5.4 `scripts/dr/fullsite-failover.sh`

```
Purpose:    Execute full-site failover from on-prem to Azure DR VM
Inputs:     --confirm (required), --wal-lag-threshold (default: 1024 bytes)
Outputs:    Evidence files in /tmp/fsdr-*, exit 0 on PASS
Safety:     Stops pg-primary PostgreSQL and Keepalived; promotes DR VM
Reversible: Via fullsite-failback.sh (requires pg_basebackup)
```

Logic:
1. **Step 0 — MANDATORY:** ssh-precheck.sh (abort if any host unreachable)
2. Assert DR VM app is running, pg_is_in_recovery=t
3. Assert pg-primary is primary (pg_is_in_recovery=f) and keepalived active
4. Check WireGuard handshake age < 300s
5. Record FS_START timestamp
6. Capture pre-failover LSN snapshot
7. **Open persistent DR VM SSH session** (validate before proceeding)
8. `--confirm` gate: print all prerequisites passed, confirm to proceed
9. Stop app on app-onprem (SSH multi-hop via pg-primary relay)
10. Record final LSN on pg-primary
11. Stop postgresql on pg-primary
12. Stop keepalived on pg-primary
13. Poll DR VM replay_lsn until caught up (lag < threshold, timeout 120s)
14. Promote DR VM: SELECT pg_promote()
15. Assert pg_is_in_recovery=f on DR VM
16. Start app on DR VM (docker run with env)
17. Poll /health on DR VM (up to 60s, assert pg_is_in_recovery=false)
18. Capture all evidence
19. Record FS_END timestamp, print RTO

---

### 5.5 `scripts/dr/fullsite-failback.sh`

```
Purpose:    Execute full-site failback from Azure DR VM to on-prem
Inputs:     --confirm (required), --confirm-destructive (required separately)
Outputs:    Evidence files in /tmp/fsdb-*, exit 0 on PASS
Safety:     Two confirmation gates; one before each pg_basebackup (rm -rf)
Reversible: No — pg-primary data directory is wiped in FB-3. DR VM data wiped in FB-8.
```

Logic:
1. ssh-precheck.sh
2. All H-1..H-7 checks (abort if any fail)
3. Record FSB_START timestamp
4. Capture pre-failback state on DR VM
5. Stop app on DR VM
6. Set DR VM to read-only (ALTER SYSTEM + reload), assert setting
7. **GATE 1 — `--confirm-destructive pg-primary`:** print "THIS WILL WIPE pg-primary DATA DIR"
8. Stop postgresql on pg-primary (assert inactive)
9. pg_basebackup on pg-primary from DR VM (-h 10.200.0.2, -R, --wal-method=stream)
10. Start pg-primary as standby, assert pg_is_in_recovery=t
11. Poll DR VM pg_stat_replication for 10.200.0.1, state=streaming (timeout 60s)
12. Poll catchup lag to near-zero (timeout 120s)
13. Assert DR VM still read-only
14. SELECT pg_promote() on pg-primary, assert pg_is_in_recovery=f
15. **GATE 2 — `--confirm-destructive dr-vm`:** print "THIS WILL WIPE DR VM DATA DIR"
16. Undo read-only on DR VM (ALTER SYSTEM RESET)
17. Stop postgresql on DR VM
18. pg_basebackup on DR VM from pg-primary (-h 10.200.0.1, -R, --wal-method=stream)
19. Start DR VM as standby, assert pg_is_in_recovery=t
20. Start keepalived on pg-primary, poll VIP returned (10s)
21. Start app on app-onprem (SSH multi-hop)
22. Poll /health on app-onprem (assert pg_is_in_recovery=false)
23. Verify pg_stat_replication on pg-primary shows 10.200.0.2 streaming
24. Capture all evidence
25. Record FSB_END, print RTO

---

### 5.6 `scripts/dr/dr-preflight.sh`

```
Purpose:    Validate steady-state readiness before any DR operation
Inputs:     <workflow> (onprem-ha | fullsite)
Outputs:    Table of pass/fail checks, exit 0 if all pass
Safety:     Read-only
```

Checks for `fullsite` mode:
- pg-primary: postgresql active, pg_is_in_recovery=f, keepalived active/MASTER
- pg-standby: postgresql active, pg_is_in_recovery=t (streaming)
- app-onprem: /health 200, pg_is_in_recovery=false
- DR VM: postgresql active, pg_is_in_recovery=t, replication lag < 65536 bytes
- WireGuard: handshake < 300s on both ends
- SSH ControlMaster: sockets fresh (rm + test as side effect)

---

### 5.7 `scripts/dr/evidence-export.sh`

```
Purpose:    Batch-export /tmp evidence files from all hosts to docs/05-evidence/
Inputs:     <phase> (onprem-ha | fullsite-failover | fullsite-failback)
Outputs:    Files copied to docs/05-evidence/<phase>-validation/, print manifest
Safety:     Read-only (scp from remote /tmp)
```

---

## 6. RTO reduction analysis

### Full-site failover

| Phase | Current (S4-09) | With automation | Notes |
|---|---|---|---|
| SSH pre-check | 0s (not done) | 5s | Prevents 45-min failure mode |
| Prerequisite checks | ~5 min (manual) | ~30s | Script with parallel SSH |
| Stop app on app-onprem | ~2 min | ~20s | Script with retry |
| Stop pg-primary services | ~1 min | ~10s | Script |
| WAL replay wait | ~30s | ~30s | Cannot be shortened |
| Promote DR VM | ~20s | ~10s | Script |
| Start app on DR VM | ~1 min | ~20s | Script |
| Validate health | ~1 min | ~15s | Script with assertion loop |
| SSH ControlMaster failure | ~45 min | 0 | Eliminated by pre-check |
| **TOTAL** | **48m 42s** | **~3-4 min** | |

**Target <5 min: YES, achievable immediately with ssh-precheck.sh as mandatory Step 0.**

### Full-site failback

| Phase | Current (S4-09) | With automation | Notes |
|---|---|---|---|
| Pre-checks | ~3 min | ~30s | Script |
| Stop app + read-only gate | ~2 min | ~30s | Script |
| pg_basebackup (pg-primary) | ~2 min | ~2 min | Data volume is the floor |
| Start standby + verify | ~3 min | ~1 min | Script with poll |
| Catchup wait | ~1 min | ~1 min | Data-volume dependent |
| Promote pg-primary | ~30s | ~10s | Script |
| Rebuild DR VM (basebackup) | ~3 min | ~3 min | Data volume is the floor |
| Start keepalived + VIP | ~1 min | ~20s | Script |
| Start app on app-onprem | ~2 min | ~30s | Script |
| Validate health | ~1 min | ~15s | Script |
| Evidence capture | ~2 min | ~30s | Script |
| **TOTAL** | **20m 53s** | **~8-10 min** | Floor = 2x pg_basebackup |

**Target <10 min: YES, achievable with fullsite-failback.sh.**

---

## 7. Execution strategy and prioritization

### Phase A — Zero-effort RTO fix (do this week, 30 min total)

Add a single mandatory pre-check step to both full-site runbooks:

```bash
# Step 0 — MANDATORY SSH PRE-CHECK (do before ANYTHING else)
rm -f ~/.ssh/ctl/pve
ssh pve 'echo "PVE OK"'
# Expected: PVE OK within 5s
# If it hangs or fails: do NOT proceed. Fix WSL network / SSH before continuing.
```

This is already documented in the runbooks as a best-practice note. It should be
promoted to a mandatory numbered step (before all others) and highlighted in red in
the runbooks. This single change eliminates the primary RTO risk from S4-09.

### Phase B — Script development (1-2 sprints, start with highest priority)

**Sprint S5-01 scope (recommended):**
1. `ssh-precheck.sh` — 1-2 hours, highest priority
2. `dr-preflight.sh` — 1-2 hours, low risk, high value for next drill prep
3. `evidence-export.sh` — 1 hour, no risk

**Sprint S5-02 scope (recommended):**
4. `onprem-failover.sh` + `onprem-fallback.sh` — 2-3 hours total
5. Update on-prem runbook to reference scripts

**Sprint S5-03 scope (recommended):**
6. `fullsite-failover.sh` — 3-4 hours (most complex SSH chain)
7. `fullsite-failback.sh` — 3-4 hours (two destructive gates)

### Phase C — Validation (each script before production use)

Each script must be:
1. Reviewed for correctness against the runbook
2. Dry-run tested with `--dry-run` flag (add to each script — print commands, do not execute)
3. Tested in a controlled non-production drill before use in a real DR event

### Phase D — Runbook updates

After each script is validated:
- Update corresponding runbook to reference script
- Keep manual steps as fallback documentation
- Add a note: "Script available at `scripts/dr/<name>.sh` — use in preference to manual steps"

---

## 8. What NOT to automate

| Item | Reason |
|---|---|
| DR VM pre-test-day setup (Docker, app copy) | One-time, not in RTO window, already done |
| pg-standby timeline rebuild after failback | Maintenance task, not a gate, needs careful data assessment |
| Automatic (unsupervised) failover trigger | DR events should always have a human decision gate |
| WireGuard key rotation | Out of scope, infrastructure-level change |
| Azure VM start/stop | Terraform manages this; not in DR runbook scope |
| ClickUp status updates | Manual — requires judgment about what "done" means |

---

## 9. Safety constraints for all scripts

Every script in `scripts/dr/` must follow these rules:

1. **No unsupervised execution** — all destructive scripts require `--confirm` flag
2. **Host verification** — every script asserts it is talking to the correct host before
   any stateful change (check hostname, not just IP)
3. **Assertion-first** — every step checks current state before acting; if state is already
   correct (idempotent), log and skip rather than fail
4. **Explicit lag gates** — no promotion happens before WAL replay lag < threshold
5. **Dry-run mode** — all scripts support `--dry-run` which prints commands without executing
6. **Exit codes** — 0=PASS, 1=assertion failure, 2=connectivity failure, 3=timeout
7. **Evidence capture built-in** — evidence files captured by the script, not a separate step
8. **No secret hardcoding** — replication password read from Key Vault or `~/.pgpass` only
9. **SSH via existing config** — use `~/.ssh/config` host aliases, not inline IP addresses

---

## 10. ClickUp recommendations

| Item | Action | Task |
|---|---|---|
| Create task: S5-01 ssh-precheck.sh | High priority, 1-2 hours | Link to this audit doc |
| Create task: S5-01 dr-preflight.sh | High priority, 1-2 hours | Link to this audit doc |
| Create task: S5-01 evidence-export.sh | Medium priority, 1 hour | Link to this audit doc |
| Create task: S5-02 onprem-failover.sh | Medium priority | Reference dr-validation-runbook.md |
| Create task: S5-02 onprem-fallback.sh | Medium priority | Reference dr-validation-runbook.md |
| Create task: S5-03 fullsite-failover.sh | High priority, 3-4 hours | Reference full-site-failover-runbook.md |
| Create task: S5-03 fullsite-failback.sh | High priority, 3-4 hours | Reference full-site-failback-runbook.md |
| Update S4-09 task 86c8u3pwy | Add automation audit note, link this doc | |
| Add runbook improvement items | Promote SSH pre-check to Step 0 in both runbooks | Quick-win |

---

## Appendix A: Step count summary per workflow

| Workflow | Manual steps | Evidence files | Terminal windows | Automatable steps |
|---|---|---|---|---|
| On-prem failover | ~25 commands | ~10 files | 3 | ~20 |
| On-prem fallback | ~15 commands | ~8 files | 3 | ~12 |
| Full-site failover | ~40 commands | 14 files | 4+ | ~35 |
| Full-site failback | ~50 commands | 17 files | 4+ | ~42 |

## Appendix B: SSH topology reminder

All scripts must handle the on-prem SSH relay topology:

- WSL -> pve (10.0.10.71): direct SSH via `ssh pve`
- WSL -> pg-primary (10.0.96.11): `ssh -J pve katar711@10.0.96.11`
- WSL -> pg-standby (10.0.96.14): via pg-primary relay (PVE cannot TCP-forward)
  `ssh -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/id_ed25519_dr_onprem katar711@10.0.96.11" katar711@10.0.96.14`
- WSL -> app-onprem (10.0.96.13): same relay via pg-primary
- WSL -> vm-pg-dr-fce (10.200.0.2): only via WireGuard from pg-primary (NSG restricts SSH to 10.200.0.1)
  Requires pg-primary to be running AND WireGuard active

ControlMaster sockets: `~/.ssh/ctl/pve` — always clear before any DR operation.
