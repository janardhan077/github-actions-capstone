# 🎬 BookMyShow Clone — Docker Deployment Guide

> **From the Development Team → DevOps / Infrastructure Team**
>
> This document covers everything you need to deploy, configure, and operate the BookMyShow Clone application. Please read it end-to-end before touching any environment.

---

## 📋 Table of Contents

1. [Application Overview](#1-application-overview)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Technology Stack](#3-technology-stack)
4. [Repository Structure](#4-repository-structure)
5. [Prerequisites](#5-prerequisites)
6. [Quick Start (Local / Dev)](#6-quick-start-local--dev)
7. [Production Deployment](#7-production-deployment)
8. [Environment Variables Reference](#8-environment-variables-reference)
9. [Docker Images & Build Details](#9-docker-images--build-details)
10. [Networking & Ports](#10-networking--ports)
11. [Database](#11-database)
12. [Redis Cache](#12-redis-cache)
13. [Health Checks](#13-health-checks)
14. [Logs](#14-logs)
15. [Scaling](#15-scaling)
16. [Useful Docker Commands](#16-useful-docker-commands)
17. [Troubleshooting](#17-troubleshooting)
18. [Security Checklist](#18-security-checklist)
19. [CI/CD Integration Notes](#19-cicd-integration-notes)
20. [Contact](#20-contact)

---

## 1. Application Overview

BookMyShow Clone is a full-stack movie ticket booking application with:

- **Frontend** — Plain HTML/CSS/JS served by Nginx (no build step needed)
- **Backend** — Node.js + Express REST API
- **Database** — PostgreSQL 15 (schema auto-initialized on first boot)
- **Cache** — Redis 7 (caches movie listings; TTL 5 min)
- **Reverse Proxy** — Nginx (single entry point; routes `/api/*` to backend, everything else to frontend)

**Key User Flows:**
1. Browse movies → Select a show time → Pick seats → Enter details → Booking confirmed

---

## 2. Architecture Diagram

```
                        ┌─────────────────────────────────────┐
                        │          Docker Network              │
                        │           (bms_network)              │
                        │                                      │
  Browser / Client      │  ┌──────────┐    ┌────────────────┐ │
       │                │  │  nginx   │    │    frontend    │ │
       │  port 80 ──────┼──▶  (proxy) ├────▶  (nginx:80)   │ │
       │                │  │          │    │  static HTML   │ │
       │                │  └────┬─────┘    └────────────────┘ │
       │                │       │                              │
       │                │       │ /api/*                       │
       │                │  ┌────▼─────┐    ┌────────────────┐ │
       │                │  │ backend  │    │   postgres     │ │
       │                │  │ (node.js)├────▶  (port 5432)  │ │
       │                │  │ :5000    │    │                │ │
       │                │  │          │    └────────────────┘ │
       │                │  │          │    ┌────────────────┐ │
       │                │  │          ├────▶    redis       │ │
       │                │  └──────────┘    │  (port 6379)  │ │
       │                │                  └────────────────┘ │
       │                └─────────────────────────────────────┘
       │
  Only port 80 (nginx) is exposed to the host machine.
  All other services communicate only within bms_network.
```

---

## 3. Technology Stack

| Layer         | Technology            | Version     | Image                  |
|---------------|-----------------------|-------------|------------------------|
| Reverse Proxy | Nginx                 | 1.25        | `nginx:1.25-alpine`    |
| Frontend      | HTML/CSS/JS + Nginx   | —           | `nginx:1.25-alpine`    |
| Backend       | Node.js + Express     | Node 20 LTS | `node:20-alpine`       |
| Database      | PostgreSQL            | 15          | `postgres:15-alpine`   |
| Cache         | Redis                 | 7           | `redis:7-alpine`       |

> All base images use **Alpine Linux** for minimal attack surface and image size.

---

## 4. Repository Structure

```
bookmyshow-docker/
├── docker-compose.yml          ← Production compose file
├── docker-compose.dev.yml      ← Dev overrides (hot-reload, exposed ports)
├── .env.example                ← Template — copy to .env
├── .gitignore
│
├── backend/
│   ├── Dockerfile              ← Multi-stage: deps / development / production
│   ├── .dockerignore
│   ├── package.json
│   └── server.js               ← Express API (single file for simplicity)
│
├── frontend/
│   ├── Dockerfile
│   ├── nginx.conf              ← Frontend nginx: serves HTML, proxies /api/*
│   └── index.html              ← Entire frontend SPA
│
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf              ← Top-level reverse proxy config
│
└── postgres/
    └── init.sql                ← Schema + seed data (runs once on first boot)
```

---

## 5. Prerequisites

Install these on the **deployment machine** before proceeding:

| Tool           | Minimum Version | Install Guide                                      |
|----------------|-----------------|---------------------------------------------------|
| Docker Engine  | 24.x            | https://docs.docker.com/engine/install/           |
| Docker Compose | v2.x (plugin)   | https://docs.docker.com/compose/install/          |
| Git            | any             | https://git-scm.com/                              |

Verify:
```bash
docker --version          # Docker version 24.x.x
docker compose version    # Docker Compose version v2.x.x
```

> ⚠️ **Important:** Use `docker compose` (v2 plugin) — NOT the legacy `docker-compose` (v1 standalone). They behave differently.

---

## 6. Quick Start (Local / Dev)

### Step 1 — Clone the repo
```bash
git clone https://github.com/your-org/bookmyshow-docker.git
cd bookmyshow-docker
```

### Step 2 — Set up environment
```bash
cp .env.example .env
# Edit .env if needed — defaults work for local dev
```

### Step 3 — Start in development mode
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

### Step 4 — Access the app
| Service           | URL                          |
|-------------------|------------------------------|
| Full App (nginx)  | http://localhost:8080        |
| Frontend direct   | http://localhost:3000        |
| API direct        | http://localhost:5000/api    |
| API Health check  | http://localhost:5000/api/health |

### Dev Mode extras
- **Backend hot-reload** is enabled via nodemon + bind mount
- **PostgreSQL** exposed on `localhost:5432` (connect with DBeaver, pgAdmin, etc.)
- **Redis** exposed on `localhost:6379` (connect with RedisInsight or `redis-cli`)

---

## 7. Production Deployment

### Step 1 — Clone & configure
```bash
git clone https://github.com/your-org/bookmyshow-docker.git
cd bookmyshow-docker
cp .env.example .env
nano .env    # Set strong passwords (see Section 8)
```

### Step 2 — Build images
```bash
docker compose build --no-cache
```

### Step 3 — Start services (detached)
```bash
docker compose up -d
```

### Step 4 — Verify all containers are healthy
```bash
docker compose ps
```
Expected output:
```
NAME           STATUS                   PORTS
bms_nginx      Up (healthy)             0.0.0.0:80->80/tcp
bms_frontend   Up (healthy)
bms_backend    Up (healthy)
bms_postgres   Up (healthy)
bms_redis      Up (healthy)
```

> 🕐 On first boot, PostgreSQL runs `init.sql` to create schema and seed data.
> This takes ~30 seconds. The backend's `depends_on: condition: service_healthy`
> ensures it waits for Postgres to be ready before starting.

### Step 5 — Access the app
```
http://YOUR_SERVER_IP
```

### Stopping
```bash
docker compose down          # Stop containers (preserves volumes)
docker compose down -v       # ⚠️  Also deletes all data volumes
```

---

## 8. Environment Variables Reference

Copy `.env.example` → `.env` and set these:

| Variable            | Default        | Required | Description                                      |
|---------------------|----------------|----------|--------------------------------------------------|
| `APP_PORT`          | `80`           | No       | Host port mapped to nginx                        |
| `FRONTEND_URL`      | `http://localhost` | No  | CORS allowed origin for the backend              |
| `POSTGRES_DB`       | `bookmyshow`   | Yes      | PostgreSQL database name                         |
| `POSTGRES_USER`     | `admin`        | Yes      | PostgreSQL username                              |
| `POSTGRES_PASSWORD` | `admin123`     | **Yes**  | **CHANGE THIS in production**                   |
| `NODE_ENV`          | `production`   | No       | Node.js environment                              |

> **Security rule:** Never commit `.env` to Git. It is already in `.gitignore`.

---

## 9. Docker Images & Build Details

### Backend — Multi-stage Dockerfile

The backend uses a **3-stage Dockerfile**:

| Stage         | Purpose                                          |
|---------------|--------------------------------------------------|
| `deps`        | Install only `--production` npm deps (no devDeps)|
| `development` | Install all deps + nodemon (used in dev compose) |
| `production`  | Copy deps from `deps` stage; run as non-root user|

**Non-root user:** The production backend container runs as `nodeuser` (UID 1001), not root.

### Image sizes (approximate)
| Service  | Base Image           | Approx Size |
|----------|----------------------|-------------|
| backend  | node:20-alpine       | ~180 MB     |
| frontend | nginx:1.25-alpine    | ~25 MB      |
| nginx    | nginx:1.25-alpine    | ~25 MB      |
| postgres | postgres:15-alpine   | ~230 MB     |
| redis    | redis:7-alpine       | ~35 MB      |

---

## 10. Networking & Ports

### Host-exposed ports (configurable via `.env`)

| Port | Service | Notes                              |
|------|---------|-------------------------------------|
| `80` | nginx   | Only public entry point             |

### Internal Docker network ports (not exposed)

| Service  | Internal Port | Accessible by         |
|----------|---------------|-----------------------|
| backend  | 5000          | nginx, frontend       |
| frontend | 80            | nginx                 |
| postgres | 5432          | backend only          |
| redis    | 6379          | backend only          |

> ✅ **Security by design:** Database and cache are never exposed to the host in production.

**Dev overrides** (via `docker-compose.dev.yml`):
- `postgres:5432` → exposed as `localhost:5432`
- `redis:6379` → exposed as `localhost:6379`
- `backend:5000` → exposed as `localhost:5000`
- `frontend:80` → exposed as `localhost:3000`
- `nginx:80` → exposed as `localhost:8080`

---

## 11. Database

### PostgreSQL — Key facts
- **Image:** `postgres:15-alpine`
- **Data persistence:** Docker named volume `postgres_data`
- **Init script:** `./postgres/init.sql` — runs **only once** on first container creation
- **Schema includes:** `movies`, `theatres`, `screenings`, `seats`, `bookings` tables
- **Seed data:** 8 movies, 6 theatres, screenings for 3 days, seats auto-generated

### Connecting manually (from host, dev only)
```bash
docker exec -it bms_postgres psql -U admin -d bookmyshow
```

### Backup
```bash
docker exec bms_postgres pg_dump -U admin bookmyshow > backup_$(date +%Y%m%d).sql
```

### Restore
```bash
docker exec -i bms_postgres psql -U admin bookmyshow < backup_20240101.sql
```

### Re-initialize (wipe & reseed) — DESTRUCTIVE
```bash
docker compose down -v          # Deletes postgres_data volume
docker compose up -d            # init.sql runs fresh on next boot
```

---

## 12. Redis Cache

- **Image:** `redis:7-alpine`
- **Persistence:** AOF enabled (`--appendonly yes`) → `redis_data` volume
- **Max memory:** 256 MB with `allkeys-lru` eviction policy
- **Cache TTL:** Movies list cached for **5 minutes** (300 seconds)
- **Keys:** `movies:all`, `movie:<id>` — invalidated on new booking

### Inspect cache (dev)
```bash
redis-cli -h localhost -p 6379
> KEYS *
> GET movies:all
> TTL movies:all
```

---

## 13. Health Checks

Every service has a Docker healthcheck. The backend waits for postgres + redis to be **healthy** before starting (using `depends_on: condition: service_healthy`).

| Service  | Check Command                             | Interval | Retries |
|----------|-------------------------------------------|----------|---------|
| postgres | `pg_isready -U admin -d bookmyshow`       | 10s      | 5       |
| redis    | `redis-cli ping`                          | 10s      | 5       |
| backend  | `wget -qO- http://localhost:5000/api/health` | 30s   | 3       |
| frontend | `wget -qO- http://localhost:80/`          | 30s      | 3       |
| nginx    | `wget -qO- http://localhost/nginx-health` | 30s      | 3       |

### Check health status
```bash
docker compose ps                    # shows health column
docker inspect bms_backend | grep -A5 '"Health"'
```

### API health endpoint response
```json
GET /api/health
{
  "status": "ok",
  "database": "connected",
  "cache": "connected",
  "timestamp": "2024-12-01T10:00:00.000Z"
}
```

---

## 14. Logs

### View logs (live)
```bash
docker compose logs -f               # All services
docker compose logs -f backend       # Backend only
docker compose logs -f postgres      # Postgres only
```

### Last N lines
```bash
docker compose logs --tail=100 backend
```

### Log storage
By default, Docker uses the `json-file` log driver. Logs are stored at:
```
/var/lib/docker/containers/<container-id>/<container-id>-json.log
```

### Production log rotation (add to `/etc/docker/daemon.json`)
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
```
Restart Docker after changing: `sudo systemctl restart docker`

---

## 15. Scaling

### Scale backend horizontally (multiple API instances)
```bash
docker compose up -d --scale backend=3
```
> ⚠️ If you scale backend, update the nginx `upstream` block to use load balancing.
> The current nginx config uses `server backend:5000` which Docker DNS round-robins automatically for multiple replicas.

### What **cannot** be scaled with the current setup
- PostgreSQL (single primary) — use managed DB (RDS, Supabase) for HA
- Redis (single node) — use Redis Cluster or ElastiCache for HA

---

## 16. Useful Docker Commands

```bash
# ── Start/Stop ─────────────────────────────────────────────────────────────
docker compose up -d                        # Start all (detached)
docker compose up -d --build                # Rebuild images then start
docker compose down                         # Stop all (keep volumes)
docker compose down -v                      # Stop all + delete volumes ⚠️
docker compose restart backend              # Restart one service

# ── Status ─────────────────────────────────────────────────────────────────
docker compose ps                           # Container status + ports
docker stats                                # Real-time CPU/RAM usage
docker system df                            # Disk usage by Docker objects

# ── Exec into containers ───────────────────────────────────────────────────
docker exec -it bms_backend sh              # Shell into backend
docker exec -it bms_postgres psql -U admin -d bookmyshow  # psql
docker exec -it bms_redis redis-cli         # redis-cli

# ── Images ─────────────────────────────────────────────────────────────────
docker compose build --no-cache             # Full rebuild (no cache)
docker image ls | grep bms                  # List project images
docker image prune -f                       # Remove dangling images

# ── Cleanup ────────────────────────────────────────────────────────────────
docker system prune -f                      # Remove stopped containers + dangling images
docker system prune -af                     # ⚠️ Remove ALL unused images too
docker volume ls | grep bms                 # List project volumes
```

---

## 17. Troubleshooting

### ❌ Backend fails with "Connection refused" to postgres

**Cause:** Backend started before Postgres was ready.
**Fix:** The `depends_on: condition: service_healthy` should handle this. If it doesn't:
```bash
docker compose restart backend
```
Or check Postgres logs: `docker compose logs postgres`

---

### ❌ `init.sql` didn't run / tables are missing

**Cause:** `init.sql` runs only on the **first** boot. If the volume already exists, it skips.
**Fix:**
```bash
docker compose down -v       # Delete postgres_data volume
docker compose up -d         # Recreate: init.sql will run
```

---

### ❌ Port 80 already in use

**Cause:** Another web server (Apache, another nginx) is running on port 80.
**Fix:**
```bash
sudo lsof -i :80             # Find what's using port 80
# Then change APP_PORT in .env:
APP_PORT=8080
docker compose up -d
```

---

### ❌ Redis "LOADING" error

**Cause:** Redis is loading AOF file on restart (especially with large datasets).
**Wait:** It resolves on its own in seconds. Or check:
```bash
docker compose logs redis
```

---

### ❌ "No space left on device" during build

**Fix:**
```bash
docker system prune -af      # Free up disk space
docker volume prune -f       # Remove unused volumes
```

---

### ❌ Frontend shows "Cannot reach API"

Check:
1. Is backend healthy? → `docker compose ps`
2. Is nginx routing `/api/` correctly? → `docker compose logs nginx`
3. CORS issue? → Check `FRONTEND_URL` in `.env` matches actual URL

---

## 18. Security Checklist

Before going to production, verify:

- [ ] `POSTGRES_PASSWORD` changed from `admin123` to a strong password (16+ chars)
- [ ] `.env` file is **not** committed to Git (check `.gitignore`)
- [ ] Postgres and Redis ports are **not** exposed in `docker-compose.yml` (they aren't by default)
- [ ] Server firewall allows only port 80 (and 443 if TLS) from the internet
- [ ] Docker is not running as root on the host (use rootless Docker or proper group)
- [ ] Log rotation is configured (see Section 14)
- [ ] Automatic security updates are enabled on the host OS
- [ ] For HTTPS: put Nginx behind a TLS terminator (Certbot + Let's Encrypt recommended) or use a load balancer with TLS

---

## 19. CI/CD Integration Notes

### GitHub Actions example snippet
```yaml
- name: Build and push images
  run: |
    docker compose build --no-cache
    docker compose push          # if using a registry

- name: Deploy
  run: |
    ssh deploy@$SERVER "
      cd /opt/bookmyshow &&
      git pull &&
      docker compose pull &&
      docker compose up -d --remove-orphans
    "
```

### Rolling update (zero-downtime)
```bash
# Build new image
docker compose build backend

# Recreate only backend (nginx keeps serving frontend during restart)
docker compose up -d --no-deps backend
```

### Image tagging for registry
```bash
docker tag bookmyshow-docker-backend:latest your-registry/bms-backend:v1.2.3
docker push your-registry/bms-backend:v1.2.3
```

---

## 20. Contact

| Role              | Contact                        |
|-------------------|--------------------------------|
| Backend Dev       | backend-team@yourcompany.com   |
| Frontend Dev      | frontend-team@yourcompany.com  |
| DevOps Lead       | devops@yourcompany.com         |
| On-call (PagerDuty)| #ops-alerts Slack channel     |

> **For urgent production issues:** Ping `@devops-oncall` in Slack `#incidents`

---

*Document version: 1.0.0 | Last updated by dev team: 2024-12 | Please keep this doc in sync when making architectural changes.*
