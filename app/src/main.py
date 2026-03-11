import os
from datetime import datetime, timezone

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI, Response

load_dotenv()

APP_ENV = os.getenv("APP_ENV", "dev")
DB_HOST = os.getenv("DB_HOST", "10.0.96.10")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER", "appuser")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

DSN = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

app = FastAPI(title="clopr2-prototype-a", version="0.1.0")


@app.get("/")
def root():
    return {
        "app": "clopr2-prototype-a",
        "version": "0.1.0",
        "env": APP_ENV,
        "db_host": DB_HOST,
        "health": "/health",
    }


@app.get("/health")
def health(response: Response):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        with psycopg.connect(DSN, connect_timeout=5) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT pg_is_in_recovery()")
                recovery = cur.fetchone()[0]
        return {
            "status": "ok",
            "db": "ok",
            "db_host": DB_HOST,
            "pg_is_in_recovery": recovery,
            "app_env": APP_ENV,
            "ts": ts,
        }
    except Exception as exc:
        response.status_code = 503
        return {
            "status": "error",
            "db": "unreachable",
            "db_host": DB_HOST,
            "error": str(exc),
            "app_env": APP_ENV,
            "ts": ts,
        }
