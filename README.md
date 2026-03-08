# 🛒 Magento 2 Server Setup — Automated Deployment

> **Automated, modular Magento 2 deployment on Debian 12**  
> Stack: Nginx · PHP 8.2-FPM · MySQL 8 · Elasticsearch 7 · Redis · Varnish · HTTPS

---

## 📸 Screenshots

### 🏠 Storefront — Homepage

The default Luma theme with a sample product listing, served over HTTPS via Nginx + Varnish.

![Magento Storefront Homepage](docs/screenshots/01-storefront-homepage.png)

---

### 🔍 Storefront — Elasticsearch Search Results

Product search powered by Elasticsearch 7. Query "watch" returns results from the catalog index.

![Magento Search Results](docs/screenshots/02-storefront-search-results.png)

---

### 🔒 Admin Panel — Login

Magento 2 admin login at `https://test.mgt.com/admin` with self-signed SSL.

![Magento Admin Login](docs/screenshots/03-magento-admin-login.png)

---

### ⚙️ Admin Panel — Cache Management

All 15 Magento cache types enabled. Full-page cache (FPC) is active, backed by Varnish.

![Magento Cache Management](docs/screenshots/04-admin-cache-management.png)

---

### ⚡ Varnish Caching — Before & After

**Cold cache (first request)** — Full page load: 3.0 MB transferred, Finish: 1.60s

![Search Results — Cold Cache](docs/screenshots/05-search-uncached-devtools.png)

**Warm cache (subsequent request)** — Served from memory: 77.4 kB transferred, Finish: 910ms

![Search Results — Warm Cache](docs/screenshots/06-search-cached-devtools.png)

> Varnish reduces data transferred by ~97% on cached pages (3.0 MB → 77.4 kB).

---

### 🗄️ phpMyAdmin

Database management UI accessible at `https://pma.mgt.com`, running on the same Nginx/PHP-FPM stack.

![phpMyAdmin Login](docs/screenshots/07-phpmyadmin-login.png)

---

### ☁️ DigitalOcean Droplet

Server running on a DigitalOcean Debian 12 droplet — 2 vCPU / 4 GB RAM / 80 GB Disk, BLR1 region.

![DigitalOcean Droplet Dashboard](docs/screenshots/08-digitalocean-droplet.png)

---

### 🌐 Live HTTPS URLs

![Storefront HTTPS URL](docs/screenshots/09-storefront-https-url.png)
![Elasticsearch Search URL](docs/screenshots/10-search-https-url.png)
![phpMyAdmin HTTPS URL](docs/screenshots/11-pma-https-url.png)

| URL                                                  | Description                          |
| ---------------------------------------------------- | ------------------------------------ |
| `https://test.mgt.com`                               | Magento storefront — self-signed SSL |
| `https://test.mgt.com/catalogsearch/result/?q=watch` | Elasticsearch-powered search         |
| `https://pma.mgt.com`                                | phpMyAdmin — separate subdomain      |

---

## 🏗️ Architecture

![Magento 2 Server Architecture](docs/architecture-diagram.svg)

### Stack Overview

| Layer          | Component       | Version   | Role                         |
| -------------- | --------------- | --------- | ---------------------------- |
| Edge / Cache   | Varnish         | 7.x       | Full-page cache, port 80     |
| TLS            | NGINX + OpenSSL | —         | SSL termination, port 443    |
| Web Server     | NGINX           | latest    | Reverse proxy, port 8080     |
| App Runtime    | PHP-FPM         | 8.2       | Magento app, FastCGI socket  |
| Application    | Magento 2       | 2.4.8-p2  | eCommerce core               |
| Database       | MySQL           | 8.0       | Primary datastore, port 3306 |
| Search         | Elasticsearch   | 7.x       | Catalog search, port 9200    |
| Cache/Sessions | Redis           | latest    | In-memory cache, port 6379   |
| DB Admin       | phpMyAdmin      | latest    | Browser-based DB management  |
| Hosting        | DigitalOcean    | Debian 12 | 2 vCPU / 4 GB / 80 GB BLR1   |

### Request Flow

```
Browser
  │
  ├─[HTTP :80]──→ Varnish (full-page cache)
  │                    └─[cache miss]──→ NGINX :8080 ──→ PHP-FPM ──→ Magento 2
  │
  └─[HTTPS :443]─→ NGINX SSL ──→ PHP-FPM ──→ Magento 2
                                                  ├──→ MySQL (data)
                                                  ├──→ Elasticsearch (search)
                                                  ├──→ Redis (sessions + cache)
                                                  └──→ Filesystem (static assets)
```

---

## 📁 Project Structure

```
magento-fasttrack-deploy/
├── README.md
├── 01-System-Prep.sh                       # Swap, process limits, GPG keys, base packages
├── 02-PHP-MySQL-Installation.sh            # PHP 8.2, Composer, MySQL 8 setup
├── 03-NGINX-Composer-Setup.sh              # NGINX install, Composer auth for Magento repo
├── 04-Elasticsearch-Redis-Installation.sh  # Elasticsearch 7.x + Redis
├── 05-Magento-Installation.sh              # Magento setup:install, static deploy, reindex
├── 06-Web-Server-Config.sh                 # PHP-FPM pool, NGINX sites, SSL, Varnish
├── 07-Final-Config-Checks.sh               # Permissions, Magento config, health checks
├── docs/
│   ├── architecture-diagram.svg
│   ├── common-errors.md
│   └── screenshots/
│       ├── 01-storefront-homepage.png
│       ├── 02-storefront-search-results.png
│       ├── 03-magento-admin-login.png
│       ├── 04-admin-cache-management.png
│       ├── 05-search-uncached-devtools.png
│       ├── 06-search-cached-devtools.png
│       ├── 07-phpmyadmin-login.png
│       ├── 08-digitalocean-droplet.png
│       ├── 09-storefront-https-url.png
│       ├── 10-search-https-url.png
│       └── 11-pma-https-url.png
└── nginx/
    └── test.mgt.com.conf
```

---

## ⚡ Quick Start

### Prerequisites

- Fresh **Debian 12** server (2 vCPU, 4 GB RAM minimum recommended)
- Root or sudo access
- [Magento Marketplace](https://commercemarketplace.adobe.com/) account with composer keys

### 1. Clone the repository

```bash
git clone https://github.com/your-username/magento-fasttrack-deploy.git
cd magento-fasttrack-deploy
chmod +x *.sh
```

### 2. Set your Magento Composer keys

```bash
export MAGENTO_COMPOSER_PUBLIC="your_public_key"
export MAGENTO_COMPOSER_PRIVATE="your_private_key"
```

### 3. Edit variables (top of each script)

```bash
MAGENTO_DOMAIN="test.mgt.com"
MYSQL_ROOT_PASS="your-secure-password"
MAGENTO_DB_PASS="your-db-password"
ADMIN_EMAIL="your@email.com"
ADMIN_PASS="YourAdminPass@123"
```

### 4. Run scripts in order

```bash
sudo ./01-System-Prep.sh
sudo ./02-PHP-MySQL-Installation.sh
sudo ./03-NGINX-Composer-Setup.sh
sudo ./04-Elasticsearch-Redis-Installation.sh
sudo ./05-Magento-Installation.sh
sudo ./06-Web-Server-Config.sh
sudo ./07-Final-Config-Checks.sh
```

### 5. Add local hosts entries

```bash
echo "YOUR_SERVER_IP test.mgt.com pma.mgt.com" | sudo tee -a /etc/hosts
```

---

## 🖥️ What Each Script Does

### `01-System-Prep.sh` — System Preparation

- Creates a **2 GB swap file** for memory-intensive Magento operations
- Sets **process limits** (`nproc 4096`) for the web user
- Imports **GPG keys** for MySQL and Elasticsearch repositories
- Runs `apt update` and installs base utilities

### `02-PHP-MySQL-Installation.sh` — PHP & Database

- Installs **PHP 8.2** with all Magento-required extensions
- Installs and verifies **Composer** (checksum-validated)
- Installs **MySQL 8.0** and creates the Magento database, user, and a read-only DB user

### `03-NGINX-Composer-Setup.sh` — Web Server & Composer Auth

- Installs **NGINX** and configures it to run as the web user
- Sets up **Composer `auth.json`** with Magento Marketplace credentials
- Validates Composer installer signature before install

### `04-Elasticsearch-Redis-Installation.sh` — Search & Cache

- Installs **Elasticsearch 7.x** from the official Elastic apt repository
- Configures JVM heap (2 GB), `vm.max_map_count`, and file descriptor limits
- Installs **Redis** for sessions and cache

### `05-Magento-Installation.sh` — Magento Core Install

- Runs `bin/magento setup:install` with full configuration
- Deploys static content, reindexes, and clears cache
- Sets correct file permissions on var/, pub/, app/etc/

### `06-Web-Server-Config.sh` — Server Configuration

- Creates **PHP-FPM pool** for the web user with a dedicated socket
- Writes **NGINX site configs** for Magento (port 8080) and phpMyAdmin
- Generates a **self-signed SSL certificate** and configures HTTPS
- Installs and configures **Varnish** to front NGINX on port 80

### `07-Final-Config-Checks.sh` — Final Checks

- Sets final **file ownership and permissions** (2755/644)
- Creates a **read-only Linux user** with ACL access to the webroot
- Persists `log_bin_trust_function_creators=1` in MySQL config
- Configures Magento for **full-page caching via Varnish**
- Prints a **health check summary** (PHP, MySQL, ES, Redis, NGINX, Varnish)

---

## 🔐 Credentials Reference

| Service       | Username         | Default (example) | Notes                   |
| ------------- | ---------------- | ----------------- | ----------------------- |
| MySQL root    | root             | `Admin@2025Y`     | Change before deploying |
| Magento DB    | magentser        | `MyPass@1234`     | App DB user             |
| DB read-only  | readonly_db_user | `ReadOnly@1234`   | Share safely            |
| Magento Admin | admin            | `Admin@123`       | Change immediately      |
| phpMyAdmin    | magentser        | `MyPass@1234`     | Uses DB credentials     |

> ⚠️ **Replace all default passwords** before deploying to production.

---

## 🛠️ Common Commands

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

# Disable 2FA (dev only)
sudo -u test-ssh php bin/magento module:disable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth

# Fix permissions
sudo chown -R test-ssh:clp /var/www/magento
sudo find /var/www/magento -type d -exec chmod 2755 {} \;
sudo find /var/www/magento -type f -exec chmod 644 {} \;
```

---

## 📊 Diagnostics

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
sudo systemctl status nginx php8.3-fpm mysql elasticsearch redis-server varnish
```

---

## ❗ Common Errors

See [`docs/common-errors.md`](docs/common-errors.md) for detailed fixes.

| Error                        | Cause                                  | Fix                                              |
| ---------------------------- | -------------------------------------- | ------------------------------------------------ |
| 403/404 static files         | Permissions or missing static deploy   | `setup:static-content:deploy -f` + fix perms     |
| 502 Bad Gateway              | FastCGI buffer too small               | Add `fastcgi_buffers 16 16k` to NGINX            |
| PHP-FPM permission denied    | Socket owner mismatch                  | Align `listen.owner` with NGINX user             |
| Elasticsearch indexing fails | ES not ready or wrong version          | Check ES health, match version in Magento config |
| Redis session errors         | Wrong connection config                | Verify `app/etc/env.php` Redis settings          |
| 2FA blocks admin login       | 2FA module active, no email configured | Disable `Magento_TwoFactorAuth` for dev          |

---

## 🔮 Future Improvements

- [ ] Replace self-signed cert with Let's Encrypt (Certbot)
- [ ] Export Magento VCL from admin and apply to Varnish for full FPC
- [ ] Add cron job configuration for scheduled indexing
- [ ] Centralise variables in a single `00-vars.sh` source file
- [ ] Integrate secrets management (HashiCorp Vault or Ansible Vault)
- [ ] Build CI/CD pipeline for repeatable zero-downtime deployments

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.  
Intended for educational and development use. Harden and review before any production deployment.

---

_Maintained by: Asit Minz · Last Updated: March 2026_
