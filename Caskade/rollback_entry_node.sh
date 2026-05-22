#!/bin/bash
# rollback_entry_node.sh
# Быстрый откат: возвращает трафик на node_e (153.80.247.239).
# Запускать с локальной машины если что-то пошло не так после миграции.
# Время отката: ~60 секунд (TTL в Cloudflare).

set -euo pipefail

OLD_IP="153.80.247.239"
OLD_SSH="node_e"
DOMAIN="alphaceiling23.ru"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[>>]${NC}  $*"; }
err()  { echo -e "${RED}[!!]${NC}  $*"; }

echo ""
echo -e "${RED}╔══════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ROLLBACK: Возврат на node_e             ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Шаг 1: Проверить что node_e запущена ───────────────────────────────
warn "Проверяем node_e (${OLD_IP})..."

STATUS=$(ssh -o ConnectTimeout=5 "$OLD_SSH" \
  "docker ps --filter name=remnawave-node --format '{{.Status}}'" 2>/dev/null || echo "")

if echo "$STATUS" | grep -qi "up"; then
  ok "node_e запущена и работает: $STATUS"
else
  warn "node_e не запущена — запускаем..."
  ssh "$OLD_SSH" "cd /root/remnawave-node && docker compose up -d" 2>/dev/null \
    || ssh "$OLD_SSH" "docker start remnawave-node"
  sleep 3
  STATUS=$(ssh "$OLD_SSH" "docker ps --filter name=remnawave-node --format '{{.Status}}'")
  if echo "$STATUS" | grep -qi "up"; then
    ok "node_e запущена: $STATUS"
  else
    err "Не удалось запустить node_e! Проверь вручную: ssh ${OLD_SSH}"
    exit 1
  fi
fi
echo ""

# ── Шаг 2: Инструкция по откату DNS ───────────────────────────────────
echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ДЕЙСТВИЕ: Верни A запись в Cloudflare                   ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}║  1. Открой: dash.cloudflare.com                          ║${NC}"
echo -e "${RED}║  2. Домен: ${DOMAIN}                       ║${NC}"
echo -e "${RED}║  3. DNS → Records → A запись                             ║${NC}"
echo -e "${RED}║  4. Верни IP: ${OLD_IP}                   ║${NC}"
echo -e "${RED}║  5. TTL: 60 секунд                                       ║${NC}"
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
read -r -p "Нажми Enter когда A запись изменена обратно → "

# ── Шаг 3: Ждём DNS ────────────────────────────────────────────────────
warn "Ждём обновления DNS (до 90 сек)..."
MAX_WAIT=90; ELAPSED=0; RESOLVED=""

while [ $ELAPSED -lt $MAX_WAIT ]; do
  RESOLVED=$(nslookup "$DOMAIN" 8.8.8.8 2>/dev/null \
    | awk '/^Address: / && !/8\.8\.8\./ {print $2}' | head -1 || echo "")

  if [ "$RESOLVED" = "$OLD_IP" ]; then
    ok "DNS вернулся: ${DOMAIN} → ${OLD_IP} ✓"
    break
  fi
  echo "    Текущий IP: ${RESOLVED:-пусто} (ждём ${OLD_IP})..."
  sleep 5; ELAPSED=$((ELAPSED + 5))
done

if [ "$RESOLVED" != "$OLD_IP" ]; then
  warn "DNS ещё не обновился. Подожди немного и проверь:"
  echo "  nslookup ${DOMAIN} 8.8.8.8"
fi
echo ""

# ── Шаг 4: Проверка логов ──────────────────────────────────────────────
warn "Логи node_e (последние 10 строк):"
ssh "$OLD_SSH" "docker logs remnawave-node --tail 10" 2>&1 || true
echo ""

ok "Откат завершён."
echo ""
echo "Проверь в Remnawave панели:"
echo "  → panelhide.su → Nodes → Списки — статус Online"
echo ""
echo "Если нода Offline → нажми Reconnect в панели."
