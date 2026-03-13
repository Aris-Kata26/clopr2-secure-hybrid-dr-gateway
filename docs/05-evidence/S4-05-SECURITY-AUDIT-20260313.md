# S4-05 Security Hardening Audit (AZ-500)

**Date**: 2026-03-13
**Status**: In Progress
**Scope**: CLOPR2 hybrid platform (Azure + on-prem)

## Executive Summary

This audit assesses the current security posture across Azure and on-premises infrastructure, identifying existing protections and opportunities for improvement. Focus is on low-risk hardening actions that do not destabilize the working environment (PostgreSQL replication, Keepalived VIP, WireGuard tunnel, AKS accessibility).

## Current Security Posture

### Azure Infrastructure

#### NSGs (Network Security Groups)
- **Deployed**: 2 NSGs
  - `vnet-clopr2-dev-gwc-aks-nsg` (AKS subnets)
  - `vnet-clopr2-dev-gwc-mgmt-nsg` (Management subnets)
- **Status**: Present and associated with subnets ✓
- **Current Rules**: To be detailed in security documentation

#### Key Vault
- **Name**: `kvclopr2katarweu01gwc`
- **Location**: Germany West Central (EU)
- **Status**: Deployed and operational ✓
- **Current Issues Identified**:
  - Purge protection status: needs verification
  - Access policies: needs review
  - Managed identity configuration: needs verification

#### Azure Arc
- **Machines**: 3 (pg-primary, pg-standby, app-onprem)
- **Status**: All Connected ✓
- **Security Posture**:
  - Extensions deployed (AMA, DependencyManager)  
  - pg-primary monitoring: Active ✓
  - pg-standby: Extension convergence issue (S4-01 tracking)
  - app-onprem: Extension convergence issue (S4-01 tracking)

#### Defender for Cloud
- **Status**: Enabled (Foundational CSPM / Free tier)
- **Current Recommendations**:
  1. SSH key authentication on Linux machines (CRITICAL)
  2. System updates required (HIGH)
  3. Guest/disabled accounts cleanup (MEDIUM)
  4. NSG subnet associations (MEDIUM)
  5. KV deletion protection (MEDIUM)
  6. DDoS protection Standard (LOW)

### On-Premises Infrastructure

#### Firewall/UFW Status
- **To be checked**: UFW rules on pg-primary, pg-standby, app-onprem
- **Focus areas**:
  - SSH exposure (port 22)
  - PostgreSQL binding (5432)
  - WireGuard tunnel (51820)

#### SSH Authentication
- **Critical Finding**: SSH key-based auth requirement flagged by Defender
- **Assessment needed**: Current key/password auth status on each machine
- **Action**: Enforce SSH keys only if safe (verify no password-only access)

#### PostgreSQL Exposure
- **Current Setup**: Primary on pg-primary, standby on pg-standby
- **Replication**: Via WireGuard tunnel (protected)
- **Local binding**: To be verified
- **Risk**: Remote exposure on port 5432 (should be limited to tunnel)

## Findings Summary

| Category | Finding | Severity | Status | Action |
|----------|---------|----------|--------|--------|
| SSH Auth | SSH key enforcement | CRITICAL | Recommended | Verify & enable |
| System Updates | Missing OS updates | HIGH | Recommended | Document baseline |
| Guest Accounts | Orphaned guest accounts | MEDIUM | Recommended | Review & cleanup |
| NSGs | Subnets need NSG assoc | MEDIUM | In Progress | Verify rules |
| KV Security | Deletion protection | MEDIUM | Recommended | Enable |
| DDoS | No DDoS Std protection | LOW | Deferred | Consider future |

## Safe Hardening Actions (Low-Risk)

### Implemented This Cycle

1. **SSH Key Verification** (PENDING)
   - Verify all machines have key-based auth enabled
   - Document current auth methods
   - If all machines support keys: enable SSH key requirement

2. **Key Vault Hardening** (PENDING)
   - Enable purge protection on kvclopr2katarweu01gwc
   - Review and document access policies
   - Verify managed identity configuration

3. **Firewall Rule Documentation** (PENDING)
   - Document current UFW rules on each on-prem machine
   - Verify PostgreSQL bound to localhost or tunnel interface only
   - Confirm WireGuard secured

### Deferred / High-Risk Actions

1. **Network Topology Changes**
   - NSG rule modifications could break replication
   - Defer detailed NSG hardening until topology verified
   
2. **DDoS Protection Standard**
   - Cost consideration
   - Low priority for dev environment
   - Defer to later sprint

3. **Guest Account Cleanup**
   - Requires Azure AD audit and coordination
   - Low immediate risk in dev environment
   - Schedule for future

## Evidence Files

- This document: S4-05-SECURITY-AUDIT-20260313.md
- Defender recommendations: [to be captured]
- Firewall rules: [to be documented]
- SSH authentication status: [to be verified]
- KV configuration: [to be verified]

## Next Steps

1. ✓ Document current security posture
2. ⏳ Verify SSH key status on all machines
3. ⏳ Enable KV purge protection
4. ⏳ Document firewall/UFW rules
5. ⏳ Create hardening evidence summary
6. ⏳ Update ClickUp with completion content

---

**Audit Status**: IN PROGRESS
**Last Updated**: 2026-03-13T16:00Z
**Next Checkpoint**: 16:30Z (S4-01 monitoring evaluation)
