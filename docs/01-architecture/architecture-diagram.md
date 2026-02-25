# Architecture diagram description

This document describes the components shown in the architecture diagram files:
- docs/01-architecture/architecture-diagram.png
- docs/01-architecture/architecture-diagram.drawio

## On-prem (Proxmox)
- PostgreSQL primary: pg-primary.
- PostgreSQL standby: pg-standby with streaming replication.
- VIP endpoint for apps: keepalived + haproxy.
- On-prem app services point to the VIP, so failover is transparent.

## Azure (DR site)
- AKS runs the Azure app tier.
- PostgreSQL DR replica runs on an Azure VM (cost-aware IaaS).
- Traffic Manager routes users to the Azure app during site-level failover.

## Connectivity
- Site-to-site VPN connects on-prem and Azure VNets.
- VPN carries replication traffic and app-to-DB connectivity when needed.

## Failover behavior
- On-prem VM failure: VIP moves to pg-standby and it is promoted.
- Site failure: Azure VM replica is promoted; Traffic Manager directs traffic to Azure.
