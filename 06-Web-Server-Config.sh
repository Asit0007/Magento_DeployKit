#!/usr/bin/env bash
# ====================================================
# Step 6: Configures PHP-FPM, NGINX sites, and Varnish.
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
# 14. PHP-FPM pool
# -----------------------------
info "Create PHP-FPM pool for ${WEB_USER}"
sudo mkdir -p /run/php
sudo tee /etc/php/8.3/fpm/pool.d/${WEB_USER}.conf > /dev/null <<'POOL'
[magento]
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
POOL
sudo sed -i "s/WEB_USER_PLACEHOLDER/${WEB_USER}/g" /etc/php/8.3/fpm/pool.d/${WEB_USER}.conf
sudo sed -i "s/WEB_GROUP_PLACEHOLDER/${WEB_GROUP}/g" /etc/php/8.3/fpm/pool.d/${WEB_USER}.conf
sudo systemctl restart php8.3-fpm

# -----------------------------
# 15. NGINX site configs
# -----------------------------
WWW_ROOT="/var/www/magento"
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

# -----------------------------
# 16. phpMyAdmin site
# -----------------------------
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
# 17. Self-signed SSL
# -----------------------------
info "Generate self-signed certificate for ${MAGENTO_DOMAIN}"
sudo mkdir -p /etc/ssl/magento
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/magento/self.key -out /etc/ssl/magento/self.crt \
  -subj "/CN=${MAGENTO_DOMAIN}/O=dev"
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
# 18. Varnish
# -----------------------------
info "Install and configure Varnish to listen on 80 and forward to nginx 8080"
sudo apt install -y varnish
sudo tee /etc/varnish/default.vcl > /dev/null <<'VCL'
vcl 4.0;
backend default { .host = "127.0.0.1"; .port = "8080"; }
sub vcl_recv {
  if (req.method == "PURGE") {
    if (client.ip != "127.0.0.1") { return (synth(403,"Not allowed.")); }
    return (purge);
  }
}
VCL
sudo sed -i 's/-a :6081/-a :80/' /lib/systemd/system/varnish.service || true
sudo systemctl daemon-reexec || true
sudo systemctl enable --now varnish || true
wait_for_service "Varnish" "sudo systemctl is-active varnish"
