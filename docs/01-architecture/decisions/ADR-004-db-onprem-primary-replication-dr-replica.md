# ADR-004: DB on-prem primary + replication + DR replica (IaaS) + failover/failback

## Status
Accepted (Sprint 2 update)

## Context
Teacher requirement and multi-cloud readiness call for an on-prem primary database with a cost-aware IaaS DR replica, avoiding managed database services.
This supersedes the single-source-of-truth decision in ADR-001.

## Decision
Adopt an on-prem PostgreSQL primary/standby pair with streaming replication and a local VIP for apps, plus an Azure VM PostgreSQL DR replica over the site-to-site VPN.

## Architecture details
- Primary DB: Proxmox pg-primary.
- Standby DB: Proxmox pg-standby (streaming replication).
- VIP endpoint: keepalived + haproxy on-prem.
- DR replica: PostgreSQL on Azure VM (cost-aware) over VPN.

## Failover scenarios
a) VM failure on-prem: VIP moves, standby promoted, apps unchanged.
b) Site failure: promote Azure replica, Traffic Manager routes to Azure app.

## Failback runbook (summary)
1. Rebuild on-prem as a replica of the Azure primary.
2. Perform a planned switchover back to the on-prem VIP.
3. Re-seed the Azure replica from the on-prem primary.

## Consequences
- Requires replication monitoring, VIP health checks, and documented procedures.
- Azure VM sizing and uptime must remain cost-aware.
- Apps keep a stable DB endpoint (VIP or promoted DR) during failover.
