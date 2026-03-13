# S4-05 Security Hardening - Executive Summary

**Date**: 2026-03-13  
**Status**: ✓ COMPLETED - Initial Hardening Phase  
**Scope**: CLOPR2 Hybrid Platform (Azure + On-Premises)  
**Framework**: AZ-500 (Azure Security Technologies)

---

## Current Security Posture

### ✅ Azure Infrastructure

**Key Vault** (`kvclopr2katarweu01gwc`)
- ✓ Purge protection: ENABLED
- ✓ Soft delete: ENABLED (7-day retention)
- ✓ RBAC authorization: ENABLED
- ✓ Audit logging: ENABLED
- **Defender Score Impact**: 1 recommendation resolved

**Network Security Groups**
- ✓ 2x NSGs deployed (AKS + Management subnets)
- ✓ Inbound rules: Restrictive (service mesh + health checks)
- ✓ Outbound rules: Explicit allow

**Azure Arc Managed Machines** (3 connected)
- ✓ pg-primary: Baseline extensions + monitoring
- ⏳ pg-standby: Extension convergence in progress (S4-01 tracked)
- ⏳ app-onprem: Extension convergence in progress (S4-01 tracked)

**Access Control (RBAC)**
- ✓ Least-privilege model implemented
- ✓ BCLC24-OPS-ADMINS: Contributor (not Owner)
- ✓ BCLC24-OPS-VIEWERS: Reader
- ✓ Managed identities: Apps use Key Vault Secrets User role

### ⏳ On-Premises Infrastructure

**Current State** (Baseline Assessment)
- PostgreSQL: Running (primary + standby via WireGuard)
- Keepalived VIP: Active
- WireGuard Tunnel: Operational
- UFW Firewall: Active on all 3 machines
- SSH Access: Operational (to be hardened)

**Defender for Cloud Issues Identified**
1. **SSH Key-Based Auth** (CRITICAL) — Recommended for enforcement
2. **System Updates** (HIGH) — Review and selective patching
3. **Guest Accounts** (MEDIUM) — Deferred to future coordination
4. **NSG Associations** (MEDIUM) — Deferred until network validation
5. **KV Deletion Protection** (MEDIUM) — ✓ RESOLVED

---

## Hardening Actions Applied ✓

### Completed This Cycle

| Action | Status | Risk | Evidence |
|--------|--------|------|----------|
| **KV Purge Protection** | ✓ Applied | Low | `kvclopr2katarweu01gwc` configured, Defender verified |
| **KV Soft Delete** | ✓ Verified | None | 7-day retention + RBAC enabled |
| **RBAC Model** | ✓ Documented | Low | Least-privilege roles mapped, audit logging |
| **Network Policy** | ✓ Documented | Low | NSG rules for AKS/management, UFW principles |
| **Security Audit** | ✓ Completed | None | Full posture assessment + risk classification |

**Total Risk**: LOW  
**Operational Impact**: NONE (security configuration only, no service changes)

---

## Deferred Hardening Recommendations

### Priority 1: SSH Key-Based Authentication (CRITICAL)
**Rationale**: Defender flagged as critical vulnerability  
**Safe Approach**: Dual-enable keys + passwords during transition, then disable passwords  
**Implementation**: 
- Verify all machines support key-based auth (pg-primary, pg-standby, app-onprem)
- Document current SSH configuration
- Enable key-only requirement without breaking access
- Re-verify Defender score improvement

**Timeline**: Next security sprint  
**Dependency**: None (low-risk)

### Priority 2: System Updates (HIGH)
**Rationale**: Defender flagged missing OS updates  
**Safe Approach**: Critical security patches only; defer OS-level updates to maintenance window  
**Recommendation**: 
- Evaluate Azure Update Manager for controlled patch scheduling
- Document baseline update requirements
- Create maintenance window procedure

**Timeline**: Next security sprint  
**Dependency**: Coordination with ops team for maintenance windows

### Priority 3: Guest Account Cleanup (MEDIUM)
**Rationale**: Defender found disabled accounts with owner permissions  
**Safe Approach**: Requires Entra ID audit and coordination  
**Recommendation**: 
- Audit all guest accounts in Entra ID
- Document cleanup procedure
- Correlate with least-privilege model

**Timeline**: Future sprint (low immediate risk)  
**Dependency**: Entra ID team coordination

### Priority 4: NSG Rule Hardening (MEDIUM)
**Rationale**: Comprehensive rule audit needed  
**Safe Approach**: Defer until network topology fully validated  
**Risk**: Misconfiguration could break PostgreSQL replication  
**Recommendation**: 
- Validate current replication path via WireGuard tunnel
- Document NSG rules + corresponding on-prem UFW rules
- Create validation procedure before rule changes

**Timeline**: Future sprint (after network validation)  
**Dependency**: Full network topology review

### Priority 5: DDoS Protection Standard (LOW)
**Status**: DEFERRED (cost-benefit for dev environment)  
**Timeline**: Future (no immediate risk)

---

## Evidence Files & Documentation

**Audit Reports**
- [S4-05-SECURITY-AUDIT-20260313.md](S4-05-SECURITY-AUDIT-20260313.md) — Full security posture assessment
- [S4-05-HARDENING-ACTIONS-COMPLETED.md](S4-05-HARDENING-ACTIONS-COMPLETED.md) — Detailed action log

**Updated Security Documentation**
- [docs/02-security/keyvault-secrets.md](../02-security/keyvault-secrets.md) — KV configuration + best practices
- [docs/02-security/rbac-model.md](../02-security/rbac-model.md) — Least-privilege RBAC structure
- [docs/02-security/network-least-privilege.md](../02-security/network-least-privilege.md) — NSG + UFW policy documentation

**Git Artifacts**
- Commit: `a7ff5b2` — All S4-05 evidence staged and committed

---

## Risk Assessment

### Completed Actions: **LOW RISK** ✓
- KV purge protection: Non-operational, security-only
- Documentation: No infrastructure changes
- No impact on PostgreSQL replication, Keepalived VIP, WireGuard, AKS access

### Deferred Actions: **LOW-MEDIUM RISK** (ready for next sprint)
- **SSH enforcement**: Low risk with dual-enable approach
- **System updates**: Medium risk (controllable via selec patching)
- **NSG rules**: Medium-High risk if not validated first (deferred)
- **Guest cleanup**: Low risk (audit-only, low business need)

---

## Next Steps for Following Sprint

1. **SSH Key Enforcement** (CRITICAL)
   - Verify configuration on all machines
   - Enable key-only requirement
   - Validate Defender score improvement

2. **System Update Assessment** (HIGH)
   - Evaluate Azure Update Manager
   - Document patch baseline
   - Create maintenance window procedure

3. **Guest Account Audit** (MEDIUM)
   - Coordinate with Entra ID team
   - Document cleanup procedure
   - Implement removal

4. **Network Topology Validation** (MEDIUM)
   - Validate NSG ↔ UFW rule mapping
   - Test replication path isolation
   - Document approved NSG changes

5. **Defender Score Tracking**
   - Baseline current score: _[to be captured]_
   - Track improvements after each hardening action
   - Document Defender recommendations resolution

---

## Stakeholder Summary

| Role | Action | Timeline |
|------|--------|----------|
| **Cloud Security** | Monitor KV purge protection compliance | Continuous |
| **Network Ops** | Review NSG rules + on-prem UFW alignment | Next sprint |
| **Sys Admin** | Enable SSH key enforcement | Next sprint |
| **Entra ID Team** | Audit + cleanup guest accounts | Future sprint |
| **Ops Lead** | Schedule system update maintenance window | Next sprint |

---

**Sprint Status**: ✓ **COMPLETED** (initial hardening + documentation)  
**Blocking Issues**: NONE (safe to proceed with deferred actions)  
**Coordination Needed**: YES (for future hardening phases)  
**Production Ready**: YES (changes do not destabilize operations)
