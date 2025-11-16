#!/usr/bin/env bash
# ====================================================
# Step 1: Prepares the system with necessary swap space,
# process limits, GPG keys, and base packages.
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
        if [ $(( $(date +s) - start_time )) -gt $max_wait ]; then
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
# 1. Address resource constraints (memory & process limits)
# -----------------------------
info "Setting up a 2GB swap file to handle memory-intensive operations..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi
info "Increasing max processes limit for user ${WEB_USER}..."
if ! grep -q "test-ssh hard nproc" /etc/security/limits.conf; then
  echo "${WEB_USER} hard nproc 4096" | sudo tee -a /etc/security/limits.conf
  echo "${WEB_USER} soft nproc 4096" | sudo tee -a /etc/security/limits.conf
fi

# -----------------------------
# 2. Add GPG keys for repositories
# -----------------------------
info "Importing GPG keys for MySQL and Elasticsearch..."
sudo mkdir -p /etc/apt/keyrings
info "Using a reliable method to download and add the MySQL GPG key."
wget -O- https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/mysql.gpg > /dev/null
if [ ! -s /etc/apt/trusted.gpg.d/mysql.gpg ]; then
  error_exit "MySQL GPG key was not imported successfully. The file is empty."
fi
sudo tee /etc/apt/sources.list.d/mysql.list >/dev/null <<EOF
deb http://repo.mysql.com/apt/debian bookworm mysql-8.0
EOF
info "Downloading and importing Elasticsearch GPG key."
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/elastic.gpg > /dev/null
if [ ! -s /etc/apt/trusted.gpg.d/elastic.gpg ]; then
  error_exit "Elasticsearch GPG key was not imported successfully. The file is empty."
fi
sudo tee /etc/apt/sources.list.d/elastic-7.x.list >/dev/null <<EOF
deb https://artifacts.elastic.co/packages/7.x/apt stable main
EOF

# -----------------------------
# 3. Basic system update + utils
# -----------------------------
info "Clean apt cache to force a fresh re-fetch and re-verification..."
sudo apt clean
sudo rm -rf /var/lib/apt/lists/*
info "Update apt and install base packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip apt-transport-https ca-certificates gnupg2 lsb-release dialog rsync jq
