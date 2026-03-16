# CLOPR2 DR Demo Platform v2

Local Dockerized dynamic demo for **Secure Hybrid DR Gateway (IaC Edition)**.

## Quick start

```bash
cd dr-demo-site
docker compose up --build -d
```

Open: **http://localhost:8888**

## Stop

```bash
docker compose down
```

## Rebuild after code changes

```bash
docker compose up --build -d
```

## What it includes

| Section | Content |
|---------|---------|
| Hero | Project title, badges, RTO/RPO stat row |
| Architecture | Animated SVG topology diagram — updates when you select a drill phase |
| Status | Current system state from evidence files (polls every 20s) |
| DR Drills | 4 phases: click any step to expand and read the actual evidence file |
| Metrics | RTO/RPO cards for all 4 drills |
| Evidence | /health proof cards + full file browser (63 evidence files) |
| Follow-up | pg-standby rebuild, runbook improvements, S4-09 complete |

## Architecture

```
frontend (nginx:1.27-alpine, port 8888)
  └── proxies /api/* → backend:8000
backend  (python:3.12-slim, internal)
  └── reads docs/05-evidence/** (mounted read-only)
```

No live SSH. No infrastructure commands. All data from committed evidence files.

## Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Frontend | React 18 + Vite 5 + Tailwind CSS 3 | Fast build, great DX |
| Animations | Framer Motion 11 | Smooth, composable |
| Backend | FastAPI + uvicorn | Already in project, async, simple |
| Serving | nginx:1.27-alpine | <8 MB, proxies /api to backend |
| Port | 8888 | Avoids app (8080) and DR app (8000) |

## Folder structure

```
dr-demo-site/
  backend/
    Dockerfile
    requirements.txt
    main.py             FastAPI: /api/status, /api/metrics, /api/drills, /api/evidence
  frontend/
    Dockerfile          node:20-alpine build -> nginx:1.27-alpine serve
    nginx.conf          SPA + /api proxy
    package.json
    vite.config.js
    tailwind.config.js
    src/
      App.jsx
      components/
        Nav.jsx
        Hero.jsx
        ArchDiagram.jsx       Animated SVG topology, updates per drill phase
        StatusDashboard.jsx   System component cards
        DrillPanel.jsx        Evidence-replay drill steps
        MetricsPanel.jsx      RTO/RPO cards
        EvidenceViewer.jsx    /health proof + file browser
        FollowUp.jsx          Maintenance items
  docker-compose.yml
  README.md
  site/                 (legacy static site, kept for reference)
```

## Safety model

The demo site has **no infrastructure execution capabilities**. It is read-only:
- All drill steps show evidence from committed files
- No SSH connections from the backend container
- No kubectl, az, terraform, or systemctl calls
- Evidence files are mounted read-only (`ro`)

For live status polling, set `APP_HEALTH_URL` in the environment to poll the on-prem
app health endpoint if it is reachable from the demo machine.
