"""
CLOPR2 DR Demo — Backend API v3.0
- Evidence file reader (read-only volume mount)
- Optional live app health polling
- Live script execution control plane (LIVE_MODE_ENABLED + LIVE_ACTION_SCOPE)
- SSE log streaming for live runs
"""
import asyncio
import json
import os
import re
import uuid
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import httpx

app = FastAPI(title="CLOPR2 DR Demo API", version="3.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# ── Config ────────────────────────────────────────────────────────────────────
EVIDENCE_BASE    = Path(os.environ.get("EVIDENCE_DIR", "/app/evidence"))
FULLSITE_DIR     = EVIDENCE_BASE / "full-site-dr-validation"
ONPREM_DIR       = EVIDENCE_BASE / "dr-validation"
APP_HEALTH_URL   = os.environ.get("APP_HEALTH_URL", "").strip()
LIVE_MODE_ENABLED = os.environ.get("LIVE_MODE_ENABLED", "false").lower() == "true"
SCRIPTS_DIR      = Path(os.environ.get("SCRIPTS_DIR", "/app/scripts"))
# none → no live actions; onprem → precheck+onprem+export; all → includes fullsite
LIVE_ACTION_SCOPE = os.environ.get("LIVE_ACTION_SCOPE", "none").lower()

SAFE_FILENAME_RE = re.compile(r'^[\w\-\.]+\.txt$')

# ── Action whitelist (zero user input reaches shell) ─────────────────────────
ACTIONS: dict[str, dict] = {
    "precheck_onprem": {
        "script": "ssh-precheck.sh", "args": [],
        "destructive": False, "dry_run_supported": False,
        "confirm_token": None, "flags_live": [],
        "scope": "onprem",
        "label": "SSH Pre-Checks",
        "description": "Checks SSH connectivity to all infra hosts. Read-only. Safe to run anytime.",
    },
    "precheck_fullsite": {
        "script": "dr-preflight.sh", "args": ["fullsite"],
        "destructive": False, "dry_run_supported": False,
        "confirm_token": None, "flags_live": [],
        "scope": "onprem",
        "label": "DR Preflight",
        "description": "Validates replication state, WireGuard, DR VM readiness. Read-only.",
    },
    "onprem_failover": {
        "script": "onprem-failover.sh", "args": [],
        "destructive": True, "dry_run_supported": True,
        "confirm_token": "FAILOVER", "flags_live": ["--confirm"],
        "scope": "onprem",
        "label": "On-Prem Failover",
        "description": "Stops keepalived on pg-primary. VIP 10.0.96.10 moves to pg-standby (10.0.96.14).",
    },
    "onprem_fallback": {
        "script": "onprem-fallback.sh", "args": [],
        "destructive": True, "dry_run_supported": True,
        "confirm_token": "FALLBACK", "flags_live": ["--confirm"],
        "scope": "onprem",
        "label": "On-Prem Fallback",
        "description": "Restarts services on pg-primary. Keepalived returns VIP automatically.",
    },
    "export_evidence": {
        "script": "evidence-export.sh", "args": [],
        "destructive": False, "dry_run_supported": True,
        "confirm_token": None, "flags_live": [],
        "scope": "onprem",
        "label": "Export Evidence",
        "description": "Copies /tmp evidence files into docs/05-evidence/. Dry-run safe.",
    },
    "fullsite_failover": {
        "script": "fullsite-failover.sh", "args": [],
        "destructive": True, "dry_run_supported": True,
        "confirm_token": "FAILOVER", "flags_live": ["--confirm"],
        "scope": "all",
        "label": "Full-Site Failover",
        "description": "Stops ALL on-prem services. Promotes Azure DR VM to primary. Starts DR app.",
    },
    "fullsite_fallback": {
        "script": "fullsite-fallback.sh", "args": [],
        "destructive": True, "dry_run_supported": True,
        "confirm_token": "FALLBACK",
        "flags_live": ["--confirm-destructive", "pg-primary", "--confirm-destructive", "dr-vm"],
        "scope": "all",
        "label": "Full-Site Fallback",
        "description": "Stops Azure app. Rebuilds pg-primary from DR VM. Restores VIP and on-prem app. Two-gate destructive.",
        "two_gate": True,
    },
}


def _action_enabled(action_id: str) -> bool:
    """True iff LIVE_MODE_ENABLED and LIVE_ACTION_SCOPE covers this action's scope."""
    if not LIVE_MODE_ENABLED:
        return False
    scope = ACTIONS[action_id]["scope"]
    if LIVE_ACTION_SCOPE == "all":
        return True
    if LIVE_ACTION_SCOPE == "onprem":
        return scope == "onprem"
    return False  # "none"


# ── Run state ─────────────────────────────────────────────────────────────────
@dataclass
class RunState:
    run_id: str
    action: str
    dry_run: bool
    started_at: str
    status: str = "running"          # running | passed | failed | error
    exit_code: Optional[int] = None
    lines: deque = field(default_factory=lambda: deque(maxlen=2000))
    done: asyncio.Event = field(default_factory=asyncio.Event)
    finished_at: Optional[str] = None


active_run: Optional[RunState] = None
run_registry: dict[str, RunState] = {}   # keyed by run_id, last 20
run_history: list[dict] = []             # serialized summaries, last 20


async def _execute_run(state: RunState, cmd: list[str]) -> None:
    global active_run
    try:
        env = {**os.environ, "TERM": "xterm-256color"}
        home = os.environ.get("HOME", "/root")
        env["HOME"] = home
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env=env,
        )
        async for raw in proc.stdout:
            line = raw.decode("utf-8", errors="replace").rstrip("\n")
            state.lines.append(line)
        await proc.wait()
        state.exit_code = proc.returncode
        state.status = "passed" if proc.returncode == 0 else "failed"
    except Exception as exc:
        state.lines.append(f"[backend-error] {exc}")
        state.status = "error"
        state.exit_code = -1
    finally:
        state.finished_at = _now()
        state.done.set()
        run_history.append({
            "run_id": state.run_id,
            "action": state.action,
            "dry_run": state.dry_run,
            "started_at": state.started_at,
            "finished_at": state.finished_at,
            "status": state.status,
            "exit_code": state.exit_code,
            "label": ACTIONS[state.action]["label"],
        })
        if len(run_history) > 20:
            run_history.pop(0)
        if len(run_registry) >= 20:
            oldest = next(iter(run_registry))
            del run_registry[oldest]
        active_run = None


# ── Helpers ───────────────────────────────────────────────────────────────────
def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_ev(path: Path) -> Optional[str]:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except FileNotFoundError:
        return None


def extract_json(text: str) -> Optional[dict]:
    m = re.search(r'\{[^\n]+\}', text)
    if m:
        try:
            return json.loads(m.group())
        except json.JSONDecodeError:
            pass
    return None


# ── Health ────────────────────────────────────────────────────────────────────
@app.get("/api/health")
async def api_health():
    return {"ok": True, "ts": _now()}


# ── Mode ──────────────────────────────────────────────────────────────────────
@app.get("/api/mode")
async def get_mode():
    scripts_available: list[str] = []
    if SCRIPTS_DIR.exists():
        for name, spec in ACTIONS.items():
            if (SCRIPTS_DIR / spec["script"]).exists():
                scripts_available.append(name)

    enabled_actions = {
        k: {
            "label": v["label"],
            "description": v["description"],
            "destructive": v["destructive"],
            "dry_run_supported": v["dry_run_supported"],
            "confirm_token": v.get("confirm_token"),
            "two_gate": v.get("two_gate", False),
            "scope": v["scope"],
            "enabled": _action_enabled(k),
        }
        for k, v in ACTIONS.items()
    }
    return {
        "live_enabled": LIVE_MODE_ENABLED,
        "live_action_scope": LIVE_ACTION_SCOPE,
        "scripts_dir_exists": SCRIPTS_DIR.exists(),
        "scripts_available": scripts_available,
        "actions": enabled_actions,
    }


# ── Run control plane ─────────────────────────────────────────────────────────
class RunRequest(BaseModel):
    action: str
    dry_run: bool = True
    confirmed: bool = False
    confirm_token: str = ""


@app.post("/api/run")
async def start_run(req: RunRequest, background_tasks: BackgroundTasks):
    global active_run

    if not LIVE_MODE_ENABLED:
        raise HTTPException(403, "Live mode is not enabled (LIVE_MODE_ENABLED=false)")

    if req.action not in ACTIONS:
        raise HTTPException(422, f"Unknown action: {req.action!r}")

    if not _action_enabled(req.action):
        raise HTTPException(403,
            f"Action '{req.action}' is not enabled in scope '{LIVE_ACTION_SCOPE}' "
            f"(requires scope: {ACTIONS[req.action]['scope']})")

    if active_run is not None:
        raise HTTPException(409,
            f"Another run is already active: {active_run.run_id} ({active_run.action}). "
            "Wait for it to complete or check /api/run/active.")

    action = ACTIONS[req.action]

    # Validate confirmation for destructive live runs
    if action["destructive"] and not req.dry_run:
        if not req.confirmed:
            raise HTTPException(422, "Destructive live actions require confirmed=true")
        expected = action.get("confirm_token")
        if expected and req.confirm_token != expected:
            raise HTTPException(422, f"Wrong confirm_token: expected '{expected}'")

    # Build command — whitelist-only, zero user input touches shell
    script_path = SCRIPTS_DIR / action["script"]
    if not script_path.exists():
        raise HTTPException(500, f"Script not found: {action['script']} (check SCRIPTS_DIR mount)")

    cmd: list[str] = ["bash", str(script_path), *action["args"]]
    if req.dry_run and action["dry_run_supported"]:
        cmd.append("--dry-run")
    elif not req.dry_run and action["destructive"]:
        cmd.extend(action["flags_live"])

    run_id = str(uuid.uuid4())
    state = RunState(
        run_id=run_id,
        action=req.action,
        dry_run=req.dry_run,
        started_at=_now(),
    )
    active_run = state
    run_registry[run_id] = state
    background_tasks.add_task(_execute_run, state, cmd)

    return {
        "run_id": run_id,
        "action": req.action,
        "label": action["label"],
        "dry_run": req.dry_run,
        "cmd_preview": f"bash {action['script']} {' '.join(cmd[2+len(action['args']):])}".strip(),
        "started_at": state.started_at,
    }


@app.get("/api/run/active")
async def get_active_run():
    if active_run is None:
        return None
    return {
        "run_id": active_run.run_id,
        "action": active_run.action,
        "label": ACTIONS[active_run.action]["label"],
        "dry_run": active_run.dry_run,
        "started_at": active_run.started_at,
        "status": active_run.status,
        "line_count": len(active_run.lines),
    }


@app.get("/api/run/{run_id}/status")
async def get_run_status(run_id: str):
    state = run_registry.get(run_id)
    if state is None:
        raise HTTPException(404, f"Run {run_id!r} not found")
    return {
        "run_id": run_id,
        "action": state.action,
        "label": ACTIONS[state.action]["label"],
        "dry_run": state.dry_run,
        "started_at": state.started_at,
        "finished_at": state.finished_at,
        "status": state.status,
        "exit_code": state.exit_code,
        "line_count": len(state.lines),
    }


@app.get("/api/run/{run_id}/stream")
async def stream_run(run_id: str):
    state = run_registry.get(run_id)
    if state is None:
        raise HTTPException(404, f"Run {run_id!r} not found (may have expired)")

    async def event_generator():
        sent = 0
        # Stream all buffered lines (run may already be done)
        while True:
            snapshot = list(state.lines)
            while sent < len(snapshot):
                payload = json.dumps({"line": snapshot[sent], "n": sent})
                yield f"data: {payload}\n\n"
                sent += 1
            if state.done.is_set():
                break
            await asyncio.sleep(0.15)

        # Final done event
        done_payload = json.dumps({
            "exit_code": state.exit_code,
            "status": state.status,
            "finished_at": state.finished_at,
            "line_count": sent,
        })
        yield f"event: done\ndata: {done_payload}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/api/runs")
async def list_runs():
    return list(reversed(run_history))


# ── Status ────────────────────────────────────────────────────────────────────
@app.get("/api/status")
async def get_status():
    app_health_json = None
    live_health = None

    if APP_HEALTH_URL:
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                r = await client.get(APP_HEALTH_URL)
                if r.status_code == 200:
                    live_health = r.json()
        except Exception:
            pass

    final_health_txt = read_ev(FULLSITE_DIR / "fsdb-final-app-health.txt")
    if final_health_txt:
        app_health_json = extract_json(final_health_txt)

    return {
        "as_of": "2026-03-16T15:00:00Z",
        "source": "live" if live_health else "evidence",
        "components": {
            "pg_primary": {
                "host": "10.0.96.11", "role": "primary", "status": "healthy",
                "keepalived": "MASTER", "vip": "10.0.96.10", "wg_handshake_s": 15,
                "wal_lsn": "0/B000358",
                "detail": "pg_is_in_recovery=f · Keepalived MASTER · VIP active",
            },
            "vm_pg_dr": {
                "host": "10.200.0.2", "role": "replica", "status": "healthy",
                "lag_bytes": 0,
                "detail": "pg_is_in_recovery=t · streaming 0 lag from pg-primary",
            },
            "app_onprem": {
                "host": "10.0.96.13:8080", "status": "healthy",
                "health": live_health or app_health_json,
                "source": "live" if live_health else "evidence",
                "detail": "docker-app-1 running · /health 200",
            },
            "pg_standby": {
                "host": "10.0.96.14", "role": "replica", "status": "healthy",
                "lag_bytes": 0,
                "detail": "pg_is_in_recovery=t · rebuilt S5-01 · streaming 0 lag",
            },
            "wireguard": {
                "status": "active", "endpoint": "20.216.128.32:51820",
                "handshake_s": 15, "rx_mib": 34.25, "tx_mib": 39.78,
                "detail": "Persistent keepalive 25s",
            },
        },
        "drill_summary": {
            "last_failover_date": "2026-03-16",
            "last_failover_verdict": "PASS",
            "last_failback_date": "2026-03-16",
            "last_failback_verdict": "PASS",
            "rpo_bytes": 0,
            "current_mode": "normal",
        },
    }


# ── Metrics ───────────────────────────────────────────────────────────────────
@app.get("/api/metrics")
async def get_metrics():
    return {
        "onprem_failover": {
            "rto_label": "<1s", "rto_sublabel": "VRRP · <5s app-confirmed",
            "rpo_label": "N/A", "date": "2026-03-14", "sprint": "S4-03", "verdict": "PASS",
        },
        "onprem_fallback": {
            "rto_label": "24s", "rto_sublabel": "Replication resumed automatically",
            "rpo_label": "0 bytes", "date": "2026-03-14", "sprint": "S4-03", "verdict": "PASS",
        },
        "fullsite_failover": {
            "rto_label": "32s", "rto_sublabel": "S5-01 automated · clean RTO (scripts_dr/)",
            "rpo_label": "0 bytes", "date": "2026-03-16", "sprint": "S5-01", "verdict": "PASS",
            "note": "Previous manual run: 48m 42s (SSH interruption). Automated: 32s.",
        },
        "fullsite_failback": {
            "rto_label": "103s", "rto_sublabel": "S5-01 automated · app RTO (service: 71s)",
            "rpo_label": "0 bytes", "date": "2026-03-16", "sprint": "S5-01", "verdict": "PASS",
            "note": "Service RTO 71s · App RTO 103s · Topology RTO 57s",
        },
        "evidence_files": 51,
        "commits": ["a386281", "217b7c6"],
    }


# ── Evidence ──────────────────────────────────────────────────────────────────
@app.get("/api/evidence")
async def list_evidence():
    files = []
    import time
    now_ts = time.time()
    for phase_dir, phase_label in [
        (ONPREM_DIR,   "on-prem-ha"),
        (FULLSITE_DIR, "full-site-dr"),
    ]:
        if not phase_dir.exists():
            continue
        for f in sorted(phase_dir.glob("*.txt")):
            stat = f.stat()
            files.append({
                "name": f.name,
                "phase": phase_label,
                "size_bytes": stat.st_size,
                "mtime": stat.st_mtime,
                "is_new": (now_ts - stat.st_mtime) < 300,  # modified in last 5 min
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
                "size_bytes": p.stat().st_size,
                "mtime": p.stat().st_mtime,
            }
    raise HTTPException(404, f"{filename} not found")


# ── Drills ────────────────────────────────────────────────────────────────────
DRILLS: dict = {
    "onprem-failover": {
        "id": "onprem-failover", "name": "On-Prem HA Failover",
        "date": "2026-03-14", "sprint": "S4-03", "verdict": "PASS",
        "rto": "<1s VRRP · <5s app-confirmed", "rpo": "N/A",
        "summary": "Keepalived VRRP moved VIP 10.0.96.10 from pg-primary to pg-standby in under 1 second. App continued serving reads via standby.",
        "steps": [
            {"id":"P-1","name":"Pre-check: replication streaming",         "file":"precheck-replication.txt",       "status":"PASS","detail":"pg-standby streaming async, near-zero lag"},
            {"id":"P-2","name":"Pre-check: app health baseline",           "file":"precheck-app-health.txt",        "status":"PASS","detail":"pg_is_in_recovery=false (primary active)"},
            {"id":"P-3","name":"Pre-check: Keepalived primary MASTER",     "file":"precheck-keepalived-primary.txt","status":"PASS","detail":"pg-primary MASTER, pg-standby BACKUP"},
            {"id":"P-4","name":"Pre-check: VIP on pg-primary",             "file":"precheck-vip.txt",               "status":"PASS","detail":"inet 10.0.96.10 on eth0 of pg-primary"},
            {"id":"F-1","name":"Failover triggered (stop keepalived)",     "file":"failover-start-timestamp.txt",   "status":"PASS","detail":"2026-03-14T15:33:50Z"},
            {"id":"F-2","name":"VIP moved to pg-standby",                  "file":"failover-vip-moved.txt",         "status":"PASS","detail":"inet 10.0.96.10 on eth0 of 10.0.96.14 (<1s)"},
            {"id":"F-3","name":"pg-standby Keepalived → MASTER",           "file":"failover-keepalived-standby.txt","status":"PASS","detail":"Entering MASTER STATE"},
            {"id":"F-4","name":"App confirms standby serving via VIP",     "file":"failover-app-health.txt",        "status":"PASS","detail":"pg_is_in_recovery=true at 15:49:13Z"},
            {"id":"F-5","name":"RTO timestamp captured",                   "file":"failover-rto-timestamp.txt",     "status":"PASS","detail":"RTO <1s VRRP, <5s app-confirmed"},
        ],
    },
    "onprem-fallback": {
        "id": "onprem-fallback", "name": "On-Prem HA Fallback",
        "date": "2026-03-14", "sprint": "S4-03", "verdict": "PASS",
        "rto": "24s total", "rpo": "0 bytes",
        "summary": "pg-primary restarted. Keepalived priority 100 > 90 returned VIP automatically. Streaming replication resumed without manual intervention.",
        "steps": [
            {"id":"B-1","name":"Started postgresql + keepalived on pg-primary","file":"fallback-start-timestamp.txt",   "status":"PASS","detail":"2026-03-14T15:52:15Z"},
            {"id":"B-2","name":"VIP returned to pg-primary (priority 100)",    "file":"fallback-vip-returned.txt",      "status":"PASS","detail":"inet 10.0.96.10 secondary on pg-primary eth0"},
            {"id":"B-3","name":"pg-standby returned to BACKUP",               "file":"fallback-keepalived-standby.txt", "status":"PASS","detail":"Keepalived BACKUP (lower priority)"},
            {"id":"B-4","name":"Replication resumed to pg-standby",           "file":"fallback-replication.txt",        "status":"PASS","detail":"Streaming async, write_lag ~11ms"},
            {"id":"B-5","name":"App confirms primary via VIP",                "file":"fallback-app-health.txt",         "status":"PASS","detail":"pg_is_in_recovery=false at 15:52:38Z"},
            {"id":"B-6","name":"Post-test full snapshot",                     "file":"posttest-final-snapshot.txt",     "status":"PASS","detail":"pg-primary MASTER, replication streaming, /health ok"},
        ],
    },
    "fullsite-failover": {
        "id": "fullsite-failover", "name": "Full-Site Failover → Azure",
        "date": "2026-03-16", "sprint": "S5-01", "verdict": "PASS",
        "rto": "32s (automated)", "rpo": "0 bytes",
        "summary": "Complete shutdown of on-prem services. Azure DR VM promoted to primary. Azure app started with --network host. All data preserved (0 bytes RPO). Automated via fullsite-failover.sh.",
        "steps": [
            {"id":"P-1","name":"Pre-check: primary state + replication",       "file":"fsdr-precheck-primary.txt",      "status":"PASS","detail":"Both replicas 0 lag, WG 5s handshake"},
            {"id":"P-2","name":"Pre-check: on-prem app healthy",               "file":"fsdr-precheck-app-health.txt",   "status":"PASS","detail":"pg_is_in_recovery=false"},
            {"id":"P-3","name":"Pre-check: DR VM ready (pg_is_in_recovery=t)", "file":"fsdr-precheck-drvm.txt",         "status":"PASS","detail":"Replica streaming, Docker image present"},
            {"id":"F-1","name":"Stop on-prem app (docker compose down)",       "file":"fsdr-app-stopped.txt",           "status":"PASS","detail":"14:41:13Z"},
            {"id":"F-2","name":"Capture final LSN (lag=0)",                    "file":"fsdr-final-lsn.txt",             "status":"PASS","detail":"bytes_lag=0 to DR VM"},
            {"id":"F-3","name":"Stop postgresql + keepalived on pg-primary",   "file":"fsdr-primary-stopped.txt",       "status":"PASS","detail":"Both inactive at 14:41:21Z"},
            {"id":"F-4","name":"Wait for DR VM replay to stabilise",           "file":"fsdr-replay-wait.txt",           "status":"PASS","detail":"replay_lsn stable"},
            {"id":"F-5","name":"Promote DR VM (pg_promote)",                   "file":"fsdr-promoted.txt",              "status":"PASS","detail":"pg_is_in_recovery=f, standby.signal absent"},
            {"id":"F-6","name":"Write test on Azure primary",                  "file":"fsdr-write-test.txt",            "status":"PASS","detail":"CREATE TABLE / INSERT 0 1 / DROP success"},
            {"id":"F-7","name":"Start Azure app (--network host)",             "file":"fsdr-app-health-drvm.txt",       "status":"PASS","detail":"pg_is_in_recovery=false, app_env=dr-azure"},
            {"id":"F-8","name":"External health confirmation",                 "file":"fsdr-app-health-local.txt",      "status":"PASS","detail":"/health 200 from WSL"},
            {"id":"F-9","name":"RTO/RPO summary captured",                     "file":"fsdr-rto-summary.txt",           "status":"PASS","detail":"RTO 32s, RPO 0 bytes"},
            {"id":"F-10","name":"Post-failover snapshot",                      "file":"fsdr-post-failover-snapshot.txt","status":"PASS","detail":"Azure app running, pg primary confirmed"},
        ],
    },
    "fullsite-failback": {
        "id": "fullsite-failback", "name": "Full-Site Failback → On-Prem",
        "date": "2026-03-16", "sprint": "S5-01", "verdict": "PASS",
        "rto": "103s app / 71s service",  "rpo": "0 bytes",
        "summary": "Azure app stopped. pg-primary rebuilt from DR VM backup, promoted. DR VM rebuilt as standby. VIP restored. On-prem app healthy. Automated via fullsite-fallback.sh.",
        "steps": [
            {"id":"B-P1","name":"Pre-check: DR VM primary, pg-primary inactive","file":"fsdb-precheck.txt",             "status":"PASS","detail":"WG 3s handshake, app-onprem stopped"},
            {"id":"B-1", "name":"Stop + remove Azure app container",           "file":"fsdb-azure-app-stopped.txt",     "status":"PASS","detail":"14:47:55Z"},
            {"id":"B-2", "name":"Set DR VM read-only (ALTER SYSTEM)",          "file":"fsdb-drvm-readonly.txt",         "status":"PASS","detail":"default_transaction_read_only=on"},
            {"id":"B-3", "name":"pg_basebackup on pg-primary from DR VM",      "file":"fsdb-pg-basebackup.txt",         "status":"PASS","detail":"30774 kB, standby.signal present"},
            {"id":"B-4", "name":"pg-primary starts as standby",               "file":"fsdb-primary-standby-start.txt", "status":"PASS","detail":"pg_is_in_recovery=t"},
            {"id":"B-5", "name":"DR VM replication to pg-primary confirmed",   "file":"fsdb-drvm-replication.txt",      "status":"PASS","detail":"10.200.0.1 streaming, 0 lag"},
            {"id":"B-6", "name":"Catch-up lag = 0 confirmed",                 "file":"fsdb-catchup-wait.txt",          "status":"PASS","detail":"0 bytes lag"},
            {"id":"B-7", "name":"Promote pg-primary (pg_promote)",             "file":"fsdb-primary-promoted.txt",      "status":"PASS","detail":"pg_promote()=t, pg_is_in_recovery=f"},
            {"id":"B-8", "name":"Rebuild DR VM as standby (pg_basebackup)",    "file":"fsdb-drvm-rebuild.txt",          "status":"PASS","detail":"pg_is_in_recovery=t after rebuild"},
            {"id":"B-9", "name":"Replication to DR VM restored",              "file":"fsdb-replication-restored.txt",  "status":"PASS","detail":"10.200.0.2 streaming, 0 lag"},
            {"id":"B-10","name":"VIP returned to pg-primary",                  "file":"fsdb-vip-returned.txt",          "status":"PASS","detail":"Keepalived MASTER, inet 10.0.96.10"},
            {"id":"B-11","name":"Start on-prem app (docker compose up)",       "file":"fsdb-app-started.txt",           "status":"PASS","detail":"docker-app-1 running"},
            {"id":"B-12","name":"App health confirmed",                        "file":"fsdb-app-health.txt",            "status":"PASS","detail":"pg_is_in_recovery=false, app_env=dev"},
            {"id":"B-13","name":"Failback RTO/RPO summary",                    "file":"fsdb-rto-summary.txt",           "status":"PASS","detail":"APP RTO 103s, service RTO 71s, RPO 0 bytes"},
            {"id":"B-14","name":"Post-failback system snapshot",               "file":"fsdb-post-failback-snapshot.txt","status":"PASS","detail":"pg-primary PRIMARY, DR VM streaming, app healthy"},
            {"id":"B-15","name":"Final app health (WSL confirmed)",            "file":"fsdb-final-app-health.txt",      "status":"PASS","detail":"pg_is_in_recovery=false, db_host=10.0.96.10"},
        ],
    },
}


@app.get("/api/drills")
async def list_drills():
    return [{k: v for k, v in d.items() if k != "steps"} for d in DRILLS.values()]


@app.get("/api/drills/{phase_id}")
async def get_drill(phase_id: str):
    if phase_id not in DRILLS:
        raise HTTPException(404, f"Phase '{phase_id}' not found")
    return DRILLS[phase_id]
