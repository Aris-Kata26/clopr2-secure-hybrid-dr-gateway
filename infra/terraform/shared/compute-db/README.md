# shared/compute-db — Interface Contract

## Purpose

This module defines the **logical interface** for a DR database VM across all cloud providers.

It is not a deployable Terraform module. It contains no resource blocks and no provider calls.
It is the **contract** that every provider-specific implementation must satisfy.

## Interface Variables

| Variable | Required | Purpose |
|---|---|---|
| `env_name` | yes | Logical environment label |
| `region` | yes | Provider-specific region string |
| `subnet_id` | yes | Provider-specific subnet reference |
| `vm_size` | yes | Provider-specific compute size |
| `ssh_public_key` | yes | Operator SSH public key |
| `wg_tunnel_ip` | yes | WireGuard tunnel IP (CIDR notation) |
| `wg_private_key` | yes | WireGuard private key (sensitive) |
| `wg_peer_public_key` | yes | On-prem peer public key (sensitive) |
| `wg_onprem_public_ip` | yes | On-prem public IP for WireGuard |
| `private_ip` | no | Static private IP (null = DHCP) |
| `disk_size_gb` | no | OS disk size (default 30 GB) |
| `postgres_version` | no | PG major version (default "16") |
| `pg_replication_password` | no | Replication password |
| `secret_store_id` | no | Secret store resource ID |
| `tags` | no | Resource tags/labels |

## Expected Outputs (all implementations must export)

| Output | Description |
|---|---|
| `vm_id` | Provider resource ID of the DB VM |
| `private_ip` | Private IP address |
| `public_ip` | Public IP address (WireGuard endpoint) |
| `identity_id` | Managed identity / IAM role / service account |

## Implementations

| Provider | Module path | Status |
|---|---|---|
| Azure | `providers/azure/compute-db/` | **Live — validated 2026-03-14** |
| AWS | `providers/aws/compute-db/` | Scaffold — not deployed |
| GCP | `providers/gcp/compute-db/` | Scaffold — not deployed |

## Size Mapping

| Logical size | Azure | AWS | GCP |
|---|---|---|---|
| Minimal DR VM (2 vCPU, 2 GB) | Standard_B2ats_v2 | t3.small | e2-small |
| Standard DR VM (2 vCPU, 4 GB) | Standard_B2s | t3.medium | e2-medium |

## WireGuard Tunnel IP Plan

| Provider | Tunnel subnet | VM tunnel IP | On-prem IP |
|---|---|---|---|
| Azure (live) | 10.200.0.0/30 | 10.200.0.2 | 10.200.0.1 |
| AWS (planned) | 10.200.0.4/30 | 10.200.0.6 | 10.200.0.5 |
| GCP (planned) | 10.200.0.8/30 | 10.200.0.10 | 10.200.0.9 |
