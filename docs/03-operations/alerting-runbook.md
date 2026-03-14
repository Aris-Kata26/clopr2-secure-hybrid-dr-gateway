# Alerting and DR Operations Runbook
<!-- CLOPR2 Secure Hybrid DR Gateway | Owner: KATAR711 | Team: BCLC24 -->

## Azure Arc monitoring note

Azure Arc was integrated as a hybrid management enhancement.
Extension convergence instability during final validation meant Arc-dependent alerts
are not relied upon for DR acceptance. Core DR monitoring uses direct CLI checks
documented in this runbook and in `dr-validation-runbook.md`.

---

## Alert: PostgreSQL primary not running

**Detection:** `systemctl is-active postgresql` returns non-active on pg-primary
OR Keepalived VRRP election triggers VIP move.

**Response:**
1. Check postgresql service: `sudo systemctl status postgresql --no-pager`
2. Check logs: `sudo journalctl -u postgresql -n 50 --no-pager`
3. Attempt restart: `sudo systemctl start postgresql`
4. If restart fails, investigate data directory: `sudo -u postgres pg_lsclusters`
5. If unrecoverable, initiate manual failover: promote pg-standby (see DR runbook)
6. Capture evidence per `dr-validation-evidence-checklist.md`

---

## Alert: VIP missing from expected node

**Detection:** `ip addr show eth0 | grep '10.0.96.10'` returns nothing on pg-primary.

**Response:**
1. Check keepalived on primary: `sudo systemctl status keepalived --no-pager`
2. Check keepalived on standby: confirm it holds the VIP
3. If planned failover is in progress, document RTO per runbook
4. If unexpected: check if postgresql is healthy on primary (keepalived check may have triggered)
5. For fallback: `sudo systemctl restart keepalived` on pg-standby after primary postgres is verified healthy

---

## Alert: WireGuard tunnel down

**Detection:** `sudo wg show` shows no latest-handshake or handshake > 3 minutes old on pg-primary.

**Response:**
1. Check wg0 interface: `sudo wg show wg0`
2. Check wg service: `sudo systemctl status wg-quick@wg0`
3. Restart WireGuard: `sudo systemctl restart wg-quick@wg0`
4. Verify Azure DR VM is reachable: `ping -c 3 10.200.0.2`
5. If Azure VM unreachable, check Azure NSG (UDP 51820 from on-prem public IP)
6. Note: WireGuard outage does not affect on-prem HA (pg-primary/pg-standby/VIP)

---

## Alert: Streaming replication lag / disconnected

**Detection:** `pg_stat_replication` shows 0 rows or large write_lag/replay_lag.

**Response:**
1. Check replication: `sudo -u postgres psql -c "SELECT client_addr, state, write_lag, replay_lag FROM pg_stat_replication;"`
2. Check pg-standby: `sudo -u postgres psql -tc "SELECT pg_is_in_recovery();"`
3. If standby disconnected: check network (10.0.96.14 reachable from primary?)
4. If lag > 1 min: check disk I/O and wal_keep_size on primary
5. If Azure DR disconnected: check WireGuard tunnel first (see above)

---

## Alert: App /health not returning 200

**Detection:** `curl -s -o /dev/null -w "%{http_code}" http://10.0.96.13:8080/health` ≠ 200

**Response:**
1. Check Docker container: `docker ps` on app-onprem
2. Check container logs: `docker logs <container_id> --tail 50`
3. Check DB connectivity from app: confirm VIP (10.0.96.10:5432) is reachable from app-onprem
4. If VIP just moved (failover in progress), wait up to 30s for reconnect
5. If db_connected=false in health response, check PostgreSQL on VIP holder

---

## Routine health check commands (quick reference)

```bash
# On pg-primary
sudo systemctl is-active postgresql keepalived
ip addr show eth0 | grep '10.0.96'
sudo wg show
sudo -u postgres psql -c "SELECT client_addr, state FROM pg_stat_replication;"

# On pg-standby
sudo -u postgres psql -tc "SELECT pg_is_in_recovery();" | tr -d ' \n'
sudo systemctl is-active keepalived postgresql

# App health
curl -s http://10.0.96.13:8080/health
```
