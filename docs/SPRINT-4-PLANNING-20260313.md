# Sprint 4 Planning - CLOPR2 Hybrid Platform

**Planning Date**: 2026-03-13  
**Sprint Duration**: 2 weeks (estimated)  
**Framework**: AZ-500 (Azure Security Technologies) + DR High-Availability  
**Status**: DRAFT (ready for team review)

---

## Sprint Objective

Execute extension deployment validation (S4-01) and foundation security hardening (S4-05) to establish a production-ready, HA-enabled hybrid platform with security baseline.

**Success Criteria**:
1. ✓ Azure Arc extensions converged on pg-standby and app-onprem
2. ✓ PostgreSQL replication + Keepalived VIP validated in scale-out mode
3. ✓ Security baseline established (KV, RBAC, NSG documented)
4. ✓ Roadmap defined for future hardening phases

---

## Sprint Scope & Execution Order

### Phase 1: Checkpoint Validation (S4-01) — 16:00-16:30Z Monitoring Window

**Mission**: Validate Azure Arc extension deployment and test failover path  
**Status**: ACTIVE (monitoring in progress at 16:14Z)  
**Blocking**: None (monitoring-only, non-operational)

#### Tasks

| # | Task | Owner | Dependency | Est. Time | Risk |
|---|------|-------|------------|-----------|------|
| 1.1 | Poll extension states (pg-standby-dr + app-onprem) | DevOps | — | 20 min | Low |
| 1.2 | Verify PostgreSQL replication health | DevOps | 1.1 | 10 min | Low |
| 1.3 | Validate Keepalived VIP active on primary | DevOps | 1.2 | 5 min | Low |
| 1.4 | Test multi-hop failover path (AKS → VIP → WireGuard) | DevOps | 1.3 | 10 min | Medium |
| 1.5 | Document checkpoint results + evidence | DevOps | 1.4 | 10 min | None |

**Target Completion**: ~16:30Z UTC  
**Success Criteria**:
- Both extensions: Provisioning state = "Succeeded"
- PostgreSQL replication: Healthy (lag < 1s)
- Keepalived VIP: Active on primary
- Failover path: All hops reachable (ping/SSH via WireGuard)

**If Successful** → Proceed to Phase 3 (scale-out validation)  
**If Blocked** → Continue Phase 2 (S4-05 hardening), keep S4-01 polling active

---

### Phase 2: Security Hardening (S4-05) — Parallel / Contingency

**Mission**: Establish security baseline and audit compliance  
**Status**: COMPLETED (initial phase)  
**Risk**: LOW (no operational changes)  
**Blocking**: None (can proceed in parallel with S4-01)

#### COMPLETED Tasks ✓

| # | Task | Owner | Status | Evidence |
|---|------|-------|--------|----------|
| 2.1 | Full security audit (Azure + on-prem) | Security | ✓ Done | S4-05-SECURITY-AUDIT-20260313.md |
| 2.2 | Enable KV purge protection | DevOps | ✓ Done | kvclopr2katarweu01gwc configured |
| 2.3 | Document RBAC least-privilege model | Security | ✓ Done | rbac-model.md updated |
| 2.4 | Document NSG + on-prem firewall policy | Security | ✓ Done | network-least-privilege.md updated |
| 2.5 | Create hardening recommendations roadmap | Security | ✓ Done | S4-05-HARDENING-ACTIONS-COMPLETED.md |

#### Ready for Future Implementation (Deferred)

| # | Task | Priority | Estimated Time | Dependencies |
|---|------|----------|-----------------|---------------|
| 2.6 | SSH key-based auth enforcement | CRITICAL | 2-3 hours | Verify all machines support keys |
| 2.7 | System update baseline assessment | HIGH | 1-2 hours | Maintenance window coordination |
| 2.8 | Guest account cleanup | MEDIUM | 2 hours | Entra ID audit |
| 2.9 | Comprehensive NSG rule audit | MEDIUM | 3-4 hours | Network topology validation |
| 2.10 | DDoS Standard protection evaluation | LOW | 1 hour | Cost-benefit analysis |

---

### Phase 3: Scale-Out Validation (S4-02) — Conditional

**Mission**: Test failover scenarios and multi-site consistency  
**Status**: PENDING S4-01 checkpoint success  
**Prerequisites**: S4-01 extensions converged + replication healthy

#### Planned Tasks (Outline)

| # | Task | Owner | Est. Time | Risk |
|---|------|-------|-----------|------|
| 3.1 | Promote pg-standby-dr to primary (failover test) | DevOps | 30 min | Medium |
| 3.2 | Verify app connectivity via promoted VIP | QA | 15 min | Medium |
| 3.3 | Failback to original primary | DevOps | 20 min | Medium |
| 3.4 | Validate replication re-converges | DevOps | 15 min | Low |
| 3.5 | Multi-zone consistency check (if applicable) | QA | 15 min | Low |
| 3.6 | Document failover runbook + evidence | DevOps | 15 min | None |

**Timeline**: Only start if S4-01 succeeds at checkpoint (16:30Z+)  
**Blocking Risk**: If S4-01 stuck → defer S4-02 until resolution

---

## Execution Timeline

```
16:00Z ──┬─ S4-01: Extension polling (20-30 min)
         │
16:30Z ──┼─ CHECKPOINT EVALUATION
         │
         ├─ ✓ CONVERGED (likely path)
         │  └─> 16:45Z: Proceed to S4-02 scale-out
         │
         └─ ❌ BLOCKED (less likely, backend issues)
            └─> 17:00Z+: Continue S4-05 work, keep polling
```

### Decision Tree

**At 16:30Z Checkpoint**:
1. **S4-01 Extensions Converged?**
   - YES → Proceed to Phase 3 (S4-02)
   - NO → Check error state
     - Transient (HCRP409 lock) → Continue polling (15 min intervals)
     - Fatal → Escalate to Azure support, continue Phase 2 work

2. **S4-01 Extensions Converged + Replication Healthy?**
   - YES → Full green light for scale-out
   - NO → Investigate lag, confirm Keepalived active

3. **Failover Path Validated?**
   - YES → Document success, proceed to Phase 3
   - NO → Troubleshoot routing/WireGuard, defer Phase 3

---

## Sprint Deliverables

### S4-01 Deliverables (Checkpoint Phase)
- [ ] Extension convergence status report
- [ ] PostgreSQL replication health assessment
- [ ] Keepalived VIP validation evidence
- [ ] Failover path accessibility report
- [ ] Updated baseline snapshot (after extensions)

### S4-05 Deliverables (Hardening Phase)
- [x] Security audit report
- [x] Hardening actions log + recommendations
- [x] Executive summary for stakeholders
- [x] Updated security documentation (KV, RBAC, network)
- [x] GitHub commit with all evidence

### S4-02 Deliverables (Scale-Out Phase, if launched)
- [ ] Failover test runbook + results
- [ ] Multi-site consistency report
- [ ] Replication convergence evidence
- [ ] Updated DR playbook (promotes, failbacks)

---

## Risk Assessment & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| **S4-01: Extension timeout** | Medium | High | Pre-allocated polling intervals, escalation path |
| **S4-01: HCRP409 lock at backend** | Low | Medium | Known Azure issue, Azure support on speed-dial |
| **S4-02: Failover failure** | Low | High | Test in dev first, have rollback procedure |
| **S4-02: Replication lag spike** | Low | Medium | Monitor lag during tests, abort if > 5s |
| **Network connectivity loss** | Low | Medium | Polling tolerates transient loss (retry logic) |
| **PostgreSQL data inconsistency** | Very Low | Critical | Replication validation gate before failover |

**Blocking Risks**: None (all deferred until safety gates met)  
**Contingency**: Phase 2 (S4-05) can proceed independently if Phase 3 blocked

---

## Sprint Roles & Responsibilities

| Role | Name | Responsibilities |
|------|------|------------------|
| **Sprint Lead** | [DevOps Lead] | Orchestrate phases, decisions at checkpoints |
| **DevOps/Infra** | [Engineers] | Execute deployments, polling, failover tests |
| **Security** | [Security Engineer] | Audit, compliance verification, hardening oversight |
| **QA** | [QA Team] | Failover testing, application validation |
| **Network** | [Network Ops] | NSG validation, WireGuard tunnel support |
| **Stakeholders** | [Product/Ops] | Review deliverables, approve phase transitions |

---

## Success Criteria & Completion Gates

### Gate 1: S4-01 Checkpoint (16:30Z)
- ✓ Both extensions provisioning states = "Succeeded"
- ✓ PostgreSQL replication lag < 1s
- ✓ Keepalived VIP active
- ✓ Failover path reachable via WireGuard
- **Decision**: Proceed to Phase 3 OR continue polling

### Gate 2: S4-02 Scale-Out (if launched)
- ✓ Promotion to pg-standby completed successfully
- ✓ App accessible via promoted VIP
- ✓ Failback to primary completed
- ✓ Replication re-converges within 2 minutes
- ✓ Multi-zone consistency verified
- **Decision**: Mark S4-02 complete, update runbook

### Gate 3: S4-05 Completion
- ✓ Security audit documented
- ✓ KV hardening enabled
- ✓ RBAC model verified
- ✓ Deferred actions roadmap published
- ✓ All evidence committed
- **Decision**: Approve S4-05 for closure

---

## Documentation & Artifacts Requirements

**S4-01 Artifacts**
- Extension polling log (timestamp, state, errors)
- PostgreSQL replication status (pg_stat_replication output)
- Keepalived VIP status (systemctl status keepalived)
- WireGuard tunnel status (wg show)
- Evidence photos/screenshots (if manual verification)

**S4-05 Artifacts** (COMPLETED)
- S4-05-EXECUTIVE-SUMMARY-20260313.md
- S4-05-SECURITY-AUDIT-20260313.md
- S4-05-HARDENING-ACTIONS-COMPLETED.md
- Updated security documentation files

**S4-02 Artifacts** (if launched)
- Failover test procedure + results
- Replication convergence timeline
- Multi-site consistency logs
- DR playbook updates

---

## Escalation Contacts

| Issue | Contact | Priority |
|-------|---------|----------|
| Azure Arc extension stuck (HCRP409) | Azure Support | P1 |
| PostgreSQL replication failure | Database team | P1 |
| Network connectivity loss | Network Ops | P1 |
| Keepalived VIP not responding | Network Ops | P1 |
| Security compliance blocker | Security team | P1 |

---

## Sprint Artifacts & Links

**Evidence Location**: `/docs/05-evidence/`  
**S4-01 Polling**: `/docs/05-evidence/outputs/S4-01-*`  
**S4-05 Reports**: `/docs/05-evidence/S4-05-*`  
**Security Docs**: `/docs/02-security/`  
**ADR Decisions**: `/docs/01-architecture/decisions/`

---

## Next Sprint Preview (S5)

Based on S4 completion:
- **S5-01**: Security hardening phase 2 (SSH keys, system updates)
- **S5-02**: Comprehensive network audit (NSG rules + on-prem UFW alignment)
- **S5-03**: Production readiness review (Defender score, compliance)
- **S5-04**: Scaling & cost optimization (Azure + on-prem resources)

---

**Sprint Status**: Ready to launch  
**Estimated Duration**: 2 weeks (may extend if S4-01 blocked)  
**Team Agreement**: [Pending approval]  
**Planning Date**: 2026-03-13

