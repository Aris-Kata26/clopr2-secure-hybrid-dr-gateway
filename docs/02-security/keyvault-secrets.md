# Key Vault Security Configuration

## Overview

The CLOPR2 hybrid platform uses Azure Key Vault (`kvclopr2katarweu01gwc`) for centralized secret management, credential storage, and encryption key management.

## Current Configuration (as of 2026-03-13)

### KV General Settings
- **Name**: kvclopr2katarweu01gwc
- **Location**: Germany West Central (EU - data residency compliance)
- **SKU**: Standard
- **Status**: Operational

### Security Features Enabled

| Feature | Status | Details |
|---------|--------|---------|
| RBAC Authorization | ✓ Enabled | Access controlled via Microsoft Entra ID roles |
| Soft Delete | ✓ Enabled | 7-day retention for deleted items |
| Purge Protection | ✓ Enabled | Prevents immediate purge during soft-delete |
| Public Network Access | Enabled | Full public access (consider restricting via private endpoint) |

### Access Control Model

**Authorization Method**: RBAC (Role-Based Access Control)
- Uses Microsoft Entra ID for authentication
- Managed identity support for Azure resources
- Service principal support for applications

**Roles Assigned**:
- BCLC24-OPS-ADMINS: Reader in KV scope (for secret rotation tasks)
- Applications: Managed identities with least-privilege KV Get/List access

### What's Stored

**Current Secrets**:
- PostgreSQL connection strings
- WireGuard tunnel credentials
- Azure Arc authentication tokens
- Application API keys

**Best Practices Applied**:
- ✓ Centralized storage (not in code/config files)
- ✓ Version control via KV versioning
- ✓ Audit logging enabled via Azure Monitor
- ✓ RBAC instead of access policies (modern approach)

## Secrets Rotation Procedure

**Automated**: PostgreSQL replication credentials rotated by keepalived manager
**Manual**: WireGuard keys should be rotated annually (schedule: EOY)
**Documentation**: See docs/03-operations/pg-dr-replica-setup.md for replication secret handling

## Hardening Improvements Applied (S4-05)

### March 13, 2026 - Purge Protection Enabled
**Action**: Enabled purge protection to satisfy Defender for Cloud recommendation
**Impact**: Prevents accidental purging of soft-deleted secrets
**Risk Level**: Low - improves security without operational impact
**Status**: ✓ COMPLETED

## Future Security Enhancements

### Consider for Later Sprint:
1. **Private Endpoint**: Limit KV access to private network, disable public endpoint
   - Requires network topology review
   - May impact development workflows
   - Estimate: Medium effort

2. **Network ACLs**: Further restrict access to specific subnets
   - Risk: Could break legitimate access patterns
   - Defer until network design is finalized

3. **Customer-Managed Keys (CMK)**: Use HSM-backed keys for highly sensitive data
   - Cost impact: Moderate
   - Benefit: Enhanced compliance for future regulated workloads
   - Defer to production readiness phase

## Compliance Notes

- ✓ Data residency: EU (Germany West Central)
- ✓ RBAC: Least privilege enforced
- ✓ Audit logging: Integrated with Log Analytics
- ✓ Deletion protection: Soft delete + purge protection
- ✓ SEC-01 remediation: Secrets removed from code, centralized in KV

## References

- Azure Key Vault documentation: https://learn.microsoft.com/en-us/azure/key-vault/general/
- RBAC roles: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
- Secret rotation: docs/03-operations/pg-dr-replica-setup.md
