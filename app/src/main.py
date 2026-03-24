import json
import logging
import os
import socket
import time
from datetime import datetime, timezone

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI, Response
from fastapi.responses import HTMLResponse

load_dotenv()

APP_ENV = os.getenv("APP_ENV", "dev")
APP_VERSION = "0.4.0"
DB_ENABLED = os.getenv("DB_ENABLED", "true").lower() == "true"
DB_HOST = os.getenv("DB_HOST", "10.0.96.10")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER", "appuser")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

DSN = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# ---------------------------------------------------------------------------
# Structured JSON logging
# ---------------------------------------------------------------------------

class _JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        base = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if hasattr(record, "extra"):
            base.update(record.extra)
        return json.dumps(base)


def _configure_logging() -> logging.Logger:
    handler = logging.StreamHandler()
    handler.setFormatter(_JSONFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    # Suppress uvicorn access logs — we emit our own per-request entries
    logging.getLogger("uvicorn.access").propagate = False
    return logging.getLogger("clopr2.app")


logger = _configure_logging()

# ---------------------------------------------------------------------------
# In-memory metrics counters
# ---------------------------------------------------------------------------

_START_TIME = time.monotonic()
_COUNTERS: dict[str, int] = {
    "health_checks_total": 0,
    "db_ok_total": 0,
    "db_error_total": 0,
    "db_disabled_total": 0,
    "readyz_total": 0,
}

# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------

app = FastAPI(title="clopr2-prototype-a", version=APP_VERSION)

logger.info(
    "App starting",
    extra={"extra": {"app_env": APP_ENV, "db_host": DB_HOST, "version": APP_VERSION}},
)


@app.get("/", response_class=HTMLResponse)
def root():
    return HTMLResponse(content=f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>CLOPR2 — Secure Hybrid DR Gateway</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
    body {{ font-family: 'Inter', sans-serif; }}
    .pulse-dot {{ animation: pulse 2s cubic-bezier(0.4,0,0.6,1) infinite; }}
    @keyframes pulse {{ 0%,100%{{opacity:1}} 50%{{opacity:.4}} }}
    .counter {{ font-variant-numeric: tabular-nums; }}
    .fade-in {{ animation: fadeIn 0.4s ease; }}
    @keyframes fadeIn {{ from{{opacity:0;transform:translateY(4px)}} to{{opacity:1;transform:translateY(0)}} }}
  </style>
</head>
<body class="bg-gray-950 text-gray-100 min-h-screen">

  <!-- Header -->
  <header class="border-b border-gray-800 bg-gray-900/60 backdrop-blur sticky top-0 z-10">
    <div class="max-w-5xl mx-auto px-6 py-4 flex items-center justify-between">
      <div class="flex items-center gap-3">
        <div class="w-8 h-8 rounded-lg bg-gradient-to-br from-blue-500 to-violet-600 flex items-center justify-center text-white font-bold text-sm">C2</div>
        <div>
          <div class="font-semibold text-white text-sm">CLOPR2</div>
          <div class="text-xs text-gray-400">Secure Hybrid DR Gateway</div>
        </div>
      </div>
      <div class="flex items-center gap-4">
        <span class="text-xs text-gray-500 counter" id="last-updated">—</span>
        <span class="inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 pulse-dot"></span>
          Live
        </span>
      </div>
    </div>
  </header>

  <main class="max-w-5xl mx-auto px-6 py-10 space-y-8">

    <!-- Hero row -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <div class="sm:col-span-2 rounded-2xl bg-gradient-to-br from-blue-600/20 to-violet-600/10 border border-blue-500/20 p-6">
        <div class="text-xs font-medium text-blue-400 uppercase tracking-widest mb-2">Application</div>
        <div class="text-2xl font-bold text-white mb-1">clopr2-prototype-a</div>
        <div class="flex items-center gap-3 text-sm text-gray-400">
          <span class="px-2 py-0.5 rounded bg-gray-800 text-gray-300 font-mono">v{APP_VERSION}</span>
          <span class="px-2 py-0.5 rounded bg-gray-800 text-gray-300">{APP_ENV}</span>
          <span class="px-2 py-0.5 rounded bg-gray-800 text-gray-300">BCLC24 / KATAR711</span>
        </div>
      </div>
      <div class="rounded-2xl bg-gray-900 border border-gray-800 p-6 flex flex-col justify-between">
        <div class="text-xs font-medium text-gray-500 uppercase tracking-widest mb-3">Uptime</div>
        <div class="text-3xl font-bold text-white counter" id="uptime">—</div>
        <div class="text-xs text-gray-500 mt-1">since last restart</div>
      </div>
    </div>

    <!-- Status cards -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <div class="rounded-2xl bg-gray-900 border border-gray-800 p-5">
        <div class="text-xs font-medium text-gray-500 uppercase tracking-widest mb-4">App Status</div>
        <div class="flex items-center gap-2">
          <span id="app-status-dot" class="w-2.5 h-2.5 rounded-full bg-gray-600"></span>
          <span id="app-status-text" class="text-lg font-semibold text-gray-300">—</span>
        </div>
        <div class="mt-3 text-xs text-gray-500" id="app-host">—</div>
      </div>
      <div class="rounded-2xl bg-gray-900 border border-gray-800 p-5">
        <div class="text-xs font-medium text-gray-500 uppercase tracking-widest mb-4">Database</div>
        <div class="flex items-center gap-2">
          <span id="db-status-dot" class="w-2.5 h-2.5 rounded-full bg-gray-600"></span>
          <span id="db-status-text" class="text-lg font-semibold text-gray-300">—</span>
        </div>
        <div class="mt-3 text-xs text-gray-500 font-mono" id="db-host">{DB_HOST}</div>
      </div>
      <div class="rounded-2xl bg-gray-900 border border-gray-800 p-5">
        <div class="text-xs font-medium text-gray-500 uppercase tracking-widest mb-4">DB Role</div>
        <div id="db-role" class="text-lg font-semibold text-gray-300">—</div>
        <div class="mt-3 text-xs text-gray-500" id="db-latency">—</div>
      </div>
    </div>

    <!-- Metrics -->
    <div>
      <div class="text-xs font-medium text-gray-500 uppercase tracking-widest mb-4">Metrics</div>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div class="rounded-xl bg-gray-900 border border-gray-800 p-4">
          <div class="text-2xl font-bold text-white counter" id="m-health">—</div>
          <div class="text-xs text-gray-500 mt-1">Health checks</div>
        </div>
        <div class="rounded-xl bg-gray-900 border border-gray-800 p-4">
          <div class="text-2xl font-bold text-emerald-400 counter" id="m-ok">—</div>
          <div class="text-xs text-gray-500 mt-1">DB OK</div>
        </div>
        <div class="rounded-xl bg-gray-900 border border-gray-800 p-4">
          <div class="text-2xl font-bold text-rose-400 counter" id="m-err">—</div>
          <div class="text-xs text-gray-500 mt-1">DB errors</div>
        </div>
        <div class="rounded-xl bg-gray-900 border border-gray-800 p-4">
          <div class="text-2xl font-bold text-sky-400 counter" id="m-readyz">—</div>
          <div class="text-xs text-gray-500 mt-1">Readyz calls</div>
        </div>
      </div>
    </div>

    <!-- Endpoints -->
    <div>
      <div class="text-xs font-medium text-gray-500 uppercase tracking-widest mb-4">Endpoints</div>
      <div class="rounded-2xl bg-gray-900 border border-gray-800 divide-y divide-gray-800">
        <a href="/health" class="flex items-center justify-between px-5 py-3.5 hover:bg-gray-800/50 transition group">
          <div class="flex items-center gap-3">
            <span class="text-xs font-mono px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">GET</span>
            <span class="text-sm font-mono text-gray-300">/health</span>
          </div>
          <span class="text-xs text-gray-600 group-hover:text-gray-400">DB connectivity check →</span>
        </a>
        <a href="/readyz" class="flex items-center justify-between px-5 py-3.5 hover:bg-gray-800/50 transition group">
          <div class="flex items-center gap-3">
            <span class="text-xs font-mono px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">GET</span>
            <span class="text-sm font-mono text-gray-300">/readyz</span>
          </div>
          <span class="text-xs text-gray-600 group-hover:text-gray-400">Liveness probe →</span>
        </a>
        <a href="/metrics" class="flex items-center justify-between px-5 py-3.5 hover:bg-gray-800/50 transition group">
          <div class="flex items-center gap-3">
            <span class="text-xs font-mono px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">GET</span>
            <span class="text-sm font-mono text-gray-300">/metrics</span>
          </div>
          <span class="text-xs text-gray-600 group-hover:text-gray-400">In-memory counters →</span>
        </a>
        <a href="/docs" class="flex items-center justify-between px-5 py-3.5 hover:bg-gray-800/50 transition group">
          <div class="flex items-center gap-3">
            <span class="text-xs font-mono px-2 py-0.5 rounded bg-violet-500/10 text-violet-400 border border-violet-500/20">UI</span>
            <span class="text-sm font-mono text-gray-300">/docs</span>
          </div>
          <span class="text-xs text-gray-600 group-hover:text-gray-400">Swagger UI →</span>
        </a>
      </div>
    </div>

  </main>

  <footer class="border-t border-gray-800 mt-12">
    <div class="max-w-5xl mx-auto px-6 py-5 flex items-center justify-between text-xs text-gray-600">
      <span>CLOPR2 · BCLC24 · KATAR711</span>
      <span>BTS Final Project — 2026</span>
    </div>
  </footer>

<script>
function fmtUptime(s) {{
  if (s < 60) return s + 's';
  if (s < 3600) return Math.floor(s/60) + 'm ' + (s%60) + 's';
  return Math.floor(s/3600) + 'h ' + Math.floor((s%3600)/60) + 'm';
}}

async function refresh() {{
  try {{
    const [h, m] = await Promise.all([
      fetch('/health').then(r=>r.json()),
      fetch('/metrics').then(r=>r.json()),
    ]);

    // App status
    const ok = h.status === 'ok';
    document.getElementById('app-status-dot').className =
      'w-2.5 h-2.5 rounded-full ' + (ok ? 'bg-emerald-400' : 'bg-rose-400');
    document.getElementById('app-status-text').textContent = ok ? 'Healthy' : 'Degraded';
    document.getElementById('app-status-text').className =
      'text-lg font-semibold ' + (ok ? 'text-emerald-400' : 'text-rose-400');

    // DB
    const db = h.db || '—';
    const dbOk = db === 'ok';
    const dbDis = db === 'disabled';
    document.getElementById('db-status-dot').className =
      'w-2.5 h-2.5 rounded-full ' + (dbOk ? 'bg-emerald-400' : dbDis ? 'bg-amber-400' : 'bg-rose-400');
    document.getElementById('db-status-text').textContent =
      dbOk ? 'Connected' : dbDis ? 'Disabled' : 'Unreachable';
    document.getElementById('db-status-text').className =
      'text-lg font-semibold ' + (dbOk ? 'text-emerald-400' : dbDis ? 'text-amber-400' : 'text-rose-400');

    // DB role
    const role = h.db_role || (dbDis ? 'N/A' : '—');
    document.getElementById('db-role').textContent = role;
    document.getElementById('db-role').className =
      'text-lg font-semibold ' + (role==='PRIMARY' ? 'text-blue-400' : role==='STANDBY' ? 'text-violet-400' : 'text-gray-400');
    document.getElementById('db-latency').textContent =
      h.latency_ms != null ? h.latency_ms + ' ms latency' : (dbDis ? 'DB_ENABLED=false' : '—');

    // App host
    document.getElementById('app-host').textContent = h.app_host ? 'Host: ' + h.app_host : '';

    // Metrics
    document.getElementById('uptime').textContent = fmtUptime(Math.floor(m.uptime_seconds));
    document.getElementById('m-health').textContent = m.health_checks_total;
    document.getElementById('m-ok').textContent = m.db_ok_total;
    document.getElementById('m-err').textContent = m.db_error_total;
    document.getElementById('m-readyz').textContent = m.readyz_total;

    document.getElementById('last-updated').textContent =
      'Updated ' + new Date().toLocaleTimeString();

  }} catch(e) {{
    document.getElementById('app-status-text').textContent = 'Unreachable';
  }}
}}

refresh();
setInterval(refresh, 5000);
</script>
</body>
</html>""")


@app.get("/api")
def api_root():
    return {
        "app": "clopr2-prototype-a",
        "version": APP_VERSION,
        "env": APP_ENV,
        "db_host": DB_HOST,
        "endpoints": {
            "health": "/health",
            "readyz": "/readyz",
            "metrics": "/metrics",
        },
    }


@app.get("/health")
def health(response: Response):
    """
    DB connectivity check.
    200 = DB reachable, pg_is_in_recovery reported.
    503 = DB unreachable.
    """
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    _COUNTERS["health_checks_total"] += 1

    if not DB_ENABLED:
        _COUNTERS["db_disabled_total"] += 1
        logger.info("health_check", extra={"extra": {"db": "disabled", "ts": ts}})
        return {
            "status": "ok",
            "db": "disabled",
            "app_env": APP_ENV,
            "ts": ts,
        }

    app_host = socket.gethostname()
    t0 = time.perf_counter()

    try:
        with psycopg.connect(DSN, connect_timeout=5) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT pg_is_in_recovery()")
                recovery = cur.fetchone()[0]
        latency_ms = round((time.perf_counter() - t0) * 1000, 1)
        db_role = "PRIMARY" if not recovery else "STANDBY"
        _COUNTERS["db_ok_total"] += 1
        logger.info(
            "health_check",
            extra={"extra": {
                "db": "ok",
                "db_host": DB_HOST,
                "db_role": db_role,
                "pg_is_in_recovery": recovery,
                "latency_ms": latency_ms,
                "ts": ts,
            }},
        )
        return {
            "status": "ok",
            "db": "ok",
            "db_host": DB_HOST,
            "db_role": db_role,
            "pg_is_in_recovery": recovery,
            "latency_ms": latency_ms,
            "app_host": app_host,
            "app_env": APP_ENV,
            "ts": ts,
        }
    except Exception as exc:
        latency_ms = round((time.perf_counter() - t0) * 1000, 1)
        _COUNTERS["db_error_total"] += 1
        response.status_code = 503
        logger.warning(
            "health_check",
            extra={"extra": {
                "db": "unreachable",
                "db_host": DB_HOST,
                "db_role": "UNREACHABLE",
                "latency_ms": latency_ms,
                "error": str(exc),
                "ts": ts,
            }},
        )
        return {
            "status": "error",
            "db": "unreachable",
            "db_host": DB_HOST,
            "db_role": "UNREACHABLE",
            "latency_ms": latency_ms,
            "app_host": app_host,
            "error": str(exc),
            "app_env": APP_ENV,
            "ts": ts,
        }


@app.get("/readyz")
def readyz():
    """
    Liveness check — confirms the app process is alive and the event loop
    is responsive. Does NOT check the database.
    Always returns 200.
    """
    _COUNTERS["readyz_total"] += 1
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    logger.info("readyz", extra={"extra": {"ts": ts}})
    return {"status": "ready", "ts": ts}


@app.get("/metrics")
def metrics():
    """
    In-memory counters since last container start.
    No Prometheus dependency — plain JSON.
    """
    uptime = round(time.monotonic() - _START_TIME, 1)
    return {
        "uptime_seconds": uptime,
        **_COUNTERS,
        "app_env": APP_ENV,
        "version": APP_VERSION,
    }
