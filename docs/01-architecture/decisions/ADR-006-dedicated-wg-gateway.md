# ADR-006 — Dedicated WireGuard Gateway Architecture

**Status:** Accepted — design complete, deployment deferred to post-presentation maintenance window
**Date:** 2026-03-18
**Author:** KATAR711 | Team: BCLC24
**Addresses:** S5 Weakness #2 — WireGuard co-hosted on PostgreSQL primary

---

## Context

WireGuard is currently hosted on two nodes:

- **On-prem:** `pg-primary` (10.0.96.11) — the PostgreSQL 16 primary, Keepalived MASTER
- **Azure:** `vm-pg-dr-fce` (10.200.0.2) — the DR PostgreSQL replica

`pg-primary` is the WireGuard initiator (`PersistentKeepalive = 25`); the Azure VM
listens on UDP 51820. The tunnel provides:

1. **Replication channel:** WAL streaming from `pg-primary:10.200.0.1` to
   `vm-pg-dr-fce:10.200.0.2` over TCP 5432.
2. **Management SSH path:** WSL → PVE → `pg-primary` → tunnel → `vm-pg-dr-fce`.
   This is the only path to the DR VM (`vm-pg-dr-fce` NSG blocks port 22 from internet).

### Weakness

Co-hosting WireGuard on the PostgreSQL primary creates a single failure domain:

| Event | PG impact | WireGuard impact |
|-------|-----------|-----------------|
| Planned failover (FS-3) | `postgresql` + `keepalived` stopped | **WG stays up** (separate `wg-quick@wg0` service) |
| On-prem HA failover (`onprem-failover.sh`) | VIP moves to pg-standby | **WG stays up** (pg-primary not rebooted) |
| **Unexpected pg-primary crash / reboot** | pg-standby takes over (HA) | **WG goes down** — DR VM becomes island |

The planned scenarios are safe. The gap is **unexpected pg-primary downtime**:
- DR VM loses its replication source (WAL replay stops).
- DR VM loses all SSH management access (tunnel gone, NSG blocks internet SSH).
- No other on-prem node (pg-standby, app-onprem) runs WireGuard as a fallback.

---

## Decision

Provision a **dedicated on-prem WireGuard gateway VM** (`wg-gw-onprem`) with a
single responsibility: maintain the WireGuard tunnel.

Remove WireGuard from `pg-primary`. All other on-prem nodes and the Azure DR VM
are unchanged in function; only the tunnel endpoint IP changes.

---

## Architecture — Before vs After

### Before (collocated, current state)

```
On-prem:
  pg-primary (10.0.96.11, Standard_B2ats_v2)
    ├── PostgreSQL 16 PRIMARY + Keepalived MASTER
    └── WireGuard wg0 (10.200.0.1/30)  ← tunnel endpoint

  pg-standby (10.0.96.14)
    └── PostgreSQL 16 standby (no WireGuard)

Azure:
  vm-pg-dr-fce (10.200.0.2/30, listener UDP 51820)
    ├── PostgreSQL 16 DR replica
    │   primary_conninfo: host=10.200.0.1 ...    ← pg-primary tunnel IP
    └── WireGuard wg0

SSH path:  WSL → PVE → pg-primary → tunnel → vm-pg-dr-fce
```

### After (ADR-006 target)

```
On-prem:
  pg-primary (10.0.96.11)
    ├── PostgreSQL 16 PRIMARY + Keepalived MASTER
    └── (no WireGuard)

  wg-gw-onprem (10.0.96.15, NEW — lightweight VM)
    └── WireGuard wg0 (10.200.0.3/30)  ← dedicated tunnel endpoint

  pg-standby (10.0.96.14)
    └── PostgreSQL 16 standby (unchanged)

Azure:
  vm-pg-dr-fce (10.200.0.2/30, listener UDP 51820 — unchanged)
    ├── PostgreSQL 16 DR replica
    │   primary_conninfo: host=10.200.0.3 ...    ← new gateway tunnel IP
    └── WireGuard wg0 (peer updated to wg-gw-onprem)

SSH path:  WSL → PVE → wg-gw-onprem → tunnel → vm-pg-dr-fce
```

---

## Specification — wg-gw-onprem VM

| Property | Value |
|----------|-------|
| Proxmox VM name | `wg-gw-onprem` |
| IP | `10.0.96.15` (static, same subnet as pg-primary) |
| Size | 1 vCPU, 512 MB RAM, 10 GB disk |
| OS | Ubuntu 22.04 LTS |
| Services | `wg-quick@wg0` only |
| PostgreSQL | No |
| Docker | No |
| Keepalived | No |
| Always-on | Yes (no auto-shutdown — tunnel must be persistent) |
| WireGuard role | Initiator (like current pg-primary) |
| Tunnel IP | `10.200.0.3/30` |
| PersistentKeepalive | 25 (same as current config) |

---

## Changes Required

### Terraform (`infra/terraform/envs/onprem/`)

New resource: `proxmox_virtual_environment_vm.wg_gw` — lightweight Ubuntu VM,
gated by `enable_wg_gateway = false` (deploy when ready).

### Ansible

- New inventory group `wg_gateway`; `wg-gw-onprem` as sole member
- `group_vars/wg_gateway.yml`: `wg_tunnel_ip: "10.200.0.3"`, `wg_is_listener: false`,
  `wg_peer_endpoint: "20.216.128.32"`, `wg_peer_allowed_ips: "10.200.0.2/32"`
- Remove `wg_*` vars from `group_vars/pg_primary.yml`
- Remove `pg_primary` from `[wg_nodes:children]` in `hosts.ini`

### DR VM changes

- `wg0.conf [Peer]`: update `PublicKey` to wg-gw-onprem's key, `AllowedIPs`
  to `10.200.0.3/32, 10.0.96.0/24`
- `postgresql.auto.conf` (via `pg_dr.yml`): `primary_conninfo host=10.200.0.3`
- `pg_hba.conf` WireGuard block: source CIDR `10.200.0.2/31` or `/32` for gateway
- NSG `pg_dr_allowed_ssh_cidrs`: add `10.200.0.3/32`

### Scripts

- `scripts/dr/ssh-precheck.sh`: `DIRECT_HOSTS` — replace
  ProxyJump via pg-primary with ProxyJump via wg-gw-onprem for `vm-pg-dr-fce`
- `scripts/dr/fullsite-failover.sh`: comment on FS-3 stays valid (WG on
  wg-gw-onprem, not touched by FS-3 which stops pg-primary)
- `~/.ssh/config` `dr-tunnel` Host: update ProxyJump from pg-primary to wg-gw-onprem

---

## Migration Plan (for maintenance window)

Execute in order. Each step is independently verifiable before the next.

1. Provision `wg-gw-onprem` via Terraform (`enable_wg_gateway = true`).
2. Run `ansible-playbook wg_tunnel.yml -l wg_gateway` — generates keypair, starts WG.
3. Add `wg-gw-onprem` as a **second** peer on DR VM (keep pg-primary peer active).
   Verify: `ping 10.200.0.3` from DR VM succeeds.
4. Update `primary_conninfo` on DR VM: `host=10.200.0.3` (via Ansible pg_dr.yml).
   `systemctl reload postgresql` on DR VM. Verify replication resumes.
5. Remove pg-primary peer from DR VM `wg0.conf` (`wg syncconf` — zero downtime).
6. Disable WireGuard on pg-primary: `systemctl stop && disable wg-quick@wg0`.
7. Update Ansible group_vars (pg_primary.yml, hosts.ini).
8. Update `~/.ssh/config` dr-tunnel ProxyJump chain.
9. Update `scripts/dr/ssh-precheck.sh` DIRECT_HOSTS.
10. Run `ssh-precheck.sh` and `dr-preflight.sh` — verify all PASS.

**Rollback (up to Step 5):** Re-enable pg-primary WireGuard, revert primary_conninfo.
**Rollback (after Step 5):** Re-add pg-primary peer to DR VM wg0.conf, revert primary_conninfo.

---

## Consequences

### Positive

- `pg-primary` crash no longer isolates the DR VM.
- Single-responsibility `wg-gw-onprem` can run always-on with no cost-saving
  auto-shutdown (WireGuard process is idle, minimal resource use).
- Cleaner operational model: pg-primary = PostgreSQL only.
- Full-site failover (FS-3 stops pg-primary) does not touch the tunnel VM — DR
  management path stays up throughout failover.

### Negative / Trade-offs

- Additional Proxmox VM to provision and patch.
- Migration requires coordinated changes across 5+ config files and a live
  PostgreSQL reload on the DR VM.
- New tunnel IP (10.200.0.3) requires pg_hba and NSG updates.
- `wg-gw-onprem` is a new SPOF: if it goes down, same isolation problem returns.
  Mitigation: `wg-gw-onprem` has no PG workload — far less likely to crash.

---

## Deployment Status

- Design: COMPLETE
- Terraform scaffolding: `enable_wg_gateway = false` variable added to
  `infra/terraform/envs/onprem/variables.tf`
- Live deployment: **DEFERRED** — intentional risk-managed decision (2026-03-18).
  Current collocated WireGuard path is production-safe for all planned operations.
  Deploy in first available 3-hour maintenance window after 2026-03-26.
- Validation: PENDING (requires wg-gw-onprem provisioned and dr-preflight.sh PASS)
