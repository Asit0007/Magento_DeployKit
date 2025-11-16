#!/usr/bin/env bash
# ====================================================
# Step 7: Sets final permissions, performs Magento config
# updates, and runs health checks.
# ====================================================

set -e
set -o pipefail

# -----------------------------
# User-editable variables (copied for each script)
# -----------------------------
MAGENTO_DOMAIN="test.mgt.com"
PMA_DOMAIN="pma.mgt.com"
MYSQL_ROOT_PASS="Admin@2025Y"
MAGENTO_DB="magento"
MAGENTO_DB_USER="magentser"
MAGENTO_DB_PASS="MyPass@1234"
MYSQL_READONLY_USER="readonly_db_user"
MYSQL_READONLY_PASS="ReadOnly@1234"
WEB_USER="test-ssh"
WEB_GROUP="clp"
READONLY_LINUX_USER="readonly-user"
WEB_ROOT="/var/www/magento"

# -----------------------------
# Helper functions
# -----------------------------
info(){ echo ">>> $*"; }
error_exit() { echo "!!! $*" >&2; exit 1; }
wait_for_service() {
    local service_name="$1"
    local command_check="$2"
    info "Waiting for $service_name to be ready..."
    local start_time=$(date +%s)
    local max_wait=300 # 5 minutes
    while ! eval "$command_check" &>/dev/null; do
        if [ $(( $(date +%s) - start_time )) -gt $max_wait ]; then
            printf "."
            sleep 5
        fi
        printf "."
        sleep 5
    done
    echo ""
    info "$service_name is ready."
}
WWW_ROOT="/var/www/magento"

# -----------------------------
# 19. Ensure ownership + perms
# -----------------------------
info "Set ownership and permissions for Magento webroot"
sudo chown -R ${WEB_USER}:${WEB_GROUP} "${WEB_ROOT}"
sudo find "${WEB_ROOT}" -type d -exec chmod 2755 {} \;
sudo find "${WEB_ROOT}" -type f -exec chmod 644 {} \;
sudo chmod -R g+w "${WEB_ROOT}/var" "${WEB_ROOT}/pub/static" "${WEB_ROOT}/pub/media" "${WEB_ROOT}/app/etc" || true

# -----------------------------
# 20. Read-only linux user (shareable)
# -----------------------------
info "Create readonly linux user (no sudo)"
if ! id -u "${READONLY_LINUX_USER}" &>/dev/null; then
    sudo useradd -m -s /bin/bash "${READONLY_LINUX_USER}"
fi
sudo setfacl -R -m u:${READONLY_LINUX_USER}:rX "${WWW_ROOT}" || true

# -----------------------------
# 21. Persist MySQL trigger setting (needed for Magento)
# -----------------------------
info "Ensure log_bin_trust_function_creators=1 for MySQL (needed for triggers)"
sudo mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SET GLOBAL log_bin_trust_function_creators = 1;"
if ! sudo grep -q '^log_bin_trust_function_creators' /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null; then
    echo 'log_bin_trust_function_creators = 1' | sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf >/dev/null
    sudo systemctl restart mysql
fi

# -----------------------------
# 22. Final Magento config updates + caches
# -----------------------------
info "Final Magento config: secure urls and caching"
sudo -u "$WEB_USER" php "$WEB_ROOT/bin/magento" config:set web/secure/base_url "https://${MAGENTO_DOMAIN}/"
sudo -u "$WEB_USER" php "$WEB_ROOT/bin/magento" config:set web/unsecure/base_url "https://${MAGENTO_DOMAIN}/"
sudo -u "$WEB_USER" php "$WEB_ROOT/bin/magento" config:set system/full_page_cache/caching_application 2
sudo -u "$WEB_USER" php "$WEB_ROOT/bin/magento" cache:flush

# -----------------------------
# 23. Healthcheck summary
# -----------------------------
info "Healthcheck: services status"
echo "PHP: $(php -v | head -n1)"
echo "MySQL: $(mysql --version 2>/dev/null || echo 'mysql not available')"
echo "Elasticsearch: $(curl -sS http://localhost:9200 | jq -r .version.number 2>/dev/null || echo 'elasticsearch not ready')"
echo "Redis: $(redis-cli ping 2>/dev/null || echo 'redis not ready')"
echo "NGINX: $(sudo systemctl is-active nginx || true)"
echo "Varnish: $(sudo systemctl is-active varnish || true)"

# -----------------------------
# Final messages
# -----------------------------
cat <<ENDMSG

Setup complete.

Local test steps:
1) Add entries in your local /etc/hosts:
    <droplet-ip> ${MAGENTO_DOMAIN} ${PMA_DOMAIN}

2) Visit:
    https://${MAGENTO_DOMAIN}      (Magento storefront, self-signed cert)
    https://${MAGENTO_DOMAIN}/admin  (Magento admin user: admin / Admin123!)
    https://${PMA_DOMAIN}         (phpMyAdmin — login with ${MAGENTO_DB_USER} / ${MAGENTO_DB_PASS})

3) Read-only DB user to share:
    ${MYSQL_READONLY_USER} / ${MYSQL_READONLY_PASS}

4) Read-only Linux user (set a password):
    sudo passwd ${READONLY_LINUX_USER}

Notes & warnings:
- Magento composer install requires valid Marketplace keys (set env vars MAGENTO_COMPOSER_PUBLIC and MAGENTO_COMPOSER_PRIVATE).
- For production, export the Magento VCL from admin and replace /etc/varnish/magento.vcl with it.
- Varnish is fronting nginx (80 -> 8080). If you want to terminate TLS at a load balancer, adjust accordingly.

ENDMSG
