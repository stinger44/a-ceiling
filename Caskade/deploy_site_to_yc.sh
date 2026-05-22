#!/bin/bash
# deploy_site_to_yc.sh
# Заливает сайт alphaceiling на entry ноду (yc, 111.88.249.82)
# и настраивает nginx с защитой от active probing.
#
# Запускать локально: bash deploy_site_to_yc.sh
#
# Что делает:
#   1. rsync — синхронизирует файлы сайта на сервер
#   2. SSH   — создаёт nginx конфиг с anti-probing защитой
#   3. Перезагружает nginx

set -euo pipefail

SSH_ALIAS="yc"
DOMAIN="alphaceiling23.ru"
LOCAL_SITE="D:/Gravity/alphaceiling/"
REMOTE_SITE="/var/www/alphaceiling"
SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
NGINX_SITE_CONF="/etc/nginx/sites-available/reality-masquerade"
NGINX_HTTP_CONF="/etc/nginx/conf.d/rate_limit.conf"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. Проверяем / создаём самоподписанный сертификат для default_server
# ─────────────────────────────────────────────────────────────────────────────
log "Проверяем самоподписанный сертификат..."
ssh "${SSH_ALIAS}" "
  if [ ! -f /etc/nginx/ssl/selfsigned.crt ]; then
    echo '[cert] Сертификат не найден — создаём...'
    sudo mkdir -p /etc/nginx/ssl
    sudo openssl req -x509 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/selfsigned.key \
      -out    /etc/nginx/ssl/selfsigned.crt \
      -days 3650 -nodes \
      -subj '/CN=${DOMAIN}' \
      -addext 'subjectAltName=DNS:${DOMAIN}'
    echo '[cert] Готово: /etc/nginx/ssl/selfsigned.crt'
  else
    echo '[cert] OK: /etc/nginx/ssl/selfsigned.crt уже существует'
  fi
"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Синхронизируем файлы сайта
# ─────────────────────────────────────────────────────────────────────────────
log "Создаём папку на сервере..."
ssh "${SSH_ALIAS}" "sudo mkdir -p ${REMOTE_SITE} && sudo chown \$(whoami):\$(whoami) ${REMOTE_SITE}"

log "Синхронизируем сайт → ${SSH_ALIAS}:${REMOTE_SITE} ..."
rsync -avz --delete \
  --exclude='*.DS_Store' \
  --exclude='Thumbs.db' \
  -e ssh \
  "${LOCAL_SITE}" \
  "${SSH_ALIAS}:${REMOTE_SITE}/"

log "Файлы загружены."

# ─────────────────────────────────────────────────────────────────────────────
# 3. Rate-limit zone в http-контексте (conf.d загружается в http {})
# ─────────────────────────────────────────────────────────────────────────────
log "Создаём rate-limit zone..."
ssh "${SSH_ALIAS}" "sudo tee ${NGINX_HTTP_CONF} > /dev/null" << 'RATE_EOF'
# Rate limiting: объявляется в http-контексте, используется в server-блоках.
limit_req_zone $binary_remote_addr zone=site_rl:10m rate=10r/s;
RATE_EOF

# ─────────────────────────────────────────────────────────────────────────────
# 3. Nginx конфиг с anti-probing защитой
# ─────────────────────────────────────────────────────────────────────────────
log "Создаём nginx конфиг..."
ssh "${SSH_ALIAS}" "sudo tee ${NGINX_SITE_CONF} > /dev/null" << NGINX_EOF
# reality-masquerade — nginx на порту 4433
# Reality (Xray) перенаправляет сюда «посторонних» наблюдателей.
# Конфиг имитирует обычный HTTPS-сайт компании по натяжным потолкам.

# ── Блок-ловушка: все запросы без нашего Host или с чужим Host ───────────────
# default_server перехватывает всё, что не попало в основной блок.
server {
    listen 4433 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    # 444 = close connection without response (nginx-специфично, лучший drop)
    return 444;
}

# ── Основной блок: легитимный трафик с правильным Host ───────────────────────
server {
    listen 4433 ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    # Скрываем версию nginx
    server_tokens off;

    # Rate limiting (zone объявлена в /etc/nginx/conf.d/rate_limit.conf)
    limit_req zone=site_rl burst=20 nodelay;
    limit_req_status 429;

    # Блокируем сканеры по User-Agent
    if (\$http_user_agent ~* "(curl|wget|python-requests|python|go-http|zgrab|masscan|nmap|nikto|sqlmap|dirbuster|nuclei|metasploit|libwww|scanner)") {
        return 444;
    }

    # Разрешаем только безопасные методы
    if (\$request_method !~ ^(GET|HEAD|POST)$) {
        return 444;
    }

    # Корень сайта
    root ${REMOTE_SITE};
    index index.html;

    # Основные страницы
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Изображения — долгий кэш
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    # JS/CSS — средний кэш
    location ~* \.(css|js)$ {
        expires 1d;
        add_header Cache-Control "public";
    }

    # Блокируем популярные пути сканеров
    location ~* ^/(wp-admin|wp-login|\.env|\.git|\.htaccess|admin|phpmyadmin|xmlrpc\.php|cgi-bin) {
        return 444;
    }

    # 404 → главная (SPA-стиль, корректно для многостраничного сайта)
    error_page 404 /index.html;
}
NGINX_EOF

# ─────────────────────────────────────────────────────────────────────────────
# 4. Активируем конфиг и перезагружаем nginx
# ─────────────────────────────────────────────────────────────────────────────
log "Активируем конфиг..."
ssh "${SSH_ALIAS}" "
  sudo ln -sf ${NGINX_SITE_CONF} /etc/nginx/sites-enabled/reality-masquerade
  echo '--- Проверка конфига nginx:'
  sudo nginx -t
  echo '--- Перезагружаем nginx:'
  sudo systemctl reload nginx
  echo 'OK: nginx перезагружен'
"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Финальная проверка
# ─────────────────────────────────────────────────────────────────────────────
log "Финальная проверка..."
ssh "${SSH_ALIAS}" "
  echo '--- Порт 4433 слушает:'
  ss -tlnp | grep 4433 || echo 'ОШИБКА: порт не слушает'
  echo '--- Файлы сайта (первые 5):'
  ls ${REMOTE_SITE}/ | head -5
  echo '--- Проверяем самоподписанный сертификат:'
  ls /etc/nginx/ssl/selfsigned.crt && echo 'cert OK' || echo 'ОШИБКА: selfsigned.crt не найден'
"

echo ""
echo "✅ Деплой завершён!"
echo ""
echo "   Сайт:     https://${DOMAIN}:4433"
echo ""
echo "   Anti-probing защита:"
echo "   ├── Запросы без Host=${DOMAIN}   → 444 (drop)"
echo "   ├── Сканеры по User-Agent         → 444"
echo "   ├── Нестандартные HTTP методы     → 444"
echo "   ├── Служебные пути (/wp-, /.env)  → 444"
echo "   └── Rate limit: 10 req/s / IP     → 429"
echo ""
echo "   Reality маскировка:"
echo "   └── Легитимный клиент → Xray обрабатывает до nginx"
echo "       Посторонний       → nginx:4433 → сайт потолков"
