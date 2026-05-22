#!/usr/bin/env bash
# =============================================================
# deploy_node_f.sh — Развёртывание exit ноды на aesa
# (193.233.137.187, SSH порт 22222)
#
# Что делает:
#   1. Разворачивает standalone xray-transit (порт 2223)
#   2. Разворачивает Remnawave Node Agent (порт 2222)
#   3. Применяет балансировщик в панели
#   4. Перезапускает entry ноду
#   5. Проверяет связность
#
# Требования:
#   - node_f.env заполнен (NODE_ID + SECRET_KEY из панели)
#   - SSH алиас 'aesa' доступен
#
# Использование:
#   bash deploy_node_f.sh [all|transit|node|panel|verify]
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Загрузка конфигурации из .env ─────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
[[ -f "$ENV_FILE" ]] || { echo "[✗] Файл .env не найден! Скопируй .env.example → .env и заполни." >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a

# Алиасы для обратной совместимости
AESA_HOST="$NODE_F_HOST"
NODE_DIR="/opt/remnawave-node"

log()  { echo -e "\033[32m[+]\033[0m $*"; }
warn() { echo -e "\033[33m[!]\033[0m $*"; }
die()  { echo -e "\033[31m[✗]\033[0m $*" >&2; exit 1; }

# ── Шаг 1: Развернуть transit Xray ───────────────────────────
deploy_transit() {
    log "Развёртывание xray-transit на $AESA_HOST ($NODE_F_IP)..."

    ssh "$AESA_HOST" "mkdir -p $TRANSIT_DIR"
    scp "$SCRIPT_DIR/transit_xray_config.json"  "$AESA_HOST:$TRANSIT_DIR/transit-config.json"
    scp "$SCRIPT_DIR/transit_docker_compose.yml" "$AESA_HOST:$TRANSIT_DIR/docker-compose.yml"

    ssh "$AESA_HOST" "cd $TRANSIT_DIR && docker compose up -d"
    sleep 3

    local port_ok
    port_ok=$(ssh "$AESA_HOST" "ss -tlnp | grep $TRANSIT_PORT | wc -l")
    [[ "$port_ok" -gt 0 ]] \
        && log "Transit Xray слушает порт $TRANSIT_PORT ✅" \
        || die "Transit не поднялся! Проверь: ssh $AESA_HOST 'docker logs xray-transit'"

    log "Открываем порт $TRANSIT_PORT в UFW..."
    ssh "$AESA_HOST" "ufw allow $TRANSIT_PORT/tcp && ufw reload" || true
    log "UFW обновлён ✅"
}

# ── Шаг 2: Развернуть Remnawave Node Agent ───────────────────
deploy_node() {
    local env_file="$SCRIPT_DIR/node_f.env"
    [[ -f "$env_file" ]] || die "Файл $env_file не найден!"

    # Проверить что NODE_ID заполнен
    source "$env_file"
    [[ "$NODE_ID" == "REPLACE_WITH_NODE_ID_FROM_PANEL" ]] && \
        die "Заполни NODE_ID и SECRET_KEY в node_f.env (взять из панели panelhide.su)"

    log "Развёртывание Remnawave Node Agent на $AESA_HOST..."

    ssh "$AESA_HOST" "mkdir -p $NODE_DIR"

    # Загрузить env и compose
    scp "$env_file" "$AESA_HOST:$NODE_DIR/.env"
    scp "$SCRIPT_DIR/yc_node_docker_compose.yml" "$AESA_HOST:$NODE_DIR/docker-compose.yml"

    # Загрузить geo данные (скопировать с node_e если нет локально)
    if [[ -f "$SCRIPT_DIR/geoip.dat" ]]; then
        scp "$SCRIPT_DIR/geoip.dat"   "$AESA_HOST:$NODE_DIR/geoip.dat"
        scp "$SCRIPT_DIR/geosite.dat" "$AESA_HOST:$NODE_DIR/geosite.dat"
    else
        warn "geoip.dat не найден локально, копируем с node_e..."
        ssh "$NODE_E_HOST" "cat /opt/remnawave-node/geoip.dat"   | ssh "$AESA_HOST" "cat > $NODE_DIR/geoip.dat"
        ssh "$NODE_E_HOST" "cat /opt/remnawave-node/geosite.dat" | ssh "$AESA_HOST" "cat > $NODE_DIR/geosite.dat"
    fi

    ssh "$AESA_HOST" "cd $NODE_DIR && docker compose up -d"

    # Открыть порт агента
    ssh "$AESA_HOST" "ufw allow 2222/tcp && ufw reload" || true

    sleep 5
    local node_status
    node_status=$(ssh "$AESA_HOST" "docker logs remnawave-node --tail 5 2>&1")
    log "Логи node agent:"
    echo "$node_status"
    log "Node Agent запущен ✅ (проверь статус в панели)"
}

# ── Шаг 3: Применить балансировщик в панели ──────────────────
deploy_panel() {
    log "Применяем balancer конфиг в Remnawave панели..."
    ssh "$REMNA_HOST" \
        "docker exec -i remnawave-db psql -U postgres -d postgres" \
        < "$SCRIPT_DIR/update_cascade_balancer.sql"
    log "SQL применён ✅"

    log "Перезапускаем entry ноду для применения конфига..."
    ssh "$NODE_E_HOST" "docker restart remnawave-node"
    sleep 10
    log "Entry нода перезапущена ✅"
}

# ── Шаг 4: Проверка связности ─────────────────────────────────
verify() {
    log "Проверка TCP туннелей с entry ноды..."

    local d_ok f_ok
    d_ok=$(ssh "$NODE_E_HOST" "nc -z -w5 78.17.134.17 $TRANSIT_PORT && echo OK || echo FAIL")
    f_ok=$(ssh "$NODE_E_HOST" "nc -z -w5 $NODE_F_IP $TRANSIT_PORT && echo OK || echo FAIL")

    [[ "$d_ok" == "OK" ]] && log "node_d (78.17.134.17:$TRANSIT_PORT): ✅" || warn "node_d: НЕДОСТУПЕН ❌"
    [[ "$f_ok" == "OK" ]] && log "node_f ($NODE_F_IP:$TRANSIT_PORT): ✅"   || warn "node_f: НЕДОСТУПЕН ❌"

    echo ""
    echo "════════════════════════════════════════"
    echo " Балансировщик: roundRobin"
    echo " node_d: 78.17.134.17:$TRANSIT_PORT"
    echo " node_f: $NODE_F_IP:$TRANSIT_PORT"
    echo " Подписка: https://panelhide.su/api/sub/jk99Ho0Q5XBoPBfq"
    echo "════════════════════════════════════════"
}

# ── Основной поток ────────────────────────────────────────────
main() {
    local target="${1:-all}"
    case "$target" in
        transit) deploy_transit ;;
        node)    deploy_node ;;
        panel)   deploy_panel ;;
        verify)  verify ;;
        all)
            deploy_transit
            deploy_node
            deploy_panel
            verify
            ;;
        *)
            echo "Использование: $0 [all|transit|node|panel|verify]"
            exit 1
            ;;
    esac
    log "Готово!"
}

main "$@"
