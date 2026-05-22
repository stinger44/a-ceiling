#!/usr/bin/env bash
# =============================================================
# Caskade VPN — Master Deploy Script
# Развёртывание каскадной VPN инфраструктуры
#
# Архитектура:
#   Клиент → node_e:443 (VLESS Reality) → node_d:2223 (VLESS) → Интернет
#
# Использование:
#   bash deploy.sh [all|transit|panel|firewall]
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Загрузка конфигурации из .env ─────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
[[ -f "$ENV_FILE" ]] || { echo "[✗] Файл .env не найден! Скопируй .env.example → .env и заполни." >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a

log()  { echo -e "\033[32m[+]\033[0m $*"; }
warn() { echo -e "\033[33m[!]\033[0m $*"; }
die()  { echo -e "\033[31m[✗]\033[0m $*" >&2; exit 1; }

# ── Шаг 1: Развернуть transit Xray на node_d ─────────────────
deploy_transit() {
    log "Развёртывание transit Xray на $NODE_D_HOST ($NODE_D_IP)..."

    # Создать директорию
    ssh "$NODE_D_HOST" "mkdir -p $TRANSIT_DIR"

    # Загрузить конфиг и compose
    scp "$SCRIPT_DIR/transit_xray_config.json" "$NODE_D_HOST:$TRANSIT_DIR/transit-config.json"
    scp "$SCRIPT_DIR/transit_docker_compose.yml" "$NODE_D_HOST:$TRANSIT_DIR/docker-compose.yml"

    # Запустить контейнер
    ssh "$NODE_D_HOST" "cd $TRANSIT_DIR && docker compose up -d"

    # Проверить
    sleep 3
    local port_check
    port_check=$(ssh "$NODE_D_HOST" "ss -tlnp | grep $TRANSIT_PORT | wc -l")
    if [[ "$port_check" -gt 0 ]]; then
        log "Transit Xray запущен, порт $TRANSIT_PORT слушается ✅"
    else
        die "Transit Xray не запустился! Проверь: ssh $NODE_D_HOST 'docker logs xray-transit'"
    fi
}

# ── Шаг 2: Открыть порт 2223 в фаерволе node_d ───────────────
deploy_firewall() {
    log "Открываю порт $TRANSIT_PORT в UFW на $NODE_D_HOST..."
    ssh "$NODE_D_HOST" "ufw allow $TRANSIT_PORT/tcp && ufw allow $TRANSIT_PORT/udp" || true
    log "UFW обновлён ✅"
}

# ── Шаг 3: Настроить панель Remnawave ────────────────────────
deploy_panel() {
    log "Настройка Remnawave панели ($REMNA_HOST)..."

    # Загрузить SQL на сервер
    scp "$SCRIPT_DIR/panel_setup.sql" "$REMNA_HOST:/tmp/caskade_panel_setup.sql"

    # Выполнить SQL
    ssh "$REMNA_HOST" "docker exec -i remnawave-db psql -U postgres -d postgres < /tmp/caskade_panel_setup.sql"

    log "Конфигурация панели применена ✅"

    # Перезапустить node_e чтобы подхватить новый конфиг
    log "Перезапуск node_e для применения конфига..."
    ssh "$NODE_E_HOST" "docker restart remnawave-node"
    sleep 10

    # Проверить что Xray видит пользователей
    local users_check
    users_check=$(ssh "$NODE_E_HOST" "docker logs remnawave-node --tail 10 2>&1 | grep 'has 2 users' | wc -l")
    if [[ "$users_check" -gt 0 ]]; then
        log "node_e: VLESS_YC_ENTRY has 2 users ✅"
    else
        warn "Проверь логи node_e: ssh $NODE_E_HOST 'docker logs remnawave-node --tail 20'"
    fi
}

# ── Шаг 4: Проверка связности ─────────────────────────────────
verify() {
    log "Проверка связности..."

    # TLS handshake на entry
    local tls_code
    tls_code=$(ssh "$REMNA_HOST" \
        "curl -sk --max-time 5 https://$ENTRY_DOMAIN \
         --resolve $ENTRY_DOMAIN:443:$NODE_E_IP \
         -o /dev/null -w '%{http_code}'" 2>/dev/null || echo "000")
    if [[ "$tls_code" == "200" ]]; then
        log "Reality TLS handshake: $ENTRY_DOMAIN:443 → 200 OK ✅"
    else
        warn "TLS handshake вернул: $tls_code"
    fi

    # TCP до transit порта
    local tcp_check
    tcp_check=$(ssh "$NODE_E_HOST" "nc -z -w5 $NODE_D_IP $TRANSIT_PORT && echo OK || echo FAIL")
    if [[ "$tcp_check" == "OK" ]]; then
        log "TCP туннель $NODE_E_IP → $NODE_D_IP:$TRANSIT_PORT ✅"
    else
        warn "TCP туннель недоступен!"
    fi

    echo ""
    echo "════════════════════════════════════════"
    echo " Подписка:"
    echo " https://panelhide.su/api/sub/jk99Ho0Q5XBoPBfq"
    echo "════════════════════════════════════════"
}

# ── Основной поток ────────────────────────────────────────────
main() {
    local target="${1:-all}"

    case "$target" in
        transit)  deploy_transit ;;
        firewall) deploy_firewall ;;
        panel)    deploy_panel ;;
        verify)   verify ;;
        all)
            deploy_transit
            deploy_firewall
            deploy_panel
            verify
            ;;
        *)
            echo "Использование: $0 [all|transit|firewall|panel|verify]"
            exit 1
            ;;
    esac

    log "Готово!"
}

main "$@"
