# Magento 2 Server Setup & Automated Deployment (Debian + Nginx + PHP-FPM + MySQL)

## Project summary

This project deploys an eCommerce website built on Magento 2. It provides modular, step-by-step scripts to provision a Debian 12 server with Nginx, PHP 8.3-FPM, MySQL, Elasticsearch, Redis, Varnish, and HTTPS (self-signed), plus phpMyAdmin for DB management. Use the scripts to set up a reproducible Magento environment for development, testing, or small-scale production.

---

## Quick description

An automated deployment toolset for a Magento 2 eCommerce site. The stack includes:

- Debian 12
- Nginx (web server)
- PHP 8.3 + PHP-FPM (app runtime)
- MySQL 8 (database)
- Elasticsearch 7 (catalog search)
- Redis (sessions + cache)
- HTTPS (self-signed or replace with CA cert)
- phpMyAdmin (pma.mgt.com)

---

## Server details (example)

- Hostname: debian-s-2vcpu-4gb-blr1-01
- Domain: test.mgt.com
- Web root: /var/www/magento
- Magento file owner: test-ssh
- PHP-FPM socket: /run/php/php8.3-fpm-magento.sock
- Database: magento (local MySQL)

---

## Credentials (example)

- MySQL (local): root / <your_mysql_root_password>
- Magento Admin: create credentials during installation or set in install script
- SSH: root and a deploy user (test-ssh) — use keys, avoid passwords

(Replace placeholders with secure values before running any install scripts.)

---

## Files & project structure

magento-fasttrack-deploy/
├── README.md
├── 01-System-Prep.sh
├── 02-PHP-MySQL-Installation.sh
├── 03-NGINX-Composer-Setup.sh
├── 04-Elasticsearch-Redis-Installation.sh
├── 05-Magento-Installation.sh
├── 06-Web-Server-Config.sh
├── 07-Final-Config-Checks.sh
├── nginx/
│ └── test.mgt.com.conf
└── common-errors/
└── common-errors.md

---

## Usage (recommended flow)

1. Clone repo and review variables:
   git clone
2. (Optional) source variables if you use a central vars file:
   source ./00-vars.sh
3. Run scripts in order:
   ./01-System-Prep.sh
   ./02-PHP-MySQL-Installation.sh
   ./03-NGINX-Composer-Setup.sh
   ./04-Elasticsearch-Redis-Installation.sh
   ./05-Magento-Installation.sh
   ./06-Web-Server-Config.sh
   ./07-Final-Config-Checks.sh
4. Add hosts entries for local testing:
   127.0.0.1 test.mgt.com
   127.0.0.1 pma.mgt.com

---

## Common commands (run as deploy user)

Run Magento CLI as the web owner:
sudo -u test-ssh php bin/magento <command>

Examples:

- sudo -u test-ssh php bin/magento cache:flush
- sudo -u test-ssh php bin/magento indexer:reindex
- sudo -u test-ssh php bin/magento setup:upgrade
- sudo -u test-ssh php bin/magento setup:di:compile
- sudo -u test-ssh php bin/magento setup:static-content:deploy -f
- sudo -u test-ssh php bin/magento module:disable Magento_TwoFactorAuth

---

## File & folder permissions

Set owner and perms:
sudo chown -R test-ssh:www-data /var/www/magento
sudo find /var/www/magento -type d -exec chmod 775 {} \;
sudo find /var/www/magento -type f -exec chmod 664 {} \;

Writable directories:

- var/
- pub/static/
- pub/media/
- generated/

---

## Diagnostics & useful checks

- Indexer status:
  sudo -u test-ssh php bin/magento indexer:status
- Cache status:
  sudo -u test-ssh php bin/magento cache:status
- Tail logs:
  sudo tail -n 50 /var/www/magento/var/log/system.log
  sudo tail -n 50 /var/log/nginx/test.mgt.com.error.log
- Check products:
  mysql -u root -p'<your_mysql_root_password>' -D magento -e "SELECT sku, type_id, created_at FROM catalog_product_entity;"

---

## Maintenance & backups

- Backup DB:
  mysqldump -u root -p'<your_mysql_root_password>' magento > /root/magento_backup.sql
- Clear generated:
  rm -rf generated/ var/cache/ var/view_preprocessed/
- Restart services:
  systemctl restart php8.3-fpm
  systemctl restart nginx

---

## Current config notes

- Magento mode: developer
- Full Page Cache: File
- Indexer mode: Schedule
- PHP: 8.3
- Nginx: ports 80 / 443
- DB: MySQL local

---

## Common errors & quick fixes

See docs/common-errors.md. Typical issues:

- 403/404 static files → permissions and rewrite rules
- “upstream sent too big header” → increase fastcgi_buffers
- PHP-FPM socket permission denied → check pool user/group and socket perms
- Redis/session errors → verify Redis connection and auth
- Elasticsearch indexing failures → validate ES health and indices

---

## Future improvements

1. Configure cron for scheduled indexing and cache maintenance.
2. Replace self-signed certs with CA-signed certificates.
3. Integrate Varnish for improved full-page caching.
4. Automate secure secrets management (Vault/Ansible/Vault-like).
5. CI/CD pipeline for repeatable deployments.

---

## License & notes

Intended for educational purposes. Review and harden before production. Replace placeholders with secure credentials, test in disposable environments first.

_Maintained by: Asit Minz_
_Last Updated: October 2025_
