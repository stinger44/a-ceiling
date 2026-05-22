#!/bin/bash
# Временный скрипт деплоя через scp (без rsync)
set -euo pipefail

SSH_ALIAS="yc"
DOMAIN="alphaceiling23.ru"
REMOTE_SITE="/var/www/alphaceiling"
SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
NGINX_SITE_CONF="/etc/nginx/sites-available/reality-masquerade"
NGINX_HTTP_CONF="/etc/nginx/conf.d/rate_limit.conf"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# 1. Selfsigned cert
log "Проверяем selfsigned.crt..."
ssh "${SSH_ALIAS}" "
  if [ ! -f /etc/nginx/ssl/selfsigned.crt ]; then
    echo '[cert] Создаём...'
    sudo mkdir -p /etc/nginx/ssl
    sudo openssl req -x509 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/selfsigned.key \
      -out    /etc/nginx/ssl/selfsigned.crt \
      -days 3650 -nodes \
      -subj '/CN=${DOMAIN}' \
      -addext 'subjectAltName=DNS:${DOMAIN}'
    echo '[cert] Готово.'
  else
    echo '[cert] OK — уже существует.'
  fi
"

# 2. Папка на сервере
log "Создаём папку на сервере..."
ssh "${SSH_ALIAS}" "sudo mkdir -p ${REMOTE_SITE} && sudo chown \$(whoami):\$(whoami) ${REMOTE_SITE}"

# 3. Загрузка файлов через scp
log "Загружаем файлы сайта через scp..."
scp -r /d/Gravity/alphaceiling/. "${SSH_ALIAS}:${REMOTE_SITE}/"
log "Файлы загружены."

# 4. Rate-limit zone
log "Создаём rate-limit zone..."
ssh "${SSH_ALIAS}" "echo 'limit_req_zone \$binary_remote_addr zone=site_rl:10m rate=10r/s;' | sudo tee ${NGINX_HTTP_CONF} > /dev/null"

# 5. Nginx конфиг
log "Создаём nginx конфиг..."
ssh "${SSH_ALIAS}" "sudo tee ${NGINX_SITE_CONF} > /dev/null" << NGINX_EOF
# reality-masquerade — nginx на порту 4433

# Ловушка: запросы без нашего Host → drop
server {
    listen 4433 ssl default_server;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    return 444;
}

# Основной блок: сайт для легитимных запросов
server {
    listen 4433 ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    server_tokens off;

    limit_req zone=site_rl burst=20 nodelay;
    limit_req_status 429;

    # Блокируем сканеры по User-Agent
    if (\$http_user_agent ~* "(curl|wget|python|go-http|zgrab|masscan|nmap|nikto|sqlmap|dirbuster|nuclei|metasploit|libwww|scanner)") {
        return 444;
    }

    # Разрешаем только безопасные методы
    if (\$request_method !~ ^(GET|HEAD|POST)\$) {
        return 444;
    }

    root ${REMOTE_SITE};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp)\$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    location ~* \.(css|js)\$ {
        expires 1d;
        add_header Cache-Control "public";
    }

    # Блокируем пути сканеров
    location ~* ^/(wp-admin|wp-login|\.env|\.git|\.htaccess|admin|phpmyadmin|xmlrpc\.php|cgi-bin) {
        return 444;
    }

    error_page 404 /index.html;
}
NGINX_EOF

# 6. Активируем и перезагружаем
log "Активируем конфиг nginx..."
ssh "${SSH_ALIAS}" "
  sudo ln -sf ${NGINX_SITE_CONF} /etc/nginx/sites-enabled/reality-masquerade
  sudo nginx -t && sudo systemctl reload nginx
  echo 'nginx перезагружен OK'
"

# 7. Финальная проверка
log "Финальная проверка..."
ssh "${SSH_ALIAS}" "
  echo '--- Порт 4433:'
  ss -tlnp | grep 4433 || echo 'ОШИБКА: 4433 не слушает'
  echo '--- Файлы сайта:'
  ls ${REMOTE_SITE}/ | head -6
"

echo ""
echo "✅ Деплой завершён! Сайт: https://${DOMAIN}:4433"
