#!/bin/bash
# migrate_entry_node.sh
# Мастер-скрипт миграции entry ноды node_e → yc.
# Запускать с ЛОКАЛЬНОЙ машины (Windows: Git Bash, WSL или аналог).
#
# Что делает:
#   Шаг 1 — Настраивает nginx 4433 на yc
#   Шаг 2 — Перезапускает remnawave-node на yc (получает свежий конфиг)
#   Шаг 3 — Тест подключения к yc напрямую (минуя DNS)
#   Шаг 4 — Инструкция по смене DNS в Cloudflare
#   Шаг 5 — Ждёт и проверяет распространение DNS
#   Шаг 6 — Финальная проверка

set -euo pipefail

OLD_IP="153.80.247.239"
NEW_IP="111.88.249.82"
DOMAIN="alphaceiling23.ru"
OLD_SSH="node_e"
NEW_SSH="yc"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[>>]${NC}  $*"; }
err()  { echo -e "${RED}[!!]${NC}  $*"; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Entry Node Migration: node_e → yc       ║"
echo "║  ${OLD_IP} → ${NEW_IP}       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── ШАГ 1: nginx 4433 на yc ────────────────────────────────────────────
warn "Шаг 1/5: Настраиваем nginx 4433 на yc сервере..."

if ssh "$NEW_SSH" "ss -tlnp | grep -q ':4433 '"; then
  ok "Порт 4433 уже слушает на yc — пропускаем"
else
  ssh "$NEW_SSH" 'bash -s' < setup_nginx_4433_yc.sh
  ok "nginx 4433 настроен"
fi
echo ""

# ── ШАГ 2: Перезапуск ноды на yc ──────────────────────────────────────
warn "Шаг 2/5: Перезапускаем remnawave-node на yc (получаем свежий конфиг)..."
ssh "$NEW_SSH" "sudo docker restart remnawave-node"
sleep 5
ssh "$NEW_SSH" "sudo docker logs remnawave-node --tail 20 2>&1"
ok "Нода перезапущена"
echo ""

# ── ШАГ 3: Тест без смены DNS ──────────────────────────────────────────
warn "Шаг 3/5: Тест подключения к yc напрямую по IP..."
echo "  (используем curl --resolve чтобы обойти DNS)"

HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
  --resolve "${DOMAIN}:443:${NEW_IP}" \
  --connect-timeout 10 \
  "https://${DOMAIN}/" || echo "FAIL")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
  ok "yc сервер отвечает на 443 (HTTP $HTTP_CODE) ✓"
elif [ "$HTTP_CODE" = "FAIL" ]; then
  warn "Curl не подключился — это нормально если Reality не возвращает HTTP"
  warn "Критично: remnawave-node должен показывать VLESS_YC_ENTRY в логах выше"
else
  warn "HTTP код: $HTTP_CODE — проверь логи выше"
fi
echo ""

# ── ШАГ 4: Инструкция DNS ──────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ДЕЙСТВИЕ: Смени A запись в Cloudflare                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                           ║"
echo "║  1. Открой: dash.cloudflare.com                          ║"
echo "║  2. Домен: ${DOMAIN}                       ║"
echo "║  3. DNS → Records → найди A запись                       ║"
echo "║  4. Измени IP: ${OLD_IP} → ${NEW_IP}       ║"
echo "║  5. TTL: 60 секунд  (Auto или минимум)                   ║"
echo "║  6. Прокси (оранжевое облако): ВЫКЛЮЧИТЬ (только DNS)    ║"
echo "║                                                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
read -r -p "Нажми Enter когда A запись изменена → "

# ── ШАГ 5: Ждём DNS ────────────────────────────────────────────────────
warn "Шаг 4/5: Ждём распространения DNS..."
MAX_WAIT=120
ELAPSED=0
RESOLVED=""

while [ $ELAPSED -lt $MAX_WAIT ]; do
  RESOLVED=$(nslookup "$DOMAIN" 8.8.8.8 2>/dev/null \
    | awk '/^Address: / && !/8\.8\.8\./ {print $2}' | head -1 || echo "")

  if [ "$RESOLVED" = "$NEW_IP" ]; then
    ok "DNS обновился: ${DOMAIN} → ${NEW_IP} ✓"
    break
  fi
  echo "    Текущий IP: ${RESOLVED:-пусто} (ждём ${NEW_IP})..."
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ "$RESOLVED" != "$NEW_IP" ]; then
  warn "DNS ещё не обновился. Подожди 1-2 минуты и проверь:"
  warn "  nslookup ${DOMAIN} 8.8.8.8"
fi
echo ""

# ── ШАГ 6: Финальная проверка ──────────────────────────────────────────
warn "Шаг 5/5: Финальная проверка после DNS..."
echo ""

echo "Логи yc ноды:"
ssh "$NEW_SSH" "sudo docker logs remnawave-node --tail 10 2>&1"
echo ""

echo "Статус старой ноды (должна быть жива для отката):"
ssh "$OLD_SSH" "docker ps --filter name=remnawave-node --format 'Status: {{.Status}}'" 2>/dev/null || echo "  node_e недоступна"
echo ""

ok "Миграция завершена!"
echo ""
echo "════════════════════════════════════════════"
echo "  Оставь node_e запущенной ещё 30 минут."
echo "  Если что-то не так — запусти:"
echo "    bash rollback_entry_node.sh"
echo "════════════════════════════════════════════"
