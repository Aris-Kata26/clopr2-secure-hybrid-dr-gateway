"""
CLOPR2 DR Demo — Backend API
Reads evidence files from mounted volume. No live SSH connections.
Optional: polls a configurable app health URL if APP_HEALTH_URL is set.
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
import json, re, os
from datetime import datetime, timezone
import httpx

app = FastAPI(title="CLOPR2 DR Demo API", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

EVIDENCE_BASE = Path(os.environ.get("EVIDENCE_DIR", "/app/evidence"))
FULLSITE_DIR = EVIDENCE_BASE / "full-site-dr-validation"
ONPREM_DIR   = EVIDENCE_BASE / "dr-validation"
APP_HEALTH_URL = os.environ.get("APP_HEALTH_URL", "").strip()

SAFE_FILENAME_RE = re.compile(r'^[\w\-\.]+\.txt$')


def read_ev(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except FileNotFoundError:
        return None


def extract_json(text: str) -> dict | None:
    m = re.search(r'\{[^\n]+\}', text)
    if m:
        try:
            return json.loads(m.group())
        except json.JSONDecodeError:
            pass
    return None


# ─── Health ──────────────────────────────────────────────────────────────────

@app.get("/api/health")
async def api_health():
    return {"ok": True, "ts": datetime.now(timezone.utc).isoformat()}


# ─── Status ──────────────────────────────────────────────────────────────────

@app.get("/api/status")
async def get_status():
    app_health_json = None
    live_health = None

    # Try live HTTP health check if URL configured
    if APP_HEALTH_URL:
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                r = await client.get(APP_HEALTH_URL)
                if r.status_code == 200:
                    live_health = r.json()
        except Exception:
            pass

    # Fall back to evidence
    final_health_txt = read_ev(FULLSITE_DIR / "fsdb-final-app-health.txt")
    if final_health_txt:
        app_health_json = extract_json(final_health_txt)

    repl_txt    = read_ev(FULLSITE_DIR / "fsdb-replication-restored.txt")
    vip_txt     = read_ev(FULLSITE_DIR / "fsdb-vip-returned.txt")
    snapshot_txt = read_ev(FULLSITE_DIR / "fsdb-post-failback-snapshot.txt")

    return {
        "as_of": "2026-03-15T17:55:52Z",
        "source": "live" if live_health else "evidence",
        "components": {
            "pg_primary": {
                "host": "10.0.96.11",
                "role": "primary",
                "status": "healthy",
                "keepalived": "MASTER",
                "vip": "10.0.96.10",
                "wg_handshake_s": 15,
                "wal_lsn": "0/9000148",
                "detail": "pg_is_in_recovery=f - Keepalived MASTER - VIP active",
            },
            "vm_pg_dr": {
                "host": "10.200.0.2",
                "role": "replica",
                "status": "healthy",
                "lag_bytes": 0,
                "detail": "pg_is_in_recovery=t - streaming 0 lag from pg-primary",
            },
            "app_onprem": {
                "host": "10.0.96.13:8080",
                "status": "healthy",
                "health": live_health or app_health_json,
                "source": "live" if live_health else "evidence",
                "detail": "docker-app-1 running - /health 200",
            },
            "pg_standby": {
                "host": "10.0.96.14",
                "role": "needs_rebuild",
                "status": "degraded",
                "lsn": "0/542FD18",
                "detail": "Stuck at pre-failover LSN - maintenance required",
            },
            "wireguard": {
                "status": "active",
                "endpoint": "20.216.128.32:51820",
                "handshake_s": 15,
                "rx_mib": 34.25,
                "tx_mib": 39.78,
                "detail": "Persistent keepalive 25s",
            },
        },
        "drill_summary": {
            "last_failover_date": "2026-03-15",
            "last_failover_verdict": "PASS",
            "last_failback_date": "2026-03-15",
            "last_failback_verdict": "PASS",
            "rpo_bytes": 0,
            "current_mode": "normal",
        },
    }


# ─── Metrics ─────────────────────────────────────────────────────────────────

@app.get("/api/metrics")
async def get_metrics():
    return {
        "onprem_failover": {
            "rto_label": "<1s",
            "rto_sublabel": "VRRP - <5s app-confirmed",
            "rpo_label": "N/A",
            "date": "2026-03-14",
            "sprint": "S4-03",
            "verdict": "PASS",
        },
        "onprem_fallback": {
            "rto_label": "24s",
            "rto_sublabel": "Replication resumed automatically",
            "rpo_label": "0 bytes",
            "date": "2026-03-14",
            "sprint": "S4-03",
            "verdict": "PASS",
        },
        "fullsite_failover": {
            "rto_label": "48m 42s",
            "rto_sublabel": "Operational - <5 min clean (SSH interruption)",
            "rpo_label": "0 bytes",
            "date": "2026-03-15",
            "sprint": "S4-09",
            "verdict": "PASS",
        },
        "fullsite_failback": {
            "rto_label": "20m 53s",
            "rto_sublabel": "1253s - pg_basebackup + promote cycle",
            "rpo_label": "0 bytes",
            "date": "2026-03-15",
            "sprint": "S4-09",
            "verdict": "PASS",
        },
        "evidence_files": 33,
        "commits": ["c8063d4", "d59b7ae"],
    }


# ─── Evidence ────────────────────────────────────────────────────────────────

@app.get("/api/evidence")
async def list_evidence():
    files = []
    for phase_dir, phase_label in [
        (ONPREM_DIR,   "on-prem-ha"),
        (FULLSITE_DIR, "full-site-dr"),
    ]:
        if not phase_dir.exists():
            continue
        for f in sorted(phase_dir.glob("*.txt")):
            files.append({
                "name": f.name,
                "phase": phase_label,
                "size_bytes": f.stat().st_size,
            })
    return files


@app.get("/api/evidence/{filename}")
async def get_evidence(filename: str):
    if not SAFE_FILENAME_RE.match(filename):
        raise HTTPException(400, "Invalid filename")
    for d in [ONPREM_DIR, FULLSITE_DIR]:
        p = d / filename
        if p.exists():
            return {
                "filename": filename,
                "content": p.read_text(encoding="utf-8", errors="replace"),
            }
    raise HTTPException(404, f"{filename} not found")


# ─── Drills ──────────────────────────────────────────────────────────────────

DRILLS: dict = {
    "onprem-failover": {
        "id": "onprem-failover",
        "name": "On-Prem HA Failover",
        "date": "2026-03-14",
        "sprint": "S4-03",
        "verdict": "PASS",
        "rto": "<1s VRRP - <5s app-confirmed",
        "rpo": "N/A",
        "summary": "Keepalived VRRP moved VIP 10.0.96.10 from pg-primary to pg-standby in under 1 second. App continued serving reads via standby.",
        "steps": [
            {"id": "P-1", "name": "Pre-check: replication streaming",         "file": "precheck-replication.txt",      "status": "PASS", "detail": "pg-standby streaming async, near-zero lag"},
            {"id": "P-2", "name": "Pre-check: app health baseline",            "file": "precheck-app-health.txt",       "status": "PASS", "detail": "pg_is_in_recovery=false (primary active)"},
            {"id": "P-3", "name": "Pre-check: Keepalived primary MASTER",      "file": "precheck-keepalived-primary.txt","status": "PASS", "detail": "pg-primary MASTER, pg-standby BACKUP"},
            {"id": "P-4", "name": "Pre-check: VIP on pg-primary",              "file": "precheck-vip.txt",              "status": "PASS", "detail": "inet 10.0.96.10 on eth0 of pg-primary"},
            {"id": "F-1", "name": "Failover triggered (stop keepalived)",      "file": "failover-start-timestamp.txt",  "status": "PASS", "detail": "2026-03-14T15:33:50Z"},
            {"id": "F-2", "name": "VIP moved to pg-standby",                   "file": "failover-vip-moved.txt",        "status": "PASS", "detail": "inet 10.0.96.10 on eth0 of 10.0.96.14 (<1s)"},
            {"id": "F-3", "name": "pg-standby Keepalived -> MASTER",            "file": "failover-keepalived-standby.txt","status": "PASS", "detail": "Entering MASTER STATE"},
            {"id": "F-4", "name": "App confirms standby serving via VIP",      "file": "failover-app-health.txt",       "status": "PASS", "detail": "pg_is_in_recovery=true at 15:49:13Z"},
            {"id": "F-5", "name": "RTO timestamp captured",                    "file": "failover-rto-timestamp.txt",    "status": "PASS", "detail": "RTO <1s VRRP, <5s app-confirmed"},
        ],
    },
    "onprem-fallback": {
        "id": "onprem-fallback",
        "name": "On-Prem HA Fallback",
        "date": "2026-03-14",
        "sprint": "S4-03",
        "verdict": "PASS",
        "rto": "24s total",
        "rpo": "0 bytes",
        "summary": "pg-primary restarted. Keepalived priority 100 > 90 returned VIP automatically. Streaming replication resumed without manual intervention.",
        "steps": [
            {"id": "B-1", "name": "Started postgresql + keepalived on pg-primary", "file": "fallback-start-timestamp.txt",      "status": "PASS", "detail": "2026-03-14T15:52:15Z"},
            {"id": "B-2", "name": "VIP returned to pg-primary (priority 100)",     "file": "fallback-vip-returned.txt",          "status": "PASS", "detail": "inet 10.0.96.10 secondary on pg-primary eth0"},
            {"id": "B-3", "name": "pg-standby returned to BACKUP",                "file": "fallback-keepalived-standby.txt",    "status": "PASS", "detail": "Keepalived BACKUP (lower priority)"},
            {"id": "B-4", "name": "Replication resumed to pg-standby",            "file": "fallback-replication.txt",           "status": "PASS", "detail": "Streaming async, write_lag ~11ms"},
            {"id": "B-5", "name": "App confirms primary via VIP",                 "file": "fallback-app-health.txt",            "status": "PASS", "detail": "pg_is_in_recovery=false at 15:52:38Z"},
            {"id": "B-6", "name": "Post-test full snapshot",                      "file": "posttest-final-snapshot.txt",        "status": "PASS", "detail": "pg-primary MASTER, replication streaming, /health ok"},
        ],
    },
    "fullsite-failover": {
        "id": "fullsite-failover",
        "name": "Full-Site Failover -> Azure",
        "date": "2026-03-15",
        "sprint": "S4-09",
        "verdict": "PASS",
        "rto": "48m 42s operational (<5 min clean)",
        "rpo": "0 bytes",
        "summary": "Complete shutdown of on-prem services. Azure DR VM promoted to primary. Azure app started with --network host. All data preserved (0 bytes RPO).",
        "steps": [
            {"id": "P-1", "name": "Pre-check: primary state + replication",       "file": "fsdr-precheck-primary.txt",     "status": "PASS", "detail": "Both replicas 0 lag, WG 5s handshake"},
            {"id": "P-2", "name": "Pre-check: on-prem app healthy",               "file": "fsdr-precheck-app-health.txt",  "status": "PASS", "detail": "pg_is_in_recovery=false"},
            {"id": "P-3", "name": "Pre-check: DR VM ready (pg_is_in_recovery=t)", "file": "fsdr-precheck-drvm.txt",        "status": "PASS", "detail": "Replica streaming, Docker image present"},
            {"id": "F-1", "name": "Stop on-prem app (docker compose down)",       "file": "fsdr-app-stopped.txt",          "status": "PASS", "detail": "15:42:13Z"},
            {"id": "F-2", "name": "Capture final LSN (0/542FCA0, lag=0)",         "file": "fsdr-final-lsn.txt",            "status": "PASS", "detail": "bytes_lag=0 to DR VM"},
            {"id": "F-3", "name": "Stop postgresql + keepalived on pg-primary",   "file": "fsdr-primary-stopped.txt",      "status": "PASS", "detail": "Both inactive (dead) at 15:44:14Z"},
            {"id": "F-4", "name": "Wait for DR VM replay to stabilise",           "file": "fsdr-replay-wait.txt",          "status": "PASS", "detail": "replay_lsn stable at 0/542FD18"},
            {"id": "F-5", "name": "Promote DR VM (pg_promote)",                   "file": "fsdr-promoted.txt",             "status": "PASS", "detail": "pg_is_in_recovery=f, standby.signal absent"},
            {"id": "F-6", "name": "Write test on Azure primary",                  "file": "fsdr-write-test.txt",           "status": "PASS", "detail": "CREATE TABLE / INSERT 0 1 / DROP success"},
            {"id": "F-7", "name": "Start Azure app (--network host)",             "file": "fsdr-app-health-drvm.txt",      "status": "PASS", "detail": "pg_is_in_recovery=false, app_env=dr-azure"},
            {"id": "F-8", "name": "External health confirmation",                 "file": "fsdr-app-health-local.txt",     "status": "PASS", "detail": "/health 200 from WSL via run-command"},
            {"id": "F-9", "name": "RTO/RPO summary captured",                     "file": "fsdr-rto-summary.txt",          "status": "PASS", "detail": "RTO 48m 42s operational, RPO 0 bytes"},
            {"id": "F-10","name": "Post-failover snapshot",                       "file": "fsdr-post-failover-snapshot.txt","status": "PASS","detail": "Azure app running 20 min, pg primary confirmed"},
        ],
    },
    "fullsite-failback": {
        "id": "fullsite-failback",
        "name": "Full-Site Failback -> On-Prem",
        "date": "2026-03-15",
        "sprint": "S4-09",
        "verdict": "PASS",
        "rto": "20m 53s (1253s)",
        "rpo": "0 bytes",
        "summary": "Azure app stopped. pg-primary rebuilt from DR VM backup, promoted. DR VM rebuilt as standby. VIP restored. On-prem app healthy.",
        "steps": [
            {"id": "B-P1","name": "Pre-check: DR VM primary, pg-primary inactive","file": "fsdb-precheck.txt",             "status": "PASS", "detail": "WG 3s handshake, app-onprem stopped"},
            {"id": "B-1", "name": "Stop + remove Azure app container",            "file": "fsdb-azure-app-stopped.txt",    "status": "PASS", "detail": "17:32:10Z"},
            {"id": "B-2", "name": "Set DR VM read-only (ALTER SYSTEM)",           "file": "fsdb-drvm-readonly.txt",        "status": "PASS", "detail": "default_transaction_read_only=on"},
            {"id": "B-3", "name": "pg_basebackup on pg-primary from DR VM",       "file": "fsdb-pg-basebackup.txt",        "status": "PASS", "detail": "30774 kB, standby.signal present, 17:34:23Z"},
            {"id": "B-4", "name": "pg-primary starts as standby",                "file": "fsdb-primary-standby-start.txt","status": "PASS", "detail": "pg_is_in_recovery=t at 17:35:42Z"},
            {"id": "B-5", "name": "DR VM replication to pg-primary confirmed",    "file": "fsdb-drvm-replication.txt",     "status": "PASS", "detail": "10.200.0.1 streaming, 0 lag"},
            {"id": "B-6", "name": "Catch-up lag = 0 confirmed",                  "file": "fsdb-catchup-wait.txt",         "status": "PASS", "detail": "0 bytes lag"},
            {"id": "B-7", "name": "Promote pg-primary (pg_promote)",              "file": "fsdb-primary-promoted.txt",     "status": "PASS", "detail": "pg_promote()=t, pg_is_in_recovery=f at 17:40:33Z"},
            {"id": "B-8", "name": "Rebuild DR VM as standby (pg_basebackup)",     "file": "fsdb-drvm-rebuild.txt",         "status": "PASS", "detail": "pg_is_in_recovery=t after rebuild"},
            {"id": "B-9", "name": "Replication to DR VM restored",               "file": "fsdb-replication-restored.txt", "status": "PASS", "detail": "10.200.0.2 streaming, 0 lag"},
            {"id": "B-10","name": "VIP returned to pg-primary",                   "file": "fsdb-vip-returned.txt",         "status": "PASS", "detail": "Keepalived MASTER, inet 10.0.96.10 at 17:50:27Z"},
            {"id": "B-11","name": "Start on-prem app (docker compose up)",        "file": "fsdb-app-started.txt",          "status": "PASS", "detail": "docker-app-1 running"},
            {"id": "B-12","name": "App health confirmed",                         "file": "fsdb-app-health.txt",           "status": "PASS", "detail": "pg_is_in_recovery=false, app_env=dev"},
            {"id": "B-13","name": "Failback RTO/RPO summary",                     "file": "fsdb-rto-summary.txt",          "status": "PASS", "detail": "RTO 1253s (20m 53s), RPO 0 bytes"},
            {"id": "B-14","name": "Post-failback system snapshot",                "file": "fsdb-post-failback-snapshot.txt","status": "PASS","detail": "pg-primary PRIMARY, DR VM streaming, app healthy"},
            {"id": "B-15","name": "Final app health (WSL confirmed)",             "file": "fsdb-final-app-health.txt",     "status": "PASS", "detail": "pg_is_in_recovery=false, db_host=10.0.96.10"},
        ],
    },
}


@app.get("/api/drills")
async def list_drills():
    return [
        {k: v for k, v in d.items() if k != "steps"}
        for d in DRILLS.values()
    ]


@app.get("/api/drills/{phase_id}")
async def get_drill(phase_id: str):
    if phase_id not in DRILLS:
        raise HTTPException(404, f"Phase '{phase_id}' not found")
    return DRILLS[phase_id]
