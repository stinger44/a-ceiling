#!/bin/bash
# Установка Xray + 3X-UI на VPS (Ubuntu 22.04 / Debian 12)
# Запускать от root: bash install.sh
#
# После установки все credentials будут в ~/vpn-credentials.txt

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Параметры панели (можно переопределить через env)
PANEL_PORT="${PANEL_PORT:-54321}"
PANEL_USER="${PANEL_USER:-admin}"
PANEL_PASS="${PANEL_PASS:-$(openssl rand -hex 12)}"

[[ $EUID -ne 0 ]] && die "Запускать только от root"
command -v curl &>/dev/null || apt-get install -y curl &>/dev/null

log "[1/6] Обновление системы..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq ufw openssl curl wget

log "[2/6] Включение BBR (Google congestion control)..."
# BBR даёт прирост скорости в 2-3x на мобильных сетях
cat > /etc/sysctl.d/99-vpn-bbr.conf << 'EOF'
# BBR — управление перегрузками от Google
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Увеличение буферов сокетов
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# TCP оптимизации
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
EOF
sysctl --system -q
# Проверка что BBR включён
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control)
[[ "$CURRENT_CC" == "bbr" ]] && log "BBR активен" || warn "BBR не применился (ядро < 4.9?)"

log "[3/6] Настройка firewall (UFW)..."
ufw allow 22/tcp    comment "SSH"
ufw allow 443/tcp   comment "VLESS Reality (основной)"
ufw allow 8443/tcp  comment "VLESS Reality (резерв Google)"
ufw allow 2053/tcp  comment "VLESS WebSocket (Cloudflare CDN)"
ufw allow "${PANEL_PORT}/tcp" comment "3X-UI панель"
ufw --force enable
log "UFW активен: $(ufw status | grep Status)"

log "[4/6] Установка 3X-UI..."
# Автоматическая установка без интерактивного ввода
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) \
    --username "$PANEL_USER" \
    --password "$PANEL_PASS" \
    --port "$PANEL_PORT" <<< ""
# Убедимся что сервис запущен
systemctl enable x-ui --quiet
systemctl start x-ui

log "[5/6] Генерация Reality ключей..."
# xray встроен в 3X-UI, используем его для генерации ключей
XRAY_BIN="/usr/local/x-ui/bin/xray"
[[ ! -f "$XRAY_BIN" ]] && XRAY_BIN=$(which xray 2>/dev/null || echo "")
[[ -z "$XRAY_BIN" ]] && die "xray не найден после установки 3X-UI"

KEYPAIR=$("$XRAY_BIN" x25519 2>/dev/null)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/Private key/ {print $NF}')
PUBLIC_KEY=$(echo "$KEYPAIR"  | awk '/Public key/  {print $NF}')
UUID=$("$XRAY_BIN" uuid 2>/dev/null)
SHORT_ID=$(openssl rand -hex 8)
VPS_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

log "[6/6] Сохранение credentials..."
cat > ~/vpn-credentials.txt << EOF
# VPN Credentials — $(date '+%Y-%m-%d %H:%M:%S')
# ХРАНИ ЭТОТ ФАЙЛ В БЕЗОПАСНОМ МЕСТЕ!

VPS_IP=${VPS_IP}
VLESS_UUID=${UUID}
REALITY_PRIVATE_KEY=${PRIVATE_KEY}
REALITY_PUBLIC_KEY=${PUBLIC_KEY}
REALITY_SHORT_ID=${SHORT_ID}

PANEL_URL=http://${VPS_IP}:${PANEL_PORT}
PANEL_USER=${PANEL_USER}
PANEL_PASS=${PANEL_PASS}
EOF
chmod 600 ~/vpn-credentials.txt

# VLESS-ссылки для прямого импорта
VLESS_L0="vless://${UUID}@${VPS_IP}:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision&type=tcp#Layer0-Finland-443"
VLESS_L0B="vless://${UUID}@${VPS_IP}:8443?security=reality&sni=dl.google.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision&type=tcp#Layer0-Finland-8443"

echo ""
echo "════════════════════════════════════════════════"
echo "  ✅  Установка завершена!"
echo "════════════════════════════════════════════════"
echo ""
echo "  Панель 3X-UI:"
echo "  URL:      http://${VPS_IP}:${PANEL_PORT}"
echo "  Логин:    ${PANEL_USER}"
echo "  Пароль:   ${PANEL_PASS}"
echo ""
echo "  VLESS Reality ключи:"
echo "  UUID:         ${UUID}"
echo "  Public Key:   ${PUBLIC_KEY}"
echo "  Short ID:     ${SHORT_ID}"
echo ""
echo "  Готовые VLESS-ссылки (импортируй в Hiddify):"
echo "  ${VLESS_L0}"
echo "  ${VLESS_L0B}"
echo ""
echo "  Все данные сохранены в ~/vpn-credentials.txt"
echo ""
echo "  Следующий шаг:"
echo "  Открой панель и создай inbound-ы согласно README.md"
echo "════════════════════════════════════════════════"
