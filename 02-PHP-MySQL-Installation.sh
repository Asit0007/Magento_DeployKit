#!/usr/bin/env bash
# ====================================================
# Step 2: Installs PHP, Composer, and MySQL Server.
# ====================================================

set -e
set -o pipefail

# -----------------------------
# User-editable variables
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
# 1. Install PHP and common extensions
# -----------------------------
info "Installing PHP and common extensions..."
sudo apt install -y php8.2 php8.2-fpm php8.2-mysql php8.2-simplexml php8.2-intl \
    php8.2-soap php8.2-gd php8.2-cli php8.2-opcache php8.2-zip php8.2-curl \
    php8.2-mbstring php8.2-xml php8.2-bcmath php8.2-gmp php8.2-dom php8.2-xmlrpc

# -----------------------------
# 2. Install Composer
# -----------------------------
info "Installing Composer..."
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    error_exit "ERROR: Invalid installer checksum."
fi
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# -----------------------------
# 3. Install MySQL Server and secure it
# -----------------------------
info "Installing MySQL Server..."
sudo apt install -y mysql-server
wait_for_service "MySQL" "systemctl is-active --quiet mysql"

info "Assuming MySQL root password is set and creating Magento database/user..."

# We assume the provided password is correct and use it to run the rest of the commands.
sudo mysql -u root -p"${MYSQL_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${MAGENTO_DB}\` DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${MAGENTO_DB_USER}'@'localhost' IDENTIFIED BY '${MAGENTO_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MAGENTO_DB}\`.* TO '${MAGENTO_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${MYSQL_READONLY_USER}'@'%' IDENTIFIED BY '${MYSQL_READONLY_PASS}';
GRANT SELECT ON \`${MAGENTO_DB}\`.* TO '${MYSQL_READONLY_USER}'@'%';
FLUSH PRIVILEGES;
SQL

# -----------------------------
# 4. Final steps
# -----------------------------
info "PHP and MySQL installation complete. You can now run the next script."
