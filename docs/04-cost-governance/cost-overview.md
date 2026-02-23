# Cost overview

## Main expected cost drivers
- AKS nodes and control plane-related charges.
- VPN Gateway for hybrid connectivity.
- Azure Database for PostgreSQL.
- Log Analytics ingestion and retention.

## Cost control actions
- Keep node pools small (1-2 nodes) and right-size VM SKUs.
- Use dev-only schedules to shut down or scale down when idle.
- Delete unused resources quickly (old node pools, test gateways).
- Set budgets/alerts where allowed and review cost analysis weekly.

## Regional and credits note
- EU-only deployment: Germany West Central.
- Azure for Students credits apply; monitor burn rate and keep costs within credit limits.
