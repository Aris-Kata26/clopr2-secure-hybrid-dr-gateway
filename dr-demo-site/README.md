# CLOPR2 DR Demo Site

Local Dockerized demo website for the **Secure Hybrid DR Gateway (IaC Edition)** project.

## Quick start

```bash
# From repo root:
cd dr-demo-site

# Build and run (first time or after editing index.html)
docker compose up --build -d

# Then open in browser:
# http://localhost:8888
```

## Stop / cleanup

```bash
docker compose down
```

## Rebuild after editing site/index.html

```bash
docker compose up --build -d
```

## One-liner (no compose)

```bash
docker build -t clopr2-dr-demo dr-demo-site/ && \
docker run -d --name clopr2-dr-demo -p 8888:80 --rm clopr2-dr-demo
```

## Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Site | Static HTML/CSS | No build step, zero dependencies, instant start |
| Server | nginx:1.27-alpine | ~8 MB image, production-grade static serving |
| Port | 8888 | Avoids conflict with app (8080) and DR app (8000) |

## What the site covers

1. Executive summary — what was built and validated
2. Architecture overview — on-prem Proxmox, WireGuard VPN, Azure DR
3. DR drill timeline — 4 phases across 2 dates
4. Metrics — RTO/RPO for each drill
5. Live evidence — actual /health JSON from every phase
6. Final system state — post-failback snapshot table
7. Follow-up items — pg-standby rebuild, runbook note

## Files

```
dr-demo-site/
  Dockerfile          nginx:alpine + site/
  docker-compose.yml  port 8888
  README.md           this file
  site/
    index.html        complete single-page site (all CSS inline)
```
