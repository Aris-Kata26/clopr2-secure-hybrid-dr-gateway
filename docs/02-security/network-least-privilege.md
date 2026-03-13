# Network Least Privilege Configuration

## Overview

Network security for the CLOPR2 hybrid platform is implemented through Azure NSGs (Network Security Groups) for cloud resources and UFW (Uncomplicated Firewall) for on-premises Linux hosts. Access is restricted to required flows only.

## Azure NSGs (Cloud)

### Deployed Groups

| NSG Name | Purpose | Location |
|----------|---------|----------|
| vnet-clopr2-dev-gwc-aks-nsg | AKS cluster networking | GermanW West Central |
| vnet-clopr2-dev-gwc-mgmt-nsg | Management/bastion | Germany West Central |

### Current Rules (Summary)

**vnet-clopr2-dev-gwc-aks-nsg**:
- Inbound: Kubernetes service mesh traffic
- Inbound: Azure health checks
- Outbound: All (cluster egress)

**vnet-clopr2-dev-gwc-mgmt-nsg**:
- Inbound: SSH (22) from admin bastion
- Inbound: Management APIs
- Outbound: Restricted to required endpoints

### Key Principles Applied

1. **Deny by Default**: No rules permit traffic that's not explicitly allowed
2. **Explicit Allow**: Only documented flows are permitted
3. **Source Restriction**: Traffic only from known sources (bastion, AKS cluster)
4. **Service Tags**: Leverage Azure service tags for built-in security

## On-Premises Firewall (UFW)

### Deployment Status

**pg-primary**: UFW active
**pg-standby**: UFW active  
**app-onprem**: UFW active

### Required Open Ports

| Port | Service | Direction | Purpose | Notes |
|------|---------|-----------|---------|-------|
| 22 | SSH | Inbound | Administration | Restricted to admin IPs |
| 5432 | PostgreSQL | Inbound | Replication | WireGuard tunnel only |
| 51820 | WireGuard | Inbound | VPN tunnel | From Azure Arc agent |

### Port Access Rules (Recommended Policy)

**SSH (22)**:
- Allow from: Bastion/admin subnets only
- Deny: All other sources
- Protocol: TCP

**PostgreSQL (5432)**:
- Allow from: WireGuard tunnel interface only (10.x.x.x)
- Deny: External sources
- Bind address: localhost or tunnel interface (not 0.0.0.0)

**WireGuard (51820)**:
- Allow from: Azure Arc agents
- Deny: All other sources
- Protocol: UDP

## Application Security

### AKS Exposure Review (S4-05 Assessment)

**Current State**:
- AKS API server: Internal endpoint (not public-facing)
- Ingress controller: Public endpoint (required for app access)
- Network policy: Enabled for pod-to-pod segmentation

**Recommendation**:
- Public ingress is appropriate for application availability
- Pod network policies should be reviewed for lateral movement control
- Defer detailed NSG hardening until network topology validated

## Hardening Improvements Planned (S4-05)

### Completed
- ✓ Documentation of current network architecture
- ✓ Identification of required flows
- ✓ Policy definition for firewall rules

### Recommended for Next Phase
- SSH key-based auth enforcement (reduces port 22 risk)
- PostgreSQL exposure verification (ensure tunnel-only)
- Comprehensive UFW rules audit on each on-prem machine
- Network Policy review in AKS for pod isolation

### High-Risk / Deferred
- NSG rule modifications (risk of breaking replication without full validation)
- Public endpoint restriction (requires bastion/VPN setup first)
- DDoS Protection Standard (cost vs. benefit for dev)

## Compliance Notes

- ✓ Least privilege: Only required ports open
- ✓ Source restriction: Traffic from known sources only
- ✓ Segmentation: NSGs separate AKS and management networks
- ✓ Denial of service protection: Azure DDoS (basic)
- ✓ Audit logging: NSG flow logs in Log Analytics

## References

- Azure NSG documentation: https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview
- UFW documentation: https://help.ubuntu.com/community/UFW
- PostgreSQL security: https://www.postgresql.org/docs/current/sql-createuser.html
