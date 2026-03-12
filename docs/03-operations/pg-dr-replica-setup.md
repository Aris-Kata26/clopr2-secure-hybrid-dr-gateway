# PostgreSQL DR replica setup (Azure VM)

This runbook configures the Azure VM as a streaming replica of the on-prem primary.

## Prereqs
- Site-to-site VPN is up and routes allow Azure VM -> on-prem primary/VIP on TCP 5432.
- VM has system-assigned identity and Key Vault access (Key Vault Secrets User).
- Replication password is stored in Key Vault as `pg-replication-password`.

## Network validation (evidence)
1. From the Azure VM, confirm connectivity to the on-prem primary/VIP:
   - `nc -zv <onprem-primary-or-vip> 5432`
2. Save output to evidence:
   - `docs/05-evidence/outputs/pg-dr-netcheck-YYYYMMDD.txt`

## Install PostgreSQL on Azure VM
1. Install packages:
   - `sudo apt-get update`
   - `sudo apt-get install -y postgresql`
2. Stop the service before base backup:
   - `sudo systemctl stop postgresql`

## Configure streaming replication
1. Fetch replication secret from Key Vault:
   - `az keyvault secret show --vault-name <kv-name> --name pg-replication-password --query value -o tsv`
2. Run base backup from the on-prem primary:
   - `sudo -u postgres pg_basebackup -h <onprem-primary-or-vip> -p 5432 -D /var/lib/postgresql/14/main -U replicator -Fp -Xs -P -R`
3. Ensure `primary_conninfo` is set in `postgresql.auto.conf` and that `standby.signal` exists.
4. Start PostgreSQL:
   - `sudo systemctl start postgresql`

## Replication validation (evidence)
1. On on-prem primary:
   - `SELECT client_addr, state, sync_state FROM pg_stat_replication;`
2. On Azure VM:
   - `SELECT pg_is_in_recovery();`
3. Save outputs:
   - `docs/05-evidence/outputs/pg-dr-primary-replication-YYYYMMDD.txt`
   - `docs/05-evidence/outputs/pg-dr-replica-recovery-YYYYMMDD.txt`

## If VPN is not ready
- Deploy VM and Key Vault integration now.
- Document replication as a dependency in evidence index until VPN is ready.

## Blocked by VPN (evidence)
If VPN is not ready, capture proof that the DR VM cannot reach the on-prem primary.

1. Connectivity check:
   - `nc -vz <onprem-primary-or-vip> 5432`
2. Route/path checks:
   - `ip route`
   - `traceroute <onprem-primary-or-vip>`
3. Save outputs:
   - `docs/05-evidence/outputs/pg-dr-netcheck-blocked-YYYYMMDD.txt`
   - `docs/05-evidence/outputs/pg-dr-route-blocked-YYYYMMDD.txt`
