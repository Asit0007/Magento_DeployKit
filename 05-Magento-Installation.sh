#!/usr/bin/env bash
# ==========================================================
# Step 5: Finalizes the Magento 2 installation.
# ==========================================================

set -e
set -o pipefail

# -----------------------------
# User-editable variables
# -----------------------------
WEB_ROOT="/var/www/magento"
WEB_USER="test-ssh"
WEB_GROUP="clp"

# Database credentials (These must match the values from 02-MariaDB-Setup.sh)
DB_HOST="localhost"
DB_NAME="magento"
DB_USER="magentser"
DB_PASS="MyPass@1234"

# Base URLs for your store
BASE_URL="http://test.mgt.com"
BASE_URL_SECURE="https://test.mgt.com"

# Admin user credentials
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="User"
ADMIN_EMAIL="asitminz007@gmail.com"
ADMIN_USER="admin"
ADMIN_PASS="Admin@123"

# -----------------------------
# Helper functions
# -----------------------------
info() { echo ">>> $*"; }
error_exit() { echo "!!! $*" >&2; exit 1; }

# -----------------------------
# 1. Final Magento Installation
# -----------------------------
info "Starting Magento 2 installation..."

sudo -u "$WEB_USER" php "$WEB_ROOT"/bin/magento setup:install \
--base-url="$BASE_URL"/ \
--base-url-secure="$BASE_URL_SECURE"/ \
--db-host="$DB_HOST" \
--db-name="$DB_NAME" \
--db-user="$DB_USER" \
--db-password="$DB_PASS" \
--backend-frontname="admin" \
--admin-firstname="$ADMIN_FIRSTNAME" \
--admin-lastname="$ADMIN_LASTNAME" \
--admin-email="$ADMIN_EMAIL" \
--admin-user="$ADMIN_USER" \
--admin-password="$ADMIN_PASS" \
--language=en_US \
--currency=USD \
--timezone=America/Los_Angeles \
--use-rewrites=1 \
--session-save=db \
--cleanup-database \
--search-engine=elasticsearch8 \
--elasticsearch-host=localhost \
--elasticsearch-port=9200 \
|| error_exit "Magento installation failed."

# -----------------------------
# 2. Final Configuration and Cleanup
# -----------------------------
info "Deploying static content..."
sudo -u "$WEB_USER" php "$WEB_ROOT"/bin/magento setup:static-content:deploy -f

info "Reindexing all Magento data..."
sudo -u "$WEB_USER" php "$WEB_ROOT"/bin/magento indexer:reindex

info "Clearing cache..."
sudo -u "$WEB_USER" php "$WEB_ROOT"/bin/magento cache:clean

info "Setting final file permissions..."
sudo find "$WEB_ROOT"/var "$WEB_ROOT"/pub/static "$WEB_ROOT"/pub/media "$WEB_ROOT"/app/etc -type d -exec chmod 777 {} \;
sudo find "$WEB_ROOT"/var "$WEB_ROOT"/pub/static "$WEB_ROOT"/pub/media "$WEB_ROOT"/app/etc -type f -exec chmod 666 {} \;

info "All installation steps are now complete!"
info "Please access your new Magento store via the provided base URL."
