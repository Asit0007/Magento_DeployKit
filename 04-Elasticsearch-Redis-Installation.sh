#!/usr/bin/env bash
# ====================================================
# Step 4: Installs and configures Elasticsearch and Redis.
# run composer config --global http-basic.repo.magento.com 17fc346b8209ce37be642a736e34a1b0 b608553396258fe875056e6f4c3371da
#before running this script.
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
# 8. Elasticsearch 7.x
# -----------------------------
info "Install Elasticsearch 7.x (official repo) ..."
sudo apt update
sudo apt install -y elasticsearch
info "Configuring Elasticsearch JVM heap size, system maps, and file descriptor limits..."
sudo sed -i 's/^# -Xms1g/-Xms2g/' /etc/elasticsearch/jvm.options
sudo sed -i 's/^# -Xmx1g/-Xmx2g/' /etc/elasticsearch/jvm.options
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
sudo mkdir -p /etc/systemd/system/elasticsearch.service.d/
sudo tee /etc/systemd/system/elasticsearch.service.d/override.conf > /dev/null <<'OVERRIDE'
[Service]
LimitNOFILE=65536
OVERRIDE
sudo systemctl daemon-reload
sudo systemctl enable --now elasticsearch
wait_for_service "Elasticsearch" "curl -sS http://localhost:9200"

# -----------------------------
# 9. Redis
# -----------------------------
info "Install Redis..."
sudo apt install -y redis-server
sudo systemctl enable --now redis-server || sudo systemctl enable --now redis || true
wait_for_service "Redis" "redis-cli ping"
