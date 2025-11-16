#!/bin/bash
set -e
set -o pipefail

# ====================================================
# Full automated Magento 2 stack installer for Debian 12
# - PHP 8.3 (Sury)
# - MySQL 8 (Oracle APT repo) (root password pre-set below)
# - NGINX (runs as test-ssh)
# - Elasticsearch 7.x
# - Redis
# - Magento 2 (Composer) + sample data, configured for ES
# - PHP-FPM pool for test-ssh:clp (unix socket, owned by test-ssh:clp)
# - phpMyAdmin at pma.mgt.com
# - Self-signed SSL (test.mgt.com)
# - Varnish (port 80) -> NGINX backend on 8080
# - Read-only MySQL user and read-only Linux user
# ====================================================

# -----------------------------
# User-editable variables
# -----------------------------
MAGENTO_DOMAIN="test.mgt.com"
PMA_DOMAIN="pma.mgt.com"

# MySQL root password (you provided)
MYSQL_ROOT_PASS="Admin@2025Y"

# Magento DB user / password (idempotent creation)
MAGENTO_DB="magento"
MAGENTO_DB_USER="magentouser"
MAGENTO_DB_PASS="MagentoPass123!"

# Read-only DB user to share
MYSQL_READONLY_USER="readonly_db_user"
MYSQL_READONLY_PASS="readonly_db_pass"

# Linux users / group
WEB_USER="test-ssh"
WEB_GROUP="clp"
READONLY_LINUX_USER="readonly-user"

# Composer (Magento) credentials MUST be provided in env or script will exit
# Set these env vars before running:
# export MAGENTO_COMPOSER_PUBLIC="your_public_key"
# export MAGENTO_COMPOSER_PRIVATE="your_private_key"

# -----------------------------
# Helper
# -----------------------------
info() { echo ">>> $*"; }

# -----------------------------
# 1. Basic system update + utils
# -----------------------------
info "Update apt and install base packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip apt-transport-https ca-certificates gnupg2 lsb-release dialog

# -----------------------------
# 2. Create web user/group
# -----------------------------
info "Create group $WEB_GROUP and user $WEB_USER (if missing)..."
sudo groupadd -f "$WEB_GROUP"
if ! id -u "$WEB_USER" &>/dev/null; then
  sudo useradd -m -s /bin/bash -g "$WEB_GROUP" "$WEB_USER"
fi

# -----------------------------
# 3. PHP 8.3 (Sury repo for Debian)
# -----------------------------
info "Add Sury PHP repo and install PHP 8.3 + extensions..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.sury.org/php/apt.gpg | sudo tee /etc/apt/keyrings/php.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo apt update
sudo apt install -y php8.3 php8.3-cli php8.3-fpm php8.3-common \
  php8.3-mysql php8.3-xml php8.3-curl php8.3-intl php8.3-mbstring \
  php8.3-bcmath php8.3-zip php8.3-gd php8.3-soap

# -----------------------------
# 4. MySQL 8 (Oracle APT repo)
# -----------------------------
info "Install MySQL 8 (Oracle repo). If interactive prompt appears, choose MySQL 8.0 and OK."
TMP_DEB="/tmp/mysql-apt-config.deb"
wget -O "$TMP_DEB" https://dev.mysql.com/get/mysql-apt-config_0.8.32-1_all.deb
# dpkg -i may show an interactive menu — user should select mysql-8.0 there.
sudo dpkg -i "$TMP_DEB" || true
sudo apt update
sudo apt install -y mysql-server

# enable & start
sudo systemctl enable --now mysql

# Ensure mysql root auth is set (use plugin mysql_native_password)
info "Ensure MySQL root authentication is password-based and usable by script..."
sudo mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}'; FLUSH PRIVILEGES;" >/dev/null || true

# Create DB and users idempotently (using root password)
info "Create Magento DB and users (idempotent)..."
mysql -u root -p"${MYSQL_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${MAGENTO_DB}\` DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${MAGENTO_DB_USER}'@'localhost' IDENTIFIED BY '${MAGENTO_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MAGENTO_DB}\`.* TO '${MAGENTO_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${MYSQL_READONLY_USER}'@'%' IDENTIFIED BY '${MYSQL_READONLY_PASS}';
GRANT SELECT ON \`${MAGENTO_DB}\`.* TO '${MYSQL_READONLY_USER}'@'%';
FLUSH PRIVILEGES;
SQL

# -----------------------------
# 5. NGINX (will run as WEB_USER)
# -----------------------------
info "Install nginx..."
sudo apt install -y nginx
sudo systemctl enable --now nginx

# change nginx global user to WEB_USER:WEB_GROUP
info "Configure nginx to run as $WEB_USER:$WEB_GROUP..."
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak || true
# replace or append user line
if grep -qE '^\s*user\s+' /etc/nginx/nginx.conf; then
  sudo sed -i "s/^\s*user\s\+.*/user ${WEB_USER} ${WEB_GROUP};/" /etc/nginx/nginx.conf
else
  sudo sed -i "1iuser ${WEB_USER} ${WEB_GROUP};" /etc/nginx/nginx.conf
fi
sudo systemctl restart nginx

# -----------------------------
# 6. Elasticsearch 7.x
# -----------------------------
info "Install Elasticsearch 7.x (official repo) ..."
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install -y elasticsearch
sudo systemctl enable --now elasticsearch

# wait a bit for ES to be ready
sleep 5
if ! curl -sSf http://127.0.0.1:9200/ >/dev/null 2>&1; then
  info "Warning: Elasticsearch didn't respond on 9200 immediately. Check manually."
fi

# -----------------------------
# 7. Redis
# -----------------------------
info "Install Redis..."
sudo apt install -y redis-server
sudo systemctl enable --now redis

# -----------------------------
# 8. Composer
# -----------------------------
info "Install Composer..."
php -r "copy('https://getcomposer.org/installer','/tmp/composer-setup.php');"
EXPECTED_SIG="$(curl -s https://composer.github.io/installer.sig)"
ACTUAL_SIG="$(php -r "echo hash_file('sha384','/tmp/composer-setup.php');")"
if [ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]; then
  echo "Composer installer signature mismatch"; exit 1
fi
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm /tmp/composer-setup.php
composer --version

# -----------------------------
# 9. Composer auth (Magento repo) — required before composer create-project
# -----------------------------
info "Check Magento Composer auth keys..."
if [ -z "${MAGENTO_COMPOSER_PUBLIC}" ] || [ -z "${MAGENTO_COMPOSER_PRIVATE}" ]; then
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

# -----------------------------
# 10. Magento installation (Composer)
# -----------------------------
WWW_ROOT="/var/www/magento"
info "Create web root ${WWW_ROOT} and install Magento (composer) as ${WEB_USER}..."
sudo mkdir -p "${WWW_ROOT}"
sudo chown "${WEB_USER}:${WEB_GROUP}" "${WWW_ROOT}"

cd /tmp
# composer create-project into /tmp/magento-src then rsync to webroot to avoid partial leftovers
if [ ! -d /tmp/magento-src ]; then
  sudo -u "$WEB_USER" composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.* /tmp/magento-src
fi

# sync files to final webroot (idempotent)
sudo rsync -a --delete /tmp/magento-src/ "${WWW_ROOT}/"
sudo chown -R "${WEB_USER}:${WEB_GROUP}" "${WWW_ROOT}"

info "Run Magento setup:install (this will register DB and base URL)."
cd "${WWW_ROOT}"
sudo -u "$WEB_USER" php bin/magento setup:install \
  --base-url="https://${MAGENTO_DOMAIN}" \
  --db-host="127.0.0.1" \
  --db-name="${MAGENTO_DB}" \
  --db-user="${MAGENTO_DB_USER}" \
  --db-password="${MAGENTO_DB_PASS}" \
  --admin-firstname=Admin --admin-lastname=User \
  --admin-email=admin@"${MAGENTO_DOMAIN}" --admin-user=admin --admin-password='Admin123!' \
  --language=en_US --currency=USD --timezone=UTC \
  --use-rewrites=1 \
  --search-engine=elasticsearch7 \
  --elasticsearch-host=127.0.0.1 --elasticsearch-port=9200

info "Deploy sample data and upgrade"
sudo -u "$WEB_USER" php bin/magento sampledata:deploy || true
sudo -u "$WEB_USER" php bin/magento setup:upgrade
sudo -u "$WEB_USER" php bin/magento cache:flush

# -----------------------------
# 11. Configure Magento to use Redis (cache + session)
# -----------------------------
info "Configure Magento Redis cache + sessions"
sudo -u "$WEB_USER" php bin/magento setup:config:set \
  --cache-backend=redis --cache-backend-redis-server=127.0.0.1 --cache-backend-redis-db=0

sudo -u "$WEB_USER" php bin/magento setup:config:set \
  --session-save=redis --session-save-redis-host=127.0.0.1 --session-save-redis-db=1

# -----------------------------
# 12. PHP-FPM pool for WEB_USER (unix socket owned by WEB_USER:WEB_GROUP)
# -----------------------------
info "Create PHP-FPM pool for ${WEB_USER}"
sudo mkdir -p /run/php
sudo tee /etc/php/8.3/fpm/pool.d/${WEB_USER}.conf > /dev/null <<'EOF'
[webpool]
user = WEB_USER_PLACEHOLDER
group = WEB_GROUP_PLACEHOLDER
listen = /run/php/php8.3-fpm-magento.sock
listen.owner = WEB_USER_PLACEHOLDER
listen.group = WEB_GROUP_PLACEHOLDER
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 10
chdir = /
EOF
# Replace placeholders with real user/group
sudo sed -i "s/WEB_USER_PLACEHOLDER/${WEB_USER}/g" /etc/php/8.3/fpm/pool.d/${WEB_USER}.conf
sudo sed -i "s/WEB_GROUP_PLACEHOLDER/${WEB_GROUP}/g" /etc/php/8.3/fpm/pool.d/${WEB_USER}.conf
sudo systemctl restart php8.3-fpm

# -----------------------------
# 13. NGINX site configs (NGINX listens on 8080 as backend)
# -----------------------------
info "Write NGINX site for Magento (listen 8080 backend for Varnish front)"
sudo tee /etc/nginx/sites-available/magento.conf > /dev/null <<'NGCONF'
server {
    listen 8080;
    server_name PLACEHOLDER_MAGENTO;

    root PLACEHOLDER_ROOT/pub;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm-magento.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg)$ {
       try_files $uri $uri/ /index.php?$args;
       expires max;
       add_header Cache-Control "public";
    }
}
NGCONF
sudo sed -i "s/PLACEHOLDER_MAGENTO/${MAGENTO_DOMAIN}/g" /etc/nginx/sites-available/magento.conf
sudo sed -i "s|PLACEHOLDER_ROOT|${WWW_ROOT}|g" /etc/nginx/sites-available/magento.conf
sudo ln -sf /etc/nginx/sites-available/magento.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# phpMyAdmin site on 8080 (backend)
info "Configure phpMyAdmin site on 8080"
sudo apt install -y phpmyadmin
sudo ln -sf /usr/share/phpmyadmin /var/www/pma
sudo tee /etc/nginx/sites-available/pma.conf > /dev/null <<'PMA'
server {
    listen 8080;
    server_name PLACEHOLDER_PMA;

    root /var/www/pma;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm-magento.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
PMA
sudo sed -i "s/PLACEHOLDER_PMA/${PMA_DOMAIN}/g" /etc/nginx/sites-available/pma.conf
sudo ln -sf /etc/nginx/sites-available/pma.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# -----------------------------
# 14. Self-signed SSL and HTTPS server blocks (Nginx SSL will be used by Varnish frontend LB if you choose)
# -----------------------------
info "Generate self-signed certificate for ${MAGENTO_DOMAIN}"
sudo mkdir -p /etc/ssl/magento
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/magento/self.key -out /etc/ssl/magento/self.crt \
  -subj "/CN=${MAGENTO_DOMAIN}/O=dev"

# SSL site for Magento (Nginx)
sudo tee /etc/nginx/sites-available/magento-ssl.conf > /dev/null <<'SSL'
server {
    listen 443 ssl;
    server_name PLACEHOLDER_MAGENTO;

    ssl_certificate /etc/ssl/magento/self.crt;
    ssl_certificate_key /etc/ssl/magento/self.key;

    root PLACEHOLDER_ROOT/pub;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm-magento.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
SSL
sudo sed -i "s/PLACEHOLDER_MAGENTO/${MAGENTO_DOMAIN}/g" /etc/nginx/sites-available/magento-ssl.conf
sudo sed -i "s|PLACEHOLDER_ROOT|${WWW_ROOT}|g" /etc/nginx/sites-available/magento-ssl.conf
sudo ln -sf /etc/nginx/sites-available/magento-ssl.conf /etc/nginx/sites-enabled/

# SSL site for phpMyAdmin
sudo tee /etc/nginx/sites-available/pma-ssl.conf > /dev/null <<'PMA_SSL'
server {
    listen 443 ssl;
    server_name PLACEHOLDER_PMA;

    ssl_certificate /etc/ssl/magento/self.crt;
    ssl_certificate_key /etc/ssl/magento/self.key;

    root /var/www/pma;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm-magento.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
PMA_SSL
sudo sed -i "s/PLACEHOLDER_PMA/${PMA_DOMAIN}/g" /etc/nginx/sites-available/pma-ssl.conf
sudo ln -sf /etc/nginx/sites-available/pma-ssl.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# -----------------------------
# 15. Varnish - frontend on port 80, backend -> nginx on 8080
# -----------------------------
info "Install and configure Varnish to listen on 80 and forward to nginx 8080"
sudo apt install -y varnish
# configure default.vcl backend
sudo tee /etc/varnish/default.vcl > /dev/null <<VCL
vcl 4.0;
backend default { .host = "127.0.0.1"; .port = "8080"; }
include "/etc/varnish/magento.vcl";
VCL

# generate a basic magento.vcl compatible fragment or leave Magento exported VCL (recommended)
sudo tee /etc/varnish/magento.vcl > /dev/null <<'MAGVCL'
# Basic rules — Magento recommends exporting the full VCL from admin for production.
sub vcl_recv {
  if (req.method == "PURGE") {
    if (client.ip != "127.0.0.1") {
      return (synth(403, "Not allowed."));
    }
    return (purge);
  }
}
MAGVCL

# Edit systemd args to listen on 80 IP (Debian packaging may differ)
sudo sed -i 's/-a :6081/-a :80/' /lib/systemd/system/varnish.service || true
sudo systemctl daemon-reexec
sudo systemctl restart varnish

# -----------------------------
# 16. Ensure ownership + perms
# -----------------------------
info "Set ownership and permissions for Magento webroot"
sudo chown -R ${WEB_USER}:${WEB_GROUP} "${WWW_ROOT}"
sudo find "${WWW_ROOT}" -type d -exec chmod 2755 {} \;
sudo find "${WWW_ROOT}" -type f -exec chmod 644 {} \;

# give write permissions to var, pub/static, pub/media, app/etc
sudo chmod -R g+w "${WWW_ROOT}/var" "${WWW_ROOT}/pub/static" "${WWW_ROOT}/pub/media" "${WWW_ROOT}/app/etc" || true

# -----------------------------
# 17. Read-only linux user (shareable)
# -----------------------------
info "Create readonly linux user (no sudo)"
if ! id -u "${READONLY_LINUX_USER}" &>/dev/null; then
  sudo useradd -m -s /bin/bash "${READONLY_LINUX_USER}"
fi
# give read/execute ACL to webroot
sudo setfacl -R -m u:${READONLY_LINUX_USER}:rX "${WWW_ROOT}"

# -----------------------------
# 18. Final Magento config updates + caches
# -----------------------------
info "Final Magento config: secure urls and caching"
sudo -u "${WEB_USER}" php "${WWW_ROOT}/bin/magento" config:set web/secure/base_url "https://${MAGENTO_DOMAIN}/"
sudo -u "${WEB_USER}" php "${WWW_ROOT}/bin/magento" config:set web/unsecure/base_url "https://${MAGENTO_DOMAIN}/"
sudo -u "${WEB_USER}" php "${WWW_ROOT}/bin/magento" config:set system/full_page_cache/caching_application 2
sudo -u "${WEB_USER}" php "${WWW_ROOT}/bin/magento" cache:flush

# -----------------------------
# 19. Healthcheck summary
# -----------------------------
info "Healthcheck: services status"
echo "PHP: $(php -v | head -n1)"
echo "MySQL: $(mysql --version 2>/dev/null || echo 'mysql not available')"
echo "Elasticsearch: $(curl -sS http://127.0.0.1:9200/ | head -n1 2>/dev/null || echo 'elasticsearch not ready')"
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
   https://${MAGENTO_DOMAIN}    (Magento storefront, self-signed cert)
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
