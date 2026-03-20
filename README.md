<h1 align="center">🛒 Magento_DeployKit</h1>

<p align="center">
  <b>Production-grade Magento 2 deployment automation on Debian 12</b><br>
  <i>7 sequential shell scripts — from a bare server to a fully operational Magento 2 stack with caching, search, SSL, and database management.</i>
  <br><br>
  <img src="https://img.shields.io/badge/Debian-12-A81D33?logo=debian&logoColor=white" alt="Debian" />
  <img src="https://img.shields.io/badge/PHP-8.2--FPM-777BB4?logo=php&logoColor=white" alt="PHP" />
  <img src="https://img.shields.io/badge/MySQL-8.0-4479A1?logo=mysql&logoColor=white" alt="MySQL" />
  <img src="https://img.shields.io/badge/Nginx-latest-009639?logo=nginx&logoColor=white" alt="Nginx" />
  <img src="https://img.shields.io/badge/Elasticsearch-7.x-005571?logo=elasticsearch&logoColor=white" alt="Elasticsearch" />
  <img src="https://img.shields.io/badge/Redis-latest-DC382D?logo=redis&logoColor=white" alt="Redis" />
  <img src="https://img.shields.io/badge/Varnish-7.x-4B9CD3" alt="Varnish" />
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License" />
</p>

---

## What This Demonstrates

This project goes beyond "install a CMS." It's an exercise in **production infrastructure engineering** — making deliberate choices across every layer of a complex, multi-service stack:

- **Automation discipline** — Idempotent, ordered shell scripts with hardened defaults, not ad-hoc commands
- **Multi-layer caching strategy** — Varnish for full-page cache, Redis for sessions and object cache, Magento's internal cache types
- **Separation of concerns** — Varnish fronts HTTP on port 80, NGINX handles SSL termination on 443, PHP-FPM runs in a dedicated pool under the web user
- **Security baseline** — Dedicated MySQL user per privilege level (app user, read-only user), process limits, permission hardening
- **Operational readiness** — Health checks, log paths, and diagnostic commands documented and built into the final script

---

## The Engineering Problem

Magento 2 is one of the most infrastructure-demanding open-source platforms: it requires a specific PHP version with ~15 extensions, a compatible Elasticsearch version (Magento 2.4.x dropped MySQL search entirely), Redis for sessions to survive PHP-FPM restarts, and a full-page cache layer to be remotely usable under load.

A manual install takes 4–6 hours and produces a result that's hard to reproduce. This project reduces that to a single sequential run with predictable outcomes.

---

## Architecture & Design Decisions

![Architecture Diagram](docs/architecture-diagram.svg)

```
Browser
  │
  ├─[HTTP :80]──→ Varnish (full-page cache)
  │                    └─[cache miss]──→ NGINX :8080 ──→ PHP-FPM ──→ Magento 2
  │
  └─[HTTPS :443]─→ NGINX (SSL termination) ──→ PHP-FPM ──→ Magento 2
                                                    ├──→ MySQL 8     (persistent data)
                                                    ├──→ Elasticsearch 7  (catalog search)
                                                    ├──→ Redis       (sessions + object cache)
                                                    └──→ Filesystem  (static assets)
```

### Why this topology?

| Decision | Rationale |
|---|---|
| **Varnish on port 80, NGINX on 8080** | Varnish cannot handle TLS; NGINX terminates SSL on 443 separately. Port 8080 is the backend Varnish proxies to on cache miss — keeping the two concerns cleanly separated. |
| **Dedicated PHP-FPM pool** | Running a named pool (not the default `www`) under the web user's UID means socket permissions align without chmod hacks, and process limits are scoped to Magento specifically. |
| **Elasticsearch over MySQL search** | Magento 2.4+ dropped built-in MySQL catalog search. Elasticsearch 7.x is the minimum supported version and gives proper tokenization, relevance scoring, and scalability. |
| **Redis for sessions, not files** | PHP file sessions don't survive PHP-FPM process recycling gracefully. Redis provides atomic session writes and survives restarts without user-facing cart loss. |
| **2 GB swap on 4 GB RAM** | Composer and Magento's DI compilation (`setup:di:compile`) are memory spikes, not sustained usage. Swap prevents OOM kills during install without requiring a larger droplet. |

### Stack

| Layer | Component | Version | Role |
|---|---|---|---|
| Edge / Cache | Varnish | 7.x | Full-page cache, port 80 |
| TLS | NGINX + OpenSSL | — | SSL termination, port 443 |
| Web Server | NGINX | latest | Reverse proxy, port 8080 |
| App Runtime | PHP-FPM | 8.2 | Magento app, FastCGI socket |
| Application | Magento 2 | 2.4.8-p2 | eCommerce core |
| Database | MySQL | 8.0 | Primary datastore, port 3306 |
| Search | Elasticsearch | 7.x | Catalog search, port 9200 |
| Cache / Sessions | Redis | latest | In-memory cache, port 6379 |
| DB Admin | phpMyAdmin | latest | Browser-based DB management |
| Hosting | DigitalOcean | Debian 12 | 2 vCPU / 4 GB / 80 GB BLR1 |

---

## Performance

Varnish full-page cache impact, measured on a catalog search result page:

| | Cold Cache (first request) | Warm Cache (subsequent) |
|---|---|---|
| **Data transferred** | 3.0 MB | 77.4 kB |
| **Time to finish** | 1.60s | 910ms |
| **Reduction** | — | **~97% less data transferred** |

![Search Results — Cold Cache](docs/screenshots/05-search-uncached-devtools.png)
*Cold cache — full PHP/MySQL/ES round trip: 3.0 MB, 1.60s*

![Search Results — Warm Cache](docs/screenshots/06-search-cached-devtools.png)
*Warm cache — served from Varnish memory: 77.4 kB, 910ms*

---

## Screenshots

### Storefront

![Storefront Homepage](docs/screenshots/01-storefront-homepage.png)
*Default Luma theme, served over HTTPS via Nginx + Varnish*

![Elasticsearch Search Results](docs/screenshots/02-storefront-search-results.png)
*Product search powered by Elasticsearch 7 — query "watch" against the catalog index*

### Admin Panel

![Admin Login](docs/screenshots/03-magento-admin-login.png)
*Admin at `https://test.mgt.com/admin` — self-signed SSL*

![Cache Management](docs/screenshots/04-admin-cache-management.png)
*All 15 cache types enabled; FPC active and backed by Varnish*

### Infrastructure

![phpMyAdmin](docs/screenshots/07-phpmyadmin-login.png)
*phpMyAdmin at `https://pma.mgt.com` — separate subdomain, same Nginx/PHP-FPM stack*

![DigitalOcean Droplet](docs/screenshots/08-digitalocean-droplet.png)
*2 vCPU / 4 GB RAM / 80 GB — DigitalOcean BLR1 (Bangalore)*

### Live HTTPS URLs

| URL | Description |
|---|---|
| `https://test.mgt.com` | Magento storefront — self-signed SSL |
| `https://test.mgt.com/catalogsearch/result/?q=watch` | Elasticsearch-powered search |
| `https://pma.mgt.com` | phpMyAdmin — separate subdomain |

![Storefront HTTPS](docs/screenshots/09-storefront-https-url.png)
![Search HTTPS](docs/screenshots/10-search-https-url.png)
![phpMyAdmin HTTPS](docs/screenshots/11-pma-https-url.png)

---

## Project Structure

```
Magento_DeployKit/
├── 01-System-Prep.sh                       # Swap, process limits, GPG keys, base packages
├── 02-PHP-MySQL-Installation.sh            # PHP 8.2, Composer, MySQL 8 setup
├── 03-NGINX-Composer-Setup.sh              # NGINX install, Composer auth for Magento repo
├── 04-Elasticsearch-Redis-Installation.sh  # Elasticsearch 7.x + Redis
├── 05-Magento-Installation.sh              # setup:install, static deploy, reindex
├── 06-Web-Server-Config.sh                 # PHP-FPM pool, NGINX sites, SSL, Varnish
├── 07-Final-Config-Checks.sh               # Permissions, Magento config, health checks
├── docs/
│   ├── architecture-diagram.svg
│   ├── common-errors.md
│   └── screenshots/
└── nginx/
    └── test.mgt.com.conf
```

---

## Quick Start

### Prerequisites

- Fresh **Debian 12** server (2 vCPU / 4 GB RAM minimum)
- Root or sudo access
- [Magento Marketplace](https://commercemarketplace.adobe.com/) account with Composer keys

### 1. Clone

```bash
git clone https://github.com/Asit0007/Magento_DeployKit.git
cd Magento_DeployKit
chmod +x *.sh
```

### 2. Set Composer credentials

```bash
export MAGENTO_COMPOSER_PUBLIC="your_public_key"
export MAGENTO_COMPOSER_PRIVATE="your_private_key"
```

### 3. Configure variables (top of each script)

```bash
MAGENTO_DOMAIN="test.mgt.com"
MYSQL_ROOT_PASS="your-secure-password"
MAGENTO_DB_PASS="your-db-password"
ADMIN_EMAIL="your@email.com"
ADMIN_PASS="YourAdminPass@123"
```

### 4. Run in order

```bash
sudo ./01-System-Prep.sh
sudo ./02-PHP-MySQL-Installation.sh
sudo ./03-NGINX-Composer-Setup.sh
sudo ./04-Elasticsearch-Redis-Installation.sh
sudo ./05-Magento-Installation.sh
sudo ./06-Web-Server-Config.sh
sudo ./07-Final-Config-Checks.sh
```

### 5. Add local hosts entry

```bash
echo "YOUR_SERVER_IP test.mgt.com pma.mgt.com" | sudo tee -a /etc/hosts
```

---

## What Each Script Does

### `01-System-Prep.sh` — System Preparation
Creates a 2 GB swap file (critical for Composer and DI compilation on constrained RAM), sets `nproc 4096` process limits for the web user, imports GPG keys for MySQL and Elasticsearch apt repositories, and installs base utilities.

### `02-PHP-MySQL-Installation.sh` — PHP & Database
Installs PHP 8.2-FPM with all Magento-required extensions. Installs Composer with checksum validation. Installs MySQL 8.0, creates the Magento database, an app-level DB user, and a read-only DB user for safer external access.

### `03-NGINX-Composer-Setup.sh` — Web Server & Composer Auth
Installs NGINX and configures it to run under the web user. Sets up `auth.json` with Magento Marketplace credentials so `composer install` can pull proprietary packages.

### `04-Elasticsearch-Redis-Installation.sh` — Search & Cache
Installs Elasticsearch 7.x from the official Elastic apt repository. Configures JVM heap (2 GB), `vm.max_map_count`, and file descriptor limits — all required for ES to start cleanly. Installs Redis for sessions and object cache.

### `05-Magento-Installation.sh` — Magento Core Install
Runs `bin/magento setup:install` with full DB, search, cache, and admin configuration. Deploys static content, reindexes all indexers, and sets correct permissions on `var/`, `pub/`, and `app/etc/`.

### `06-Web-Server-Config.sh` — Server Configuration
Creates a dedicated PHP-FPM pool for the web user with a named socket. Writes NGINX site configs for Magento (port 8080) and phpMyAdmin. Generates a self-signed SSL certificate. Installs and configures Varnish to front NGINX on port 80.

### `07-Final-Config-Checks.sh` — Final Checks & Hardening
Sets final file ownership (`2755/644`), creates a read-only Linux user with ACL access for safe file inspection, persists `log_bin_trust_function_creators=1` in MySQL config, configures Magento for FPC via Varnish, and prints a full health check summary across all services.

---

## Credentials Reference

| Service | Username | Default (example) | Notes |
|---|---|---|---|
| MySQL root | root | `Admin@2025Y` | Change before deploying |
| Magento DB | magentser | `MyPass@1234` | App DB user |
| DB read-only | readonly_db_user | `ReadOnly@1234` | Safe to share |
| Magento Admin | admin | `Admin@123` | Change immediately |
| phpMyAdmin | magentser | `MyPass@1234` | Uses DB credentials |

> ⚠️ Replace all default passwords before any production use.

---

## Common Commands

```bash
# Cache management
sudo -u test-ssh php bin/magento cache:flush
sudo -u test-ssh php bin/magento cache:clean

# Indexing
sudo -u test-ssh php bin/magento indexer:reindex
sudo -u test-ssh php bin/magento indexer:status

# Upgrades and compilation
sudo -u test-ssh php bin/magento setup:upgrade
sudo -u test-ssh php bin/magento setup:di:compile
sudo -u test-ssh php bin/magento setup:static-content:deploy -f

# Disable 2FA (dev environments only)
sudo -u test-ssh php bin/magento module:disable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth

# Fix permissions
sudo chown -R test-ssh:clp /var/www/magento
sudo find /var/www/magento -type d -exec chmod 2755 {} \;
sudo find /var/www/magento -type f -exec chmod 644 {} \;
```

---

## Diagnostics

```bash
# Magento logs
sudo tail -f /var/www/magento/var/log/system.log
sudo tail -f /var/www/magento/var/log/exception.log

# NGINX logs
sudo tail -f /var/log/nginx/error.log

# Elasticsearch health
curl -s http://localhost:9200/_cat/health?v

# Redis check
redis-cli ping

# All services status
sudo systemctl status nginx php8.2-fpm mysql elasticsearch redis-server varnish
```

---

## Common Errors

See [`docs/common-errors.md`](docs/common-errors.md) for detailed fixes.

| Error | Cause | Fix |
|---|---|---|
| 403/404 on static files | Missing static deploy or wrong permissions | `setup:static-content:deploy -f` + fix perms |
| 502 Bad Gateway | FastCGI buffer too small | Add `fastcgi_buffers 16 16k` to NGINX config |
| PHP-FPM permission denied | Socket owner mismatch | Align `listen.owner` with NGINX user |
| Elasticsearch indexing fails | ES not ready or wrong version | Check ES health; verify version in Magento config |
| Redis session errors | Wrong connection config | Verify `app/etc/env.php` Redis settings |
| 2FA blocks admin login | 2FA module active, no email configured | Disable `Magento_TwoFactorAuth` for dev |

---

## What I Learned / Challenges Solved

- **Varnish and TLS can't coexist on the same port**: Varnish cannot handle TLS natively. Solving this required a clear two-frontend design — NGINX terminates SSL on 443, Varnish fronts HTTP on 80, and NGINX listens on 8080 as Varnish's backend. Getting the port topology right required tracing the full request path before writing a single config line.

- **PHP-FPM socket permissions aren't automatic**: A generic `www` pool running under a different UID than NGINX causes silent 502s. The fix — a dedicated named pool under the web user — taught me how FastCGI socket ownership actually works, not just the symptom.

- **Elasticsearch 7 is non-negotiable for Magento 2.4**: Magento dropped MySQL catalog search in 2.4.x. Getting ES to start cleanly on a 4 GB droplet required tuning JVM heap (`-Xms2g -Xmx2g`), setting `vm.max_map_count=262144` persistently, and raising the file descriptor limits — none of which are in the Magento install docs.

- **Swap matters more than RAM headroom**: Composer's dependency resolution and `setup:di:compile` both spike memory briefly, not continuously. Adding a 2 GB swap file on a 4 GB server prevented OOM kills during install without upsizing the droplet — a cost vs. reliability tradeoff worth understanding.

- **`git rm --cached` is the real `.gitignore` fix**: Adding a file to `.gitignore` does nothing if it's already tracked. Discovering this the hard way (after committing `.DS_Store` and config files) made the distinction between the index and the working tree concrete, not theoretical.

- **Redis session writes protect against PHP-FPM restarts**: File-based PHP sessions can be wiped when PHP-FPM is restarted or the process tree is recycled. Redis-backed sessions are atomic and process-independent — a subtle but production-critical difference I only understood after tracing a cart-loss scenario.

---

## Future Improvements



- [ ] Replace self-signed cert with Let's Encrypt (Certbot)
- [ ] Export Magento VCL from admin and apply to Varnish for full FPC
- [ ] Centralise all variables in a single `00-vars.sh` source file
- [ ] Add cron job configuration for scheduled indexing and cache warming
- [ ] Integrate secrets management (HashiCorp Vault or Ansible Vault)
- [ ] Build a CI/CD pipeline for zero-downtime, repeatable deployments

---

## Security

Default credentials in this project are **examples only** and must be replaced before any real deployment. Sensitive values (DB passwords, admin credentials, Composer keys) should be injected via environment variables or a secrets manager — never hardcoded. If you find a vulnerability or a hardening gap in the scripts, please open an issue or email [asitminz007@gmail.com](mailto:asitminz007@gmail.com).

---

## License

MIT — see [LICENSE](LICENSE) for details.  
Built for learning and portfolio purposes. Review and harden before any production deployment.

---

<p align="center">
  <b>Magento_DeployKit &copy; 2026 | Built by <a href="https://github.com/Asit0007">Asit Minz</a></b><br>
  <i>Designed to demonstrate production infrastructure engineering on a real-world eCommerce stack</i>
</p>
