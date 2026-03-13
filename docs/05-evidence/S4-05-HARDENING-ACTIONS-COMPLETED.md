# S4-05 Hardening Actions - Completed & Recommendations

**Date**: 2026-03-13T16:10Z
**Status**: In Progress

## Completed Hardening Actions ✓

### 1. Key Vault Purge Protection (COMPLETED)
**Action**: Enabled purge protection on `kvclopr2katarweu01gwc`
**Timestamp**: 2026-03-13T16:10:56Z
**Status**: ✓ Enabled
**Impact**: Low-risk, improves KV security posture
**Details**:
```
Before:  enablePurgeProtection: null
After:   enablePurgeProtection: true
Also verified:
  - enableSoftDelete: true ✓
  - softDeleteRetentionInDays: 7 ✓
  - enableRbacAuthorization: true ✓
```

**Defender Recommendation**: ✓ RESOLVED
- "Key vaults should have deletion protection enabled" → Completed

---

## Safe Hardening Recommendations (Low-Risk)

### 2. SSH Key-Based Authentication (RECOMMENDED)
**Priority**: CRITICAL
**Status**: Recommended for next cycle
**Rationale**:
- Defender for Cloud flagged as critical
- Requirement: Verify all machines support key-based auth without breaking operations
- Safe approach: Dual-enable both keys and passwords during transition, then disable passwords

**Implementation Plan**:
1. Verify current SSH config on pg-primary, pg-standby, app-onprem
2. Ensure all machines have key-based entries configured
3. Enable key-based requirement without disrupting existing access
4. Document transition procedure
5. Re-verify Defender score improvement

**Machines**: pg-primary, pg-standby, app-onprem

---

### 3. System Updates (HIGH Priority)
**Status**: Recommended for evaluation
**Rationale**:
- Defender flagged "System updates should be installed on your machines"
- Safe evaluation: Review what updates are available
- Decision: Apply critical security patches only, defer OS-level updates to maintenance window

**Azure Update Manager Integration**: 
- Consider enabling Azure Update Manager for patch management
- Allows scheduled, controlled updates
- Reduces manual management

---

### 4. Guest Account Cleanup (MEDIUM Priority)
**Status**: Deferred to future sprint
**Recommendation**: "Disabled accounts with owner permissions on Azure resources should be removed"
**Rationale**:
- Requires Azure AD audit
- Low immediate risk in dev environment
- Schedule for Security Sprint with full coordination

**Follow-up**: Audit guest accounts in Entra ID, document cleanup procedure

---

## High-Risk / Deferred Actions (Not for this sprint)

### NSG Rule Hardening
**Status**: DEFERRED
**Reason**: Risk of breaking PostgreSQL replication if changed without full topology review
**Recommendation**: Schedule comprehensive NSG audit with network team
**Key Consideration**: "Subnets should be associated with a network security group" - Verify all subnets have proper NSG assignments, but do not modify rules until replication path verified

### DDoS Protection Standard
**Status**: LOW PRIORITY
**Recommendation**: Defer to future. Consider cost-benefit for dev environment.

---

## On-Premises Security Assessment

### Current Configuration (Known)

| Component | Status | Notes |
|-----------|--------|-------|
| PostgreSQL | Running | Primary on pg-primary, Standby on pg-standby |
| Replication | Active | Via WireGuard tunnel (50820) |
| Keepalived VIP | Active | Maintains continuity |
| SSH Access | Active | To be hardened with key enforcement |
| UFW Firewall | Unknown | To be verified on each machine |

### Recommended Verification (Next Phase)

1. **SSH Key Status Check**
   - Verify ~/.ssh/authorized_keys exists and contains keys
   - Verify /etc/ssh/sshd_config allows key-based auth
   - Check for any password-only accounts that might be affected

2. **PostgreSQL Exposure Verification**
   - Confirm listen_address = localhost or specific interface (not 0.0.0.0)
   - Verify replication uses WireGuard tunnel only
   - Check firewall rules prevent external port 5432 access

3. **UFW Rules Review**
   - Document current rules: `sudo ufw status verbose`
   - Ensure:
     - SSH (22) only from bastion/mgmt
     - PostgreSQL (5432) only via WireGuard
     - Required services properly restricted

4. **WireGuard Tunnel Verification**
   - Confirm tunnel is up and active
   - Verify key rotation procedure exists
   - Check endpoint restrictions

---

## Evidence Collected

**Azure Security Changes**:
- KV purge protection enabled (verified above)
- Defender recommendations reviewed

**Documentation**:
- This file: S4-05-HARDENING-ACTIONS-COMPLETED.md
- Main audit: S4-05-SECURITY-AUDIT-20260313.md

---

## Next Steps for Following Sprint

1. SSH key enforcement (verify + enable)
2. System update assessment
3. Guest account audit and cleanup
4. Comprehensive NSG rule review
5. Network topology validation for replication
6. Add automated patch management

---

**Sprint Status**: ✓ Safe improvements applied, recommendations documented
**Blocker Risk**: LOW - All changes are low-risk or deferred
**Coordination Needed**: YES - for on-prem verification and Defender score tracking

