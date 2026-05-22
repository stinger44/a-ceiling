#!/bin/bash
# Диагностика всех слоёв VPN
# Запуск: bash scripts/check-layers.sh
#
# Покажет статус каждого уровня + задержку

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

VPS_IP="${VPS_IP:-}"
RELAY_IP="${RELAY_IP:-}"
DOMAIN="${DOMAIN:-}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

# Проверяет доступность хоста и возвращает пинг в мс
check_ping() {
    local host="$1"
    local result
    result=$(ping -c 3 -W 3 "$host" 2>/dev/null | grep -oP 'avg.*?\K[\d.]+(?=/)' || echo "")
    echo "${result:-timeout}"
}

# Проверяет доступность TCP-порта
check_tcp() {
    local host="$1" port="$2"
    timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null && echo "open" || echo "closed"
}

echo ""
echo "════════════════════════════════════════════════"
echo "  VPN Layer Diagnostics — $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════"
echo ""

# ─── Локальная сеть ───────────────────────────────────────────────────────────
echo "🌐 Локальная сеть:"
MY_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "недоступен")
info "Ваш IP: ${MY_IP}"

# ─── Layer 0: VPS Finland ─────────────────────────────────────────────────────
echo ""
echo "Layer 0 — VLESS Reality (VPS Финляндия):"
if [[ -z "$VPS_IP" ]]; then
    warn "VPS_IP не задан в .env"
else
    PING_L0=$(check_ping "$VPS_IP")
    TCP_443=$(check_tcp "$VPS_IP" 443)
    TCP_8443=$(check_tcp "$VPS_IP" 8443)

    [[ "$PING_L0" != "timeout" ]] && ok "ping: ${PING_L0}ms" || fail "ping: недостижим"
    [[ "$TCP_443" == "open" ]]    && ok "port 443: открыт" || fail "port 443: закрыт"
    [[ "$TCP_8443" == "open" ]]   && ok "port 8443: открыт (резерв)" || warn "port 8443: закрыт"
fi

# ─── Layer 1: Cloudflare CDN ──────────────────────────────────────────────────
echo ""
echo "Layer 1 — Cloudflare CDN:"
if [[ -z "$DOMAIN" ]]; then
    warn "DOMAIN не задан в .env"
else
    CF_DOMAIN="vpn.${DOMAIN}"
    CF_IP=$(dig +short "$CF_DOMAIN" 2>/dev/null | tail -1 || echo "")
    TCP_CF=$(check_tcp "$CF_DOMAIN" 443 2>/dev/null || echo "closed")

    [[ -n "$CF_IP" ]] && ok "DNS: ${CF_DOMAIN} → ${CF_IP}" || fail "DNS: ${CF_DOMAIN} не резолвится"
    [[ "$TCP_CF" == "open" ]] && ok "HTTPS/WebSocket: доступен" || fail "HTTPS/WebSocket: недоступен"

    # Проверяем что это действительно Cloudflare
    CF_SERVER=$(curl -sI --max-time 5 "https://${CF_DOMAIN}" 2>/dev/null | grep -i server | head -1 || echo "")
    [[ "$CF_SERVER" == *cloudflare* ]] && ok "Cloudflare proxy: активен" || warn "Cloudflare proxy: не обнаружен"
fi

# ─── Layer 2: Yandex Cloud Relay ─────────────────────────────────────────────
echo ""
echo "Layer 2 — Relay Yandex Cloud:"
if [[ -z "$RELAY_IP" ]]; then
    warn "RELAY_IP не задан в .env (relay не задеплоен?)"
else
    PING_L2=$(check_ping "$RELAY_IP")
    TCP_R443=$(check_tcp "$RELAY_IP" 443)

    [[ "$PING_L2" != "timeout" ]] && ok "ping: ${PING_L2}ms" || fail "ping: недостижим"
    [[ "$TCP_R443" == "open" ]]   && ok "port 443 (Xray relay): открыт" || fail "port 443: закрыт"

    # Проверяем что это Yandex Cloud IP
    YC_ASN=$(curl -s --max-time 5 "https://ipapi.co/${RELAY_IP}/org/" 2>/dev/null || echo "")
    [[ "$YC_ASN" == *Yandex* || "$YC_ASN" == *yandex* ]] && \
        ok "ASN: Yandex Cloud (в белом списке ✓)" || \
        info "ASN: ${YC_ASN}"
fi

# ─── Layer 3: WebRTC Server ───────────────────────────────────────────────────
echo ""
echo "Layer 3 — WebRTC Tunnel (аварийный):"
WEBRTC_PORT="${TUNNEL_PORT:-8765}"
if [[ -n "$VPS_IP" ]]; then
    TCP_WRT=$(check_tcp "$VPS_IP" "$WEBRTC_PORT")
    [[ "$TCP_WRT" == "open" ]] && \
        ok "WebRTC сервер: запущен (port ${WEBRTC_PORT})" || \
        warn "WebRTC сервер: не запущен (Layer 3 не активирован, это нормально)"
else
    warn "VPS_IP не задан"
fi

# ─── 3X-UI панель ─────────────────────────────────────────────────────────────
echo ""
echo "3X-UI панель:"
PANEL_PORT="${PANEL_PORT:-54321}"
if [[ -n "$VPS_IP" ]]; then
    TCP_PANEL=$(check_tcp "$VPS_IP" "$PANEL_PORT")
    [[ "$TCP_PANEL" == "open" ]] && \
        ok "Панель доступна: http://${VPS_IP}:${PANEL_PORT}" || \
        fail "Панель недоступна (port ${PANEL_PORT} закрыт)"
fi

# ─── Итог ─────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo "  Готово! Если Layer 0 и Layer 2 ОК — VPN рабочий."
echo "════════════════════════════════════════════════"
echo ""
