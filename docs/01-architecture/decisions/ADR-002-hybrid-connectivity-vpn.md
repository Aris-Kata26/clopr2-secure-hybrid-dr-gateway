# ADR-002: Hybrid connectivity via Site-to-Site VPN

## Context
Need private connectivity between Proxmox on-prem and Azure resources.

## Decision
Use Site-to-Site IPsec VPN (enterprise-style) with least-privilege ports.

## Consequences
Routing and firewall/NSG design becomes a key implementation challenge.

