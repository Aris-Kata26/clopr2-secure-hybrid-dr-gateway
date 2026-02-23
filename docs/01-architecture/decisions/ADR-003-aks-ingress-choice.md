# ADR-003: AKS ingress choice

## Context
Expose app endpoints securely in AKS.

## Decision
Use NGINX Ingress for Sprint 1 to keep setup fast and cost-aware while meeting rubric requirements.

### Design notes
- Region: Germany West Central.
- Node sizing: start small with 1-2 nodes.
- Networking: dedicated AKS subnet with NSG boundaries; no public admin access.

## Consequences
NGINX is quick to deploy and test, but requires manual TLS and routing configuration.
AGIC remains an option if Azure-native integration becomes a hard requirement later.

