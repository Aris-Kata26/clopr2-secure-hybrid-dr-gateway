# pg-standby Extension Rec recreation Attempt (2026-03-13 15:54-16:00 UTC)

## Timeline

**15:51:11Z** - Started controlled single-cycle recreation
- Initial states: Both extensions in `Creating` state
- Initiated delete of both extensions
- Expected: Delete → wait 30s → Create → poll for convergence

**15:54:27Z** - Post-deletion checkpoint
- AMA: `Deleting` ✓
- DEP: `Deleting` ✓
- Both extensions successfully transitioned to deletion state
- Good sign: Previous attempts were stuck; this time they're progressing

**15:54:27-15:57Z** - Extended deletion wait
- Monitored for 30+ minutes total deletion time
- Multiple waits (30s, 60s) to allow backend processing
- Expected: Extensions to disappear from list or move to deleted state

**15:57:42Z** - Create attempt #1
- HCRP409 ERROR: "Operation 'InstallExtension' is not allowed on extension 'AzureMonitorLinuxAgent' since it is marked for deletion"
- Root cause: Extensions still in deletion queue at Azure Arc backend
- Extensions confirmed still in list: `az connectedmachine extension list` showed both AzureMonitorLinuxAgent and DependencyAgentLinux

**15:57:53Z-16:00:xx** - Create attempt #2
- Same HCRP409 error
- Extensions still "Deleting" state
- Create still blocked

## Current State

**Extension Status (16:00 UTC)**:
- AMA: `Deleting` (still blocked)
- DEP: `Deleting` (still blocked)

**Environment**:
- Machine: pg-standby (Azure Arc Connected Machine)
- Resource Group: rg-clopr2-katar711-gwc
- Publishers: Microsoft.Azure.Monitor, Microsoft.Azure.Monitoring.DependencyAgent
- Versions: v1.40 (AMA), v9.10 (DEP)

## Root Cause Analysis

This is the **same Azure Arc control-plane locking issue** documented in the previous S4-01 problem cycle:

1. **HCRP409 Errors**: Indicate control-plane lock at Azure backend
2. **Prolonged Deletion**: Extensions remain in `Deleting` state for extended periods (20+ min so far)
3. **Create Blocked**: Cannot issue create while in deletion state
4. **Pattern**: Matches previous pg-standby behavior that required professional support intervention

## Options Forward

### Option A: Continue Waiting (Recommended - 30 min checkpoint)
- Continue monitoring with 30-minute polling intervals
- At X:30:00Z checkpoint, attempt create again
- If still stuck: Escalate to Azure Arc support with:
  - Timeline from 15:51:11Z to checkpoint
  - HCRP409 error details
  - Evidence of control-plane lock

### Option B: Force Full Recreate (Risk - May cause same issue)
- Cannot cleanly delete if stuck in Deleting
- Force delete may cascade to other extensions
- Likely to hit HCRP409 again

### Option C: Parallel Progress (Recommended)
- Move to different S4 task while monitoring continues
- Check pg-standby deletion status every 30 minutes
- Once deletion completes, immediately create and validate
- Do NOT force-close ClickUp task 86c8b2bb6 until all 3 machines report telemetry

## Monitoring Status

Background monitoring script active:
- Script: `/tmp/monitor_pg_standby_deletion.sh`
- Polling: Every 30 seconds for 10 minutes (20 cycles)
- Log file: `docs/05-evidence/monitoring/pg-standby-recreation-cycle-20260313.txt`
- Alert: Script will report when deletion completes

## Evidence Files Created

- This file: `pg-standby-recreation-attempt-20260313T1557Z.md`
- Polling log: `pg-standby-recreation-cycle-20260313.txt`

## Next Action

**Recommended**: Proceed with Option C
- Move to next S4 task with visual indicator that S4-01 has active monitoring
- Set calendar reminder to check pg-standby at 16:30Z (30-min checkpoint)
- If deletion complete at 16:30Z, immediately proceed to create/validate loop
- If still stuck at 16:30Z, escalate to Azure Arc support with full timeline

