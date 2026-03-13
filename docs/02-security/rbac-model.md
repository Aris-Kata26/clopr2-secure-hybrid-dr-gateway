# RBAC Model - Least Privilege Access Control

## Overview

The CLOPR2 hybrid platform implements a least-privilege RBAC model using Microsoft Entra ID (formerly Azure AD) to control access to Azure resources. Access is segregated by operational responsibility: Admins for deployment/operations, Viewers for audits/reporting.

## Group Structure

### Azure AD Groups

| Group Name | Purpose | Role | Scope |
|------------|---------|------|-------|
| BCLC24-OPS-ADMINS | Operational administration | Contributor | rg-clopr2-katar711-gwc |
| BCLC24-OPS-VIEWERS | Read-only audit access | Reader | rg-clopr2-katar711-gwc |

## Role Assignments

### Contributor (BCLC24-OPS-ADMINS)
**Scope**: Resource Group `rg-clopr2-katar711-gwc`

**Permissions Include**:
- Create, modify, delete resources
- Deploy infrastructure (Terraform, Bicep)
- Modify NSG/network rules
- Manage Key Vault secrets
- Control Arc extensions
- Manage AKS cluster

**Restrictions**:
- Cannot assign roles (Owner-level)
- Cannot delete subscription
- Cannot modify billing/quotas

### Reader (BCLC24-OPS-VIEWERS)
**Scope**: Resource Group `rg-clopr2-katar711-gwc`

**Permissions Include**:
- View all resources
- Read resource properties
- Access logs and monitoring
- Audit compliance

**Restrictions**:
- No create/modify/delete capability
- No secret read access (see KV section below)
- No configuration changes

## Key Vault Access (Special Case)

Key Vault uses its own RBAC model separate from RG-level roles:

**BCLC24-OPS-ADMINS in KV**:
- Role: Key Vault Secrets Officer (for rotation)
- Can: Read, create, delete, rotate secrets
- Cannot: Manage access policies

**Applications**:
- Use managed identities
- Assigned: Key Vault Secrets User (least privilege)
- Can: Read only specified secrets

## Least Privilege Justification

### Why This Model?
1. **Admins have Contributor, not Owner**: Prevents accidental subscription-level changes
2. **RBAC instead of access policies**: Centralized identity management via Entra ID
3. **Separate KV access**: Not inherited from RG; managed independently
4. **Viewers are read-only**: Reduces accidental changes, enables audit trail
5. **Managed identities for apps**: Eliminates shared credentials

### Risk Mitigation
- Separation of duties prevents single-person mistakes
- Audit trail in Resource Manager and Log Analytics
- Requires coordination for sensitive operations
- Limits scope of potential misuse

## Audit Trail

All RBAC changes are logged:
- **Azure Resource Manager**: Tracks role assignments
- **Log Analytics**: Monitors resource operations by user
- **Defender for Cloud**: Alerts on unusual access patterns

## Future Hardening (S4-05 Roadmap)

### Potential Improvements (Deferred)

1. **Subscription-Level Review**
   - Current: RG-scoped access
   - Future: Verify no subscription-level Owner roles assigned to users
   - Status: Deferred to enterprise governance phase

2. **Guest Account Cleanup**
   - Recommendation: Remove disabled/unused guest accounts
   - Status: Scheduled for future security sprint

3. **Conditional Access Policies**
   - Require MFA for sensitive operations
   - Restrict access from unknown locations
   - Status: Future consideration with Entra ID team

4. **Custom Roles**
   - Define fine-grained custom roles instead of Contributor
   - Current: Sufficient for dev environment
   - Future: Implement for production hardening

## Compliance Notes

- ✓ Least privilege: Contributor minimum for operations
- ✓ Separation of duties: Admins vs. Viewers
- ✓ Centralized identity: Entra ID as source of truth
- ✓ Audit logging: Integrated with Azure Monitor
- ✓ No hardcoded credentials: Managed identities for apps

## References

- Azure RBAC documentation: https://learn.microsoft.com/en-us/azure/role-based-access-control/
- Built-in Azure roles: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
- Microsoft Entra ID groups: https://learn.microsoft.com/en-us/entra/identity/hybrid/whatis-hybrid-identity
