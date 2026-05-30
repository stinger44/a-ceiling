#!/bin/bash
# setup_ru_entry_node.sh
# Настройка нового российского сервера как ВХОДНОЙ НОДЫ каскада.
# Запускается удалённо через: bash setup_ru_entry_node.sh <NODE_API_KEY>
#
# Что делает:
# 1. Устанавливает Docker
# 2. Разворачивает remnawave-node (входная нода)
# 3. Настраивает nginx для alphaceiling23.ru (маскировочный сайт на 80/443)
# 4. Выдаёт geo-базы данных

set -euo pipefail

NODE_API_KEY="${1:?Укажи NODE_API_KEY первым аргументом}"
PANEL_URL="https://panelhide.su"
WORK_DIR="/root/remnawave-node"
SITE_DIR="/var/www/alphaceiling23.ru"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ─── Docker ────────────────────────────────────────────────────────────────
log "Проверяем Docker..."
if ! command -v docker &>/dev/null; then
  log "Устанавливаем Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# ─── nginx ─────────────────────────────────────────────────────────────────
log "Устанавливаем nginx и certbot..."
apt-get update -qq
apt-get install -y -q nginx certbot python3-certbot-nginx

# Директория для сайта
mkdir -p "$SITE_DIR"

# Конфиг nginx для alphaceiling23.ru (порт 80 + 443 TLS через certbot)
cat > /etc/nginx/sites-available/alphaceiling23.ru << 'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name alphaceiling23.ru www.alphaceiling23.ru;

    root /var/www/alphaceiling23.ru;
    index index.html;

    # Для выдачи сертификата Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/alphaceiling23.ru;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Сжатие
    gzip on;
    gzip_types text/plain text/css application/javascript image/svg+xml;
}
NGINX

# Активируем и перезапускаем nginx
ln -sf /etc/nginx/sites-available/alphaceiling23.ru /etc/nginx/sites-enabled/alphaceiling23.ru
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl restart nginx

log "nginx настроен"

# ─── Remnawave Node ─────────────────────────────────────────────────────────
log "Создаём remnawave-node..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

cat > .env << EOF
# Remnawave Node — Entry RU
APP_PORT=2095
REMNAWAVE_PANEL_URL=${PANEL_URL}
NODE_API_KEY=${NODE_API_KEY}
EOF

cat > docker-compose.yml << 'EOF'
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnawave-node
    restart: always
    network_mode: host
    env_file:
      - .env
    volumes:
      - ./geoip.dat:/usr/local/bin/geoip.dat:ro
      - ./geosite.dat:/usr/local/bin/geosite.dat:ro
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

# ─── Geo базы ───────────────────────────────────────────────────────────────
log "Скачиваем geo-базы..."
curl -fsSL -o geoip.dat   "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
curl -fsSL -o geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

# ─── Запуск ноды ────────────────────────────────────────────────────────────
log "Запускаем remnawave-node..."
docker compose pull
docker compose up -d

log "✅ Готово!"
echo ""
echo "Следующие шаги:"
echo "  1. Загрузи файлы сайта в $SITE_DIR"
echo "  2. Получи TLS-сертификат: certbot --nginx -d alphaceiling23.ru -d www.alphaceiling23.ru"
echo "  3. Добавь ноду в панель Remnawave (тип: ENTRY)"
echo "  4. Проверь ноду: docker logs remnawave-node --tail 30"
