# Magento 2 Common Errors & Fixes

This document lists common issues encountered during Magento 2 installation and configuration on Debian 12, along with verified fixes and diagnostic commands.

---

## 🧱 403 / 404 Static Files (CSS, JS, Images)

**Symptoms:**

- Frontend loads without styles or scripts.
- Browser console shows 403/404 for `/static/...` URLs.

**Root Causes:**

- Nginx misconfiguration (alias vs root mismatch).
- Magento static files not deployed.
- File or directory permissions.

**Fix:**

```bash
sudo chown -R $MAGENTO_USER:$MAGENTO_GROUP $MAGENTO_DIR
sudo find $MAGENTO_DIR -type d -exec chmod 775 {} \;
sudo find $MAGENTO_DIR -type f -exec chmod 664 {} \;

sudo -u $MAGENTO_USER php bin/magento setup:static-content:deploy -f
sudo -u $MAGENTO_USER php bin/magento cache:flush
```

**Nginx block example:**

```nginx
location /static/ {
    alias /var/www/magento/pub/static/;
    expires max;
    add_header Cache-Control public;
    try_files $uri $uri/ /static.php?resource=$uri&$args;
}
```

**Verify:**

```bash
curl -I -k -H "Host: test.mgt.com" https://127.0.0.1/static/version$(date +%s)/frontend/Magento/luma/en_US/css/styles-l.css
```

If you get `403`, check permissions or use the real deployed version in the URL (from `pub/static/deployed_version.txt`).

---

## ⚙️ Upstream Sent Too Big Header

**Symptoms:**

- Admin login fails with `502 Bad Gateway`.
- Nginx error log shows: `upstream sent too big header while reading response header from upstream`.

**Fix:**
Edit `/etc/nginx/nginx.conf` or your site’s `.conf`:

```nginx
fastcgi_buffers 16 16k;
fastcgi_buffer_size 32k;
fastcgi_busy_buffers_size 32k;
```

Then:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## 🧑‍💻 PHP-FPM Socket Permission Denied

**Symptoms:**

- `connect() to unix:/run/php/php8.3-fpm-magento.sock failed (13: Permission denied)`

**Fix:**

1. Check `/etc/php/8.3/fpm/pool.d/magento.conf`:

```ini
user = test-ssh
group = clp
listen = /run/php/php8.3-fpm-magento.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
```

2. Restart PHP-FPM:

```bash
sudo systemctl restart php8.3-fpm
```

3. Ensure Nginx runs as `www-data` (or same as PHP-FPM user):

```bash
sudo grep '^user' /etc/nginx/nginx.conf
```

---

## 🔒 Generated Directory Permission Errors

**Symptoms:**

- `Class ... Interceptor does not exist`
- `generated directory permission is read-only`

**Fix:**

```bash
sudo rm -rf var/cache var/page_cache generated/* var/view_preprocessed/*
sudo chown -R $MAGENTO_USER:$MAGENTO_GROUP $MAGENTO_DIR
sudo find $MAGENTO_DIR -type d -exec chmod 775 {} \;
sudo find $MAGENTO_DIR -type f -exec chmod 664 {} \;

sudo -u $MAGENTO_USER php bin/magento setup:di:compile
sudo -u $MAGENTO_USER php bin/magento setup:static-content:deploy -f
sudo -u $MAGENTO_USER php bin/magento cache:flush
```

---

## 🧠 Redis Session/Cache Issues

**Symptoms:**

- "Session expired" errors.
- Cache backend unreachable.

**Fix:**
Check Redis connection:

```bash
redis-cli -h 127.0.0.1 -p 6379 ping
```

If it returns `PONG`, Redis is fine.

Verify `app/etc/env.php` has correct Redis config:

```php
'session' => [
    'save' => 'redis',
    'redis' => [
        'host' => '127.0.0.1',
        'port' => '6379',
        'db' => '2',
        'password' => '',
        'timeout' => '2.5',
    ],
],
```

Flush Redis cache if needed:

```bash
redis-cli FLUSHALL
```

---

## 🔍 Elasticsearch Indexing / Search Issues

**Symptoms:**

- Products don’t appear in search results.
- Catalog indexing incomplete.

**Fix:**

```bash
sudo systemctl status elasticsearch
curl localhost:9200/_cat/indices?v
sudo -u $MAGENTO_USER php bin/magento indexer:reindex
sudo -u $MAGENTO_USER php bin/magento cache:flush
```

Ensure `Stores → Configuration → Catalog → Catalog Search` is set to your running ES version.

---

## ⚠️ Two-Factor Authentication (2FA) Email Missing

**Symptoms:**

- Admin login blocked by 2FA but no email received.

**Fix (disable for dev use):**

```bash
sudo -u $MAGENTO_USER php bin/magento module:disable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth
sudo -u $MAGENTO_USER php bin/magento setup:upgrade
sudo -u $MAGENTO_USER php bin/magento cache:flush
```

---

## 🧾 Product Not Visible on Frontend

**Checklist:**

1. Product `status = 1` and `visibility = 4`
2. Product is assigned to **active category**
3. Product is in **stock** and has **qty > 0**
4. Category is included in the menu and active
5. Indexes are up to date:

```bash
sudo -u $MAGENTO_USER php bin/magento indexer:reindex
```

6. Cache flushed:

```bash
sudo -u $MAGENTO_USER php bin/magento cache:flush
```

7. Re-deploy static content if still not visible:

```bash
sudo -u $MAGENTO_USER php bin/magento setup:static-content:deploy -f
```

---

## 🧹 Cleanup & Maintenance

Useful commands:

```bash
sudo -u $MAGENTO_USER php bin/magento cache:clean
sudo -u $MAGENTO_USER php bin/magento cache:flush
sudo -u $MAGENTO_USER php bin/magento setup:upgrade
sudo -u $MAGENTO_USER php bin/magento indexer:reindex
sudo -u $MAGENTO_USER php bin/magento setup:di:compile
```

---

✅ **Always remember:** Most Magento errors trace back to one of these three things:

1. Incorrect permissions/ownership
2. Wrong Nginx or PHP-FPM user mapping
3. Missing static content or incomplete DI compilation
