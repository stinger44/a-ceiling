#!/bin/bash
# setup_nginx_4433_yc.sh
# Настраивает nginx на yc сервере (111.88.249.82) для Reality маскировки.
# Reality отправляет "посторонних" наблюдателей на 127.0.0.1:4433 — 
# нужен любой TLS сервер. Сначала используем самоподписанный сертификат,
# после переключения DNS — заменим на Let's Encrypt.
#
# Запускать: ssh yc 'bash -s' < setup_nginx_4433_yc.sh

set -euo pipefail

DOMAIN="alphaceiling23.ru"
SSL_DIR="/etc/nginx/ssl"
NGINX_CONF="/etc/nginx/sites-available/reality-masquerade"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Создаём директорию SSL..."
sudo mkdir -p "$SSL_DIR"

# Самоподписанный сертификат — для Reality маскировки достаточно.
# Настоящие клиенты (с правильным Reality fingerprint) его не увидят.
log "Генерируем самоподписанный сертификат для ${DOMAIN}..."
sudo openssl req -x509 -newkey rsa:2048 \
  -keyout "${SSL_DIR}/selfsigned.key" \
  -out "${SSL_DIR}/selfsigned.crt" \
  -days 3650 -nodes \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN}"

log "Создаём nginx конфиг для порта 4433..."
sudo tee "$NGINX_CONF" > /dev/null <<EOF
# Reality masquerade endpoint
# Xray перенаправляет "посторонних" сюда — сервер выглядит как обычный HTTPS.
server {
    listen 4433 ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${SSL_DIR}/selfsigned.crt;
    ssl_certificate_key ${SSL_DIR}/selfsigned.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # Возвращаем пустую страницу — не важно что, главное TLS работает
    location / {
        return 200 "";
        add_header Content-Type text/plain;
    }
}
EOF

# Активируем конфиг
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/reality-masquerade

# Проверяем и перезапускаем
log "Проверяем конфиг nginx..."
sudo nginx -t

log "Перезапускаем nginx..."
sudo systemctl reload nginx

# Финальная проверка
log "Проверяем что порт 4433 слушает..."
ss -tlnp | grep 4433 && echo "OK: порт 4433 открыт" || echo "ОШИБКА: порт 4433 не слушает"

log "Готово! Порт 4433 настроен для Reality маскировки."
echo ""
echo "Следующий шаг: перезапустить remnawave-node для получения свежего конфига:"
echo "  sudo docker restart remnawave-node"
echo "  sudo docker logs remnawave-node --tail 30"
