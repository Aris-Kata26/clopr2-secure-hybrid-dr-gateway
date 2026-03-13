# S4-01 Checkpoint Plan: Option A (Wait & Retry)

**Status**: ACTIVE - Controlled wait-and-retry approach in progress

## Timeline Summary

| Time | Action | Status |
|------|--------|--------|
| 15:51-16:00Z | Recreation cycle (pg-standby delete initiated) | ✓ Completed |
| 16:00Z | Polling window starts | ✓ Active |
| 16:00-16:30Z | 30-minute checkpoint monitoring | ⏳ In Progress |
| 16:30Z | Evaluate results & execute decision | ⏳ Pending |
| Post-16:30Z | Success or Escalation path | ⏳ Pending |

## What's Being Monitored (16:00-16:30Z)

### pg-standby Extensions
- **AzureMonitorLinuxAgent** (Microsoft.Azure.Monitor)
  - Current state at 16:00Z: `Deleting`
  - Tracking: Will it move past `Deleting` state?
- **DependencyAgentLinux** (Microsoft.Azure.Monitoring.DependencyAgent)
  - Current state at 16:00Z: `Deleting`
  - Tracking: Will it move past `Deleting` state?

### app-onprem Extensions
- **AzureMonitorLinuxAgent**
  - Last seen at 15:43Z: `Creating`
  - Tracking: Will it reach `Succeeded` or change state?
- **DependencyAgentLinux**
  - Last seen at 15:43Z: `Creating`
  - Tracking: Will it reach `Succeeded` or change state?

## Decision Tree (Evaluated at 16:30Z)

### Scenario 1: Both machines CONVERGED ✓
**Conditions**: 
- pg-standby: Past `Deleting` (either `Succeeded` or `Creating`)
- app-onprem: Past `Creating` (either `Succeeded` or other)

**Actions**:
1. Recreate extensions if needed
2. Run Heartbeat + Syslog validation (15m window)
3. If all 3 machines visible → capture PNG screenshots
4. Commit changes and push
5. **Close ClickUp task 86c8b2bb6** with completion comment
6. Mark S4-01 as **COMPLETE**

### Scenario 2: Both machines STILL LOCKED ✗
**Conditions**:
- pg-standby: Still in `Deleting` state 
- app-onprem: Still in `Creating` state

**Actions**:
1. Add formal blocker comment to ClickUp task
   - HCRP409 error evidence
   - Timeline from 15:51Z to 16:30Z
   - Proof DCR is healthy
   - Proof pg-primary monitoring works
2. Mark S4-01 task status as "Blocked - Azure Arc backend lock"
3. **Keep ClickUp task OPEN** (not closed)
4. Proceed to **S4-05 (Security hardening)** while keeping S4-01 context
5. Return to S4-01 monitoring in 30-60 minutes

### Scenario 3: Partial Progress ⚠
**Conditions**:
- One machine converged, one still locked

**Actions**:
1. Analyze which machine progressed
2. Attempt focused recreate on locked machine
3. Continue polling if progress detected
4. Escalate if no improvement in 15 minutes
5. Document partial progress in ClickUp

## Monitoring Infrastructure

**Active Scripts**:
- **Polling script**: `/tmp/checkpoint_polling.sh`
  - Running since: 16:00Z
  - Duration: 30 minutes (60-second intervals)
  - Output: `docs/05-evidence/monitoring/checkpoint-poll-20260313T1600-1630Z.txt`
  - Background PID: 84645

- **Evaluation script**: `/tmp/checkpoint_evaluate.sh`
  - Ready to execute at 16:30Z
  - Output: `docs/05-evidence/monitoring/checkpoint-evaluation-20260313T1630Z.md`
  - Automates decision tree logic

**Evidence Files Created**:
- `pg-standby-recreation-attempt-20260313T1557Z.md` - Recreation cycle details
- `checkpoint-poll-20260313T1600-1630Z.txt` - 30-minute polling log
- `checkpoint-evaluation-20260313T1630Z.md` - Evaluation results & decision

## Why This Approach

**Advantages**:
1. Gives Azure Arc backend time to complete deletion processing
2. Non-blocking: doesn't require constant manual intervention
3. Captures state transitions automatically
4. Data-driven decision making at checkpoint
5. Preserves forward momentum (Option C: can shift to S4-05 if needed)

**Risk Mitigation**:
- If still locked at 16:30Z: escalation path is pre-planned
- Task remains open to avoid premature closure
- Evidence is continuously captured for support escalation
- S4-01 context is preserved if moving to other work

## What Happens Now

✅ **You can proceed with other work** while monitoring runs in background
✅ **Set a reminder for 16:30Z** to evaluate results
✅ **No manual intervention needed** until checkpoint time

**Key point**: The polling script is collecting data automatically. No action required until 16:30Z UTC.

---

**Last Updated**: 2026-03-13T16:00:00Z
**ClickUp Task**: 86c8b2bb6 (Status: `planning`, **KEPT OPEN**)
**Outcome**: TBD (Pending 16:30Z checkpoint evaluation)
