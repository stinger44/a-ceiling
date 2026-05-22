#!/bin/bash
# Генерация ключей для VLESS Reality
# Запуск: bash scripts/generate-keys.sh
# Требует: xray-core локально, или docker

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

echo ""
echo "════════════════════════════════════════════════"
echo "  Генерация VLESS Reality ключей"
echo "════════════════════════════════════════════════"
echo ""

# Ищем xray в стандартных местах
XRAY_BIN=""
for candidate in \
    /usr/local/x-ui/bin/xray \
    /usr/local/bin/xray \
    "$(which xray 2>/dev/null)"; do
    [[ -f "$candidate" ]] && XRAY_BIN="$candidate" && break
done

if [[ -z "$XRAY_BIN" ]]; then
    info "xray не найден локально, используем Docker..."
    if command -v docker &>/dev/null; then
        XRAY_CMD="docker run --rm ghcr.io/xtls/xray-core:latest"
    else
        echo -e "${YELLOW}[!]${NC} Установи xray или Docker, затем повтори."
        echo "    Установка xray: bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"
        exit 1
    fi
else
    XRAY_CMD="$XRAY_BIN"
    log "Используем xray: $XRAY_BIN"
fi

# Генерация основных ключей (VPS)
log "Генерация ключей для VPS (Layer 0)..."
KEYPAIR=$($XRAY_CMD x25519 2>/dev/null)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/Private key/ {print $NF}')
PUBLIC_KEY=$(echo  "$KEYPAIR" | awk '/Public key/  {print $NF}')
UUID=$($XRAY_CMD uuid 2>/dev/null)
SHORT_ID=$(openssl rand -hex 8)

# Генерация ключей для relay (Yandex Cloud)
log "Генерация ключей для relay VM (Layer 2)..."
RELAY_KEYPAIR=$($XRAY_CMD x25519 2>/dev/null)
RELAY_PRIVATE=$(echo "$RELAY_KEYPAIR" | awk '/Private key/ {print $NF}')
RELAY_PUBLIC=$( echo "$RELAY_KEYPAIR" | awk '/Public key/  {print $NF}')
RELAY_UUID=$($XRAY_CMD uuid 2>/dev/null)
RELAY_SHORT_ID=$(openssl rand -hex 8)

echo ""
echo "════════════════════════════════════════════════"
echo "  VPS (Layer 0) — основной сервер"
echo "════════════════════════════════════════════════"
echo ""
echo "  VLESS_UUID=${UUID}"
echo "  REALITY_PRIVATE_KEY=${PRIVATE_KEY}"
echo "  REALITY_PUBLIC_KEY=${PUBLIC_KEY}"
echo "  REALITY_SHORT_ID=${SHORT_ID}"
echo ""
echo "════════════════════════════════════════════════"
echo "  Relay VM (Layer 2) — Yandex Cloud"
echo "════════════════════════════════════════════════"
echo ""
echo "  RELAY_VLESS_UUID=${RELAY_UUID}"
echo "  RELAY_REALITY_PRIVATE_KEY=${RELAY_PRIVATE}"
echo "  RELAY_REALITY_PUBLIC_KEY=${RELAY_PUBLIC}"
echo "  RELAY_REALITY_SHORT_ID=${RELAY_SHORT_ID}"
echo ""

# Сохраняем в файл
OUTPUT_FILE="$(dirname "${BASH_SOURCE[0]}")/../generated-keys.txt"
cat > "$OUTPUT_FILE" << EOF
# Сгенерировано: $(date '+%Y-%m-%d %H:%M:%S')
# ХРАНИ В БЕЗОПАСНОМ МЕСТЕ! Не коммить в git!

# VPS (Layer 0)
VLESS_UUID=${UUID}
REALITY_PRIVATE_KEY=${PRIVATE_KEY}
REALITY_PUBLIC_KEY=${PUBLIC_KEY}
REALITY_SHORT_ID=${SHORT_ID}

# Relay VM (Layer 2)
RELAY_VLESS_UUID=${RELAY_UUID}
RELAY_REALITY_PRIVATE_KEY=${RELAY_PRIVATE}
RELAY_REALITY_PUBLIC_KEY=${RELAY_PUBLIC}
RELAY_REALITY_SHORT_ID=${RELAY_SHORT_ID}
EOF
chmod 600 "$OUTPUT_FILE"
echo "  Ключи сохранены в: generated-keys.txt"
echo "  Скопируй их в .env!"
echo ""

# Готовые VLESS-ссылки
echo "════════════════════════════════════════════════"
echo "  VLESS-ссылки (после заполнения VPS_IP)"
echo "════════════════════════════════════════════════"
echo ""
VPS_IP="${VPS_IP:-YOUR_VPS_IP}"
RELAY_IP="${RELAY_IP:-YOUR_RELAY_IP}"
echo "  Layer 0:"
echo "  vless://${UUID}@${VPS_IP}:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision&type=tcp#Layer0-Finland"
echo ""
echo "  Layer 0 (резерв):"
echo "  vless://${UUID}@${VPS_IP}:8443?security=reality&sni=dl.google.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision&type=tcp#Layer0-Finland-Backup"
echo ""
echo "  Layer 2 (relay):"
echo "  vless://${RELAY_UUID}@${RELAY_IP}:443?security=reality&sni=ya.ru&fp=chrome&pbk=${RELAY_PUBLIC}&sid=${RELAY_SHORT_ID}&flow=xtls-rprx-vision&type=tcp#Layer2-YandexCloud"
echo ""
