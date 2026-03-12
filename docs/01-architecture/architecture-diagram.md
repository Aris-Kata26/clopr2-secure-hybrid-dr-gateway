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

## Azure Arc — Hybrid Management Layer (additional sprint task, 2026-03-12)
- pg-primary, pg-standby, and app-onprem are onboarded as Arc-enabled servers.
- All three appear in Azure Resource Manager under rg-clopr2-katar711-gwc.
- Arc provides unified portal visibility, Azure Policy guest configuration, and Defender for Cloud coverage for the on-prem tier.
- The Arc management plane communicates outbound HTTPS only and does NOT interact with PostgreSQL replication, Keepalived, or WireGuard.
- Arc does NOT replace or modify any component of the DR path.
- Reference: docs/03-operations/azure-arc-integration.md
