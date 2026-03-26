# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **customized fork** of [lizhipay/acg-faka](https://github.com/lizhipay/acg-faka), a PHP-based virtual card shop system. The fork is maintained on the `nsfe` branch with local modifications, while `main` auto-syncs from upstream daily.

- **Tech stack**: PHP 8.2, custom MVC framework (no Laravel/Symfony), Smarty templating, Eloquent ORM (standalone), MySQL
- **Deployment**: Docker (Nginx + PHP-FPM), auto-deployed on `nsfe` push via GitHub Actions → webhook → `auto-deploy.sh`

## Branch Strategy

- `main`: mirrors upstream, auto-synced daily by `.github/workflows/upstream-sync.yml`
- `nsfe`: all local modifications; push triggers deployment via `.github/workflows/deploy-trigger.yml`

## Common Commands

```bash
# Docker
docker compose up -d --build       # Build and start
docker logs -f acg-faka            # View logs

# Deploy (server-side, called by webhook)
./auto-deploy.sh                   # Standard deploy (fast-forward merge)
./auto-deploy.sh --rebuild         # Force Docker rebuild
./auto-deploy.sh --force-pull      # Force override local changes

# Database config
cp config/database.php.example config/database.php   # Then edit with real credentials

# New environment init (ignore local-only files)
git update-index --assume-unchanged config/database.php
git update-index --assume-unchanged .htaccess
```

No automated test suite or linter exists in this project.

## Architecture

### Routing

URL pattern: `?s=/module/controller/action` with Nginx rewrite for clean URLs.
- Frontend: `/user/<controller>/<action>` → `app/Controller/User/`
- Admin: `/admin/<controller>/<action>` → `app/Controller/Admin/`
- Special rewrites: `/item/<id>`, `/cat/<id|recommend>`

### Application Code (`app/`)

| Directory | Purpose |
|-----------|---------|
| `Controller/Admin/` | Admin backend controllers (+ `Api/` subdirectory) |
| `Controller/User/` | Frontend controllers (+ `Api/` subdirectory) |
| `Model/` | Eloquent models (15 tables, prefixed `acg_`) |
| `Service/` | Business logic layer |
| `Interceptor/` | Request interceptors (e.g., `ManageSession.php` for admin JWT auth) |
| `Pay/` | Payment module system |
| `View/` | Smarty `.html` templates |
| `Util/` | Helper classes (HTTP, JWT, validation, etc.) |

### Framework Core (`kernel/`)

`kernel/Kernel.php` (~11.5K lines) is the monolithic framework core handling routing, DI, request lifecycle, and plugin loading. The kernel uses PHP 8 attributes for route and interceptor annotations.

- `kernel/Install/Install.sql` — full database schema (15 tables)
- `kernel/Plugin.php` — plugin system for extending functionality

### Key Config Files

| File | Purpose |
|------|---------|
| `config/database.php` | DB credentials (git-tracked but assume-unchanged, **never commit real values**) |
| `config/database.php.example` | DB config template (keep in sync when upstream changes `database.php`) |
| `config/app.php` | App version |
| `config/dependencies.php` | DI container bindings |
| `docker/nginx.conf` | Nginx config with rewrite rules and FastCGI |
| `docker/php.ini` | PHP runtime settings (timezone, upload limits, opcache) |

## Modification Workflow (Critical)

Every change to upstream project code **must** be recorded in `MODIFICATIONS.md` with:
- Type: `bug 修复` or `需求定制`
- File path
- Description (what and why)
- Upstream status: `未修复` / `已修复(可移除)` / `不适用`

New infrastructure files (scripts, configs, workflows) must be registered in the "基础设施文件" table in `MODIFICATIONS.md`.

## Upstream Sync

When upstream updates arrive (via daily sync to `main`):
1. Merge `origin/main` into `nsfe`
2. Check `MODIFICATIONS.md` entries against upstream changes
3. If upstream fixed a bug we patched, mark as `已修复(可移除)` and remove patch
4. If upstream changed `config/database.php`, sync changes to `config/database.php.example`
