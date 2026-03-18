# Application Observability — CLOPR2 Secure Hybrid DR Gateway

**Owner:** KATAR711 | **Team:** BCLC24
**Implemented:** 2026-03-18 (architecture hardening phase)
**App version:** 0.2.0

---

## Overview

The FastAPI prototype app (`clopr2-prototype-a`) exposes four HTTP endpoints and emits structured JSON logs to stdout. The goal is to make the app's health observable from monitoring systems without adding external dependencies.

---

## Endpoints

### `GET /health` — DB connectivity check

| DB state | HTTP status | `db` field | Notes |
|----------|------------|------------|-------|
| Reachable | 200 | `"ok"` | `pg_is_in_recovery` reflects which PG node is serving |
| Unreachable | 503 | `"unreachable"` | `error` field contains psycopg exception message |
| Disabled (`DB_ENABLED=false`) | 200 | `"disabled"` | Test/offline mode |

**200 response (normal):**
```json
{
  "status": "ok",
  "db": "ok",
  "db_host": "10.0.96.10",
  "pg_is_in_recovery": false,
  "app_env": "dev",
  "ts": "2026-03-18T14:02:49Z"
}
```

**503 response (DB unreachable):**
```json
{
  "status": "error",
  "db": "unreachable",
  "db_host": "10.0.96.10",
  "error": "connection failed: ...",
  "app_env": "dev",
  "ts": "2026-03-18T13:53:24Z"
}
```

**Behaviour during failover:**
- `/health` remains 200 throughout on-prem HA failover (VIP moves, DB stays reachable)
- `pg_is_in_recovery` changes from `false` to `true` if app connects to standby
- DR failover (pg-dr takes over): `/health` continues serving while DR is replica;
  if on-prem goes down before DR promotion, `/health` returns 503 until DR is promoted

**Connection timeout:** 5 seconds (psycopg `connect_timeout=5`). A 503 has a worst-case
latency of ~5s from the caller's perspective when the DB host is unreachable.

---

### `GET /readyz` — Liveness check

Returns `200` unconditionally as long as the FastAPI event loop is responsive.
Does **not** check the database.

```json
{"status": "ready", "ts": "2026-03-18T14:02:50Z"}
```

**Use case:**
- Docker `HEALTHCHECK` uses `/readyz` — container is `healthy` as long as the app process
  is alive, regardless of DB state
- Kubernetes readiness/liveness probes
- Separates "app is alive" from "DB is connected" concerns

---

### `GET /metrics` — In-memory counters

Returns JSON counters accumulated since the last container start. No Prometheus,
no external dependencies.

```json
{
  "uptime_seconds": 666.8,
  "health_checks_total": 47,
  "db_ok_total": 33,
  "db_error_total": 14,
  "db_disabled_total": 0,
  "readyz_total": 4,
  "app_env": "dev",
  "version": "0.2.0"
}
```

**Limitations:** Counters reset on container restart. Not persisted, not scraped by Prometheus.
Intended for manual inspection and basic trend visibility in the DR demo context.

---

### `GET /` — Service info

Returns app name, version, environment, and endpoint map. Always 200.

---

## Structured JSON Logging

All health check events are emitted as JSON to stdout (Docker captures this as container logs).

### Log format

```json
{
  "ts": "2026-03-18T14:02:49Z",
  "level": "INFO",
  "logger": "clopr2.app",
  "msg": "health_check",
  "db": "ok",
  "db_host": "10.0.96.10",
  "pg_is_in_recovery": false
}
```

### Events and fields

| Event | Level | Key fields |
|-------|-------|-----------|
| App startup | INFO | `app_env`, `db_host`, `version` |
| `/health` — DB ok | INFO | `db="ok"`, `db_host`, `pg_is_in_recovery` |
| `/health` — DB error | WARNING | `db="unreachable"`, `db_host`, `error` |
| `/health` — DB disabled | INFO | `db="disabled"` |
| `/readyz` | INFO | `ts` |

### Viewing logs

```bash
# Live
docker logs -f docker-app-1

# Last 50 lines
docker logs --tail=50 docker-app-1

# Filter DB errors only
docker logs docker-app-1 2>&1 | grep '"db": "unreachable"'

# Count DB errors
docker logs docker-app-1 2>&1 | grep -c '"db": "unreachable"'
```

---

## Docker Healthcheck

The Docker HEALTHCHECK in `docker-compose.yml` was updated to use `/readyz`:

```yaml
healthcheck:
  test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/readyz')"]
  interval: 15s
  timeout: 5s
  retries: 3
  start_period: 10s
```

**Before (v0.1.0):** Used `/health` — container was `unhealthy` when DB was down even if
the app process was running fine.

**After (v0.2.0):** Uses `/readyz` — container is `healthy` whenever the app process is
alive. DB connectivity is a separate concern monitored via Azure Monitor alerts and `/health`.

---

## Observability Stack Integration

| Signal | Source | Where it goes |
|--------|--------|---------------|
| `/health` HTTP status | Azure Monitor alert `alert-onprem-heartbeat-silence` | Azure Monitor → email |
| Container stdout JSON logs | Docker → syslog → AMA → Log Analytics | `log-clopr2-dev-gwc` workspace |
| `/metrics` counters | Manual curl or future Prometheus scrape | N/A (manual only) |
| Container health | `docker ps` | Local only |

**AMA syslog note:** The AMA (Azure Monitor Agent) on app-onprem captures systemd/syslog
events including Docker container log output forwarded via the Docker syslog driver.
See `docs/03-operations/monitoring-architecture.md` for AMA configuration details.

---

## Limitations

| Item | Status |
|------|--------|
| `/metrics` persistence | Resets on container restart — no persistent store |
| Prometheus scrape endpoint | Not implemented — `/metrics` is JSON-only |
| Request-level tracing | Not implemented |
| Log aggregation in Azure | Via AMA syslog pipeline — some latency/loss possible |
| 503 response latency | Up to 5s (connect_timeout) when DB host is unreachable |

---

## Evidence

`docs/05-evidence/app-resilience/`

| File | Contents |
|------|----------|
| `00-summary.txt` | Task summary and AC results |
| `01-health-200.txt` | `/health` 200 response + log entry |
| `02-health-503.txt` | `/health` 503 response + log entry |
| `03-readyz-and-metrics.txt` | `/readyz`, `/metrics`, `/` endpoint outputs |
| `04-structured-logs.txt` | Sample structured log entries (startup, ok, error, readyz) |
| `05-container-status.txt` | Container status post-deploy |
