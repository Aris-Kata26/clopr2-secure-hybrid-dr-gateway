import json
import logging
import os
import socket
import time
from datetime import datetime, timezone

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI, Response

load_dotenv()

APP_ENV = os.getenv("APP_ENV", "dev")
APP_VERSION = "0.3.0"
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


@app.get("/")
def root():
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
