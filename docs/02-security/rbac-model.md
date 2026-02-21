# RBAC model (Admin vs Viewer) + role assignments

## Groups
- BCLC24-OPS-ADMINS
- BCLC24-OPS-VIEWERS

## Roles
- BCLC24-OPS-ADMINS: Contributor
- BCLC24-OPS-VIEWERS: Reader

## Scope
- Resource Group scope (CLOPR2 resource group in EU region)

## Least privilege justification
Admins can manage resources required for deployment and operations, while viewers have read-only access for audits and reporting. This separation reduces accidental changes and limits access to only what is needed.
