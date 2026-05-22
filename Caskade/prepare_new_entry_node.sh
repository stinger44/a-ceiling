#!/bin/bash
# prepare_new_entry_node.sh
# Запускать на НОВОМ YC сервере после SSH подключения.
# Разворачивает remnawave-node идентично node_e.
# Использование: bash prepare_new_entry_node.sh <NODE_API_KEY>

set -euo pipefail

NODE_API_KEY="${1:?Укажи NODE_API_KEY как первый аргумент}"
PANEL_URL="https://panelhide.su"
WORK_DIR="/root/remnawave-node"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Зависимости ---
log "Устанавливаем Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# --- Рабочая директория ---
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# --- .env файл ---
cat > .env <<EOF
# Remnawave Node — Entry (YC)
APP_PORT=2095
REMNAWAVE_PANEL_URL=${PANEL_URL}
NODE_API_KEY=${NODE_API_KEY}
EOF

log ".env создан"

# --- docker-compose.yml ---
cat > docker-compose.yml <<'EOF'
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

# --- Geo базы данных ---
log "Скачиваем geo-базы..."
curl -fsSL -o geoip.dat   "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
curl -fsSL -o geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

# --- nginx для Reality маскировки ---
log "Настраиваем nginx на порту 4433..."
apt-get install -y -q nginx

cat > /etc/nginx/sites-available/reality-mask <<'NGINX'
server {
    listen 4433 ssl;
    server_name alphaceiling23.ru;

    ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    location / {
        return 200 "ok";
        add_header Content-Type text/plain;
    }
}
NGINX

# Самоподписанный сертификат для nginx (Reality не проверяет его)
mkdir -p /etc/nginx/ssl
openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/ssl/selfsigned.key \
  -out /etc/nginx/ssl/selfsigned.crt -days 3650 -nodes \
  -subj "/CN=alphaceiling23.ru"

ln -sf /etc/nginx/sites-available/reality-mask /etc/nginx/sites-enabled/reality-mask
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# --- Запуск ---
log "Запускаем remnawave-node..."
docker compose pull
docker compose up -d

log "Готово! Проверь статус:"
echo "  docker logs remnawave-node --tail 30"
echo ""
echo "Затем добавь ноду в Remnawave панель и протестируй подключение."
