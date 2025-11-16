#!/usr/bin/env bash
# ====================================================
# Step 3: Installs NGINX and Composer and sets up
# the web user's composer auth.
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

# -----------------------------
# 7. NGINX (will run as WEB_USER)
# -----------------------------
info "Install nginx..."
sudo apt install -y nginx
sudo systemctl enable --now nginx
info "Configure nginx to run as $WEB_USER:$WEB_GROUP..."
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak || true
if grep -qE '^\s*user\s+' /etc/nginx/nginx.conf; then
    sudo sed -i "s/^\s*user\s\+.*/user ${WEB_USER} ${WEB_GROUP};/" /etc/nginx/nginx.conf
else
    sudo sed -i "1iuser ${WEB_USER} ${WEB_GROUP};" /etc/nginx/nginx.conf
fi
sudo systemctl restart nginx

# -----------------------------
# 10. Composer
# -----------------------------
info "Install Composer..."
php -r "copy('https://getcomposer.org/installer','/tmp/composer-setup.php');"
EXPECTED_SIG="$(curl -s https://composer.github.io/installer.sig)"
ACTUAL_SIG="$(php -r "echo hash_file('sha384','/tmp/composer-setup.php');")"
if [ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]; then
    error_exit "Composer installer signature mismatch"
fi
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm /tmp/composer-setup.php
composer --version

# -----------------------------
# 11. Composer auth (Magento repo)
# -----------------------------
info "Check Magento Composer auth keys..."
if [ -z "${MAGENTO_COMPOSER_PUBLIC:-}" ] || [ -z "${MAGENTO_COMPOSER_PRIVATE:-}" ]; then
  cat <<WARN
************************************************************************
MAGENTO COMPOSER KEYS NOT FOUND.
You must set Magento Marketplace composer keys as environment variables BEFORE running:
  export MAGENTO_COMPOSER_PUBLIC="your_public_key"
  export MAGENTO_COMPOSER_PRIVATE="your_private_key"
Or create /home/${WEB_USER}/.composer/auth.json with credentials.
Exiting now. After adding keys, re-run the script (it's idempotent).
************************************************************************
WARN
  exit 1
fi
info "Creating composer auth.json for $WEB_USER..."
sudo -u "$WEB_USER" mkdir -p /home/"$WEB_USER"/.composer
sudo -u "$WEB_USER" tee /home/"$WEB_USER"/.composer/auth.json > /dev/null <<JSON
{
  "http-basic": {
    "repo.magento.com": {
      "username": "${MAGENTO_COMPOSER_PUBLIC}",
      "password": "${MAGENTO_COMPOSER_PRIVATE}"
    }
  }
}
JSON
sudo chown -R "${WEB_USER}:${WEB_GROUP}" /home/"$WEB_USER"/.composer
sudo chmod 600 /home/"$WEB_USER"/.composer/auth.json
info "Composer auth file created: $(ls -l /home/${WEB_USER}/.composer/auth.json)"
