#!/bin/bash
# Обновление списка российских IP-подсетей для split routing
# Источник: RIPE NCC (официальная база данных)
# Запуск: bash scripts/update-ru-cidr.sh
# Рекомендуется запускать раз в месяц.

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTING_DIR="${SCRIPT_DIR}/../routing"
CIDR_FILE="${ROUTING_DIR}/ru-cidr.txt"
TEMP_FILE=$(mktemp)

log "Загружаем список российских подсетей с RIPE NCC..."

# RIPE NCC Statistics — официальный источник
RIPE_URL="https://ftp.ripe.net/ripe/stats/delegated-ripencc-latest"
curl -sS --max-time 60 "$RIPE_URL" -o "$TEMP_FILE"

log "Парсим IPv4 блоки для RU..."

# Формат строки: ripencc|RU|ipv4|address|count|date|status
# Конвертируем count → CIDR нотацию
python3 << PYTHON
import math

blocks = []
with open('$TEMP_FILE') as f:
    for line in f:
        parts = line.strip().split('|')
        if len(parts) >= 5 and parts[1] == 'RU' and parts[2] == 'ipv4':
            addr  = parts[3]
            count = int(parts[4])
            # count — количество адресов, конвертируем в prefix length
            prefix = 32 - int(math.log2(count))
            blocks.append(f"{addr}/{prefix}")

blocks.sort()
with open('$CIDR_FILE', 'w') as f:
    f.write(f"# Российские IPv4 подсети (обновлено $(date '+%Y-%m-%d'))\n")
    f.write(f"# Источник: RIPE NCC | Блоков: {len(blocks)}\n")
    f.write("# Использование: split routing — эти адреса идут напрямую (без VPN)\n\n")
    f.write('\n'.join(blocks))
    f.write('\n')

print(f"[✓] Записано {len(blocks)} блоков в ru-cidr.txt")
PYTHON

rm -f "$TEMP_FILE"

COUNT=$(grep -c '^[0-9]' "$CIDR_FILE" || true)
log "Готово: ${COUNT} подсетей → ${CIDR_FILE}"

# Генерируем Shadowrocket-совместимый формат (IP-CIDR правила)
log "Генерируем Shadowrocket rules..."
SHADOWROCKET_RULES="${ROUTING_DIR}/ru-rules-shadowrocket.txt"
{
    echo "# Российские IP → DIRECT (для Shadowrocket)"
    echo "# Обновлено: $(date '+%Y-%m-%d')"
    echo ""
    grep '^[0-9]' "$CIDR_FILE" | awk '{print "IP-CIDR," $1 ",DIRECT"}'
} > "$SHADOWROCKET_RULES"

info "Shadowrocket rules: ${SHADOWROCKET_RULES} (${COUNT} правил)"
info "Для sing-box (Hiddify) используй geoip-ru.srs из профиля — он обновляется автоматически"
echo ""
log "Завершено. Следующее обновление — через ~30 дней."
