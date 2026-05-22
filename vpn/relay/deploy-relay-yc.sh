#!/bin/bash
# Деплой relay VM в Yandex Cloud (Layer 2)
# Использует: yc CLI (должен быть установлен и инициализирован)
#
# Запуск: bash relay/deploy-relay-yc.sh
# Время: ~10 минут

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Загрузка конфига ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

VPS_IP="${VPS_IP:?Укажи VPS_IP в .env}"
VPS_PORT="${VPS_PORT:-4500}"
VLESS_UUID="${VLESS_UUID:?Укажи VLESS_UUID в .env}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:?Укажи REALITY_PUBLIC_KEY в .env}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:?Укажи REALITY_SHORT_ID в .env}"
RELAY_SNI="${RELAY_SNI:-mts.ru}"

YC_FOLDER_ID="${YC_FOLDER_ID:?Укажи YC_FOLDER_ID в .env}"
YC_ZONE="${YC_ZONE:-ru-central1-a}"
VM_NAME="vpn-relay-$(date +%s | tail -c 6)"
VM_PRESET="standard-v3"   # 2 vCPU, 2 GB RAM
VM_CORES=2
VM_MEMORY=2
VM_DISK=15                 # GB
VM_PREEMPTIBLE="true"      # Экономим ~70% стоимости (~400-500₽/мес)

# ─── Проверки ──────────────────────────────────────────────────────────────────
command -v yc &>/dev/null || die "yc CLI не установлен. Запусти: curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash"
yc config get token &>/dev/null || die "yc не авторизован. Запусти: yc init"

# ─── SSH ключ ──────────────────────────────────────────────────────────────────
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
if [[ ! -f "${SSH_KEY_PATH}" ]]; then
    log "Генерация SSH ключа..."
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "vpn-relay"
fi
SSH_PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")

# ─── cloud-init скрипт (запускается на VM при первом старте) ──────────────────
RELAY_UUID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
             openssl rand -hex 16 | sed 's/.\{8\}/&-/;s/.\{13\}/&-/;s/.\{18\}/&-/;s/.\{23\}/&-/')
RELAY_SHORT_ID=$(openssl rand -hex 8)

# --- Конфиг Xray (собирается локально, передаётся через base64) ---------------
# Вложенный heredoc внутри CLOUDINIT не работает в bash:
#   1. Закрывающий маркер с пробелами не распознаётся как конец heredoc
#   2. cloud-init runcmd ненадёжно обрабатывает heredocs в | блоках
# Решение: кодируем JSON в base64 здесь, декодируем на VM одной командой.
XRAY_CONFIG=$(cat <<JSONEOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "tag": "relay-in",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "${RELAY_UUID}", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "${RELAY_SNI}:443",
        "serverNames": ["${RELAY_SNI}"],
        "privateKey": "RELAY_PRIV_PLACEHOLDER",
        "shortIds": ["${RELAY_SHORT_ID}"]
      }
    }
  }],
  "outbounds": [{
    "tag": "to-vps",
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${VPS_IP}",
        "port": ${VPS_PORT},
        "users": [{"id": "${VLESS_UUID}", "flow": "xtls-rprx-vision", "encryption": "none"}]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "fingerprint": "chrome",
        "serverName": "www.microsoft.com",
        "publicKey": "${REALITY_PUBLIC_KEY}",
        "shortId": "${REALITY_SHORT_ID}"
      }
    }
  }]
}
JSONEOF
)
XRAY_CONFIG_B64=$(printf '%s' "$XRAY_CONFIG" | base64 -w 0)

# Генерируем Reality keypair для relay отдельно (свой ключ!)
# Xray будет установлен cloud-init-ом, ключи сгенерируем там
CLOUD_INIT_SCRIPT=$(cat << CLOUDINIT
#cloud-config
package_update: true
packages:
  - curl
  - openssl
  - ufw

runcmd:
  # Установка Xray
  - bash -c "\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  # BBR
  - echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
  - echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
  - sysctl -p
  # Firewall
  - ufw allow 22/tcp
  - ufw allow 443/tcp
  - ufw --force enable
  # Генерация Reality keypair для relay
  - KEYPAIR=\$(/usr/local/bin/xray x25519)
  - PRIV=\$(echo "\$KEYPAIR" | grep -oP 'Private key: \\K\\S+')
  - PUB=\$(echo "\$KEYPAIR"  | grep -oP 'Public key: \\K\\S+')
  # Сохраняем ключи в файл
  - echo "RELAY_REALITY_PRIVATE_KEY=\$PRIV"  > /root/relay-keys.txt
  - echo "RELAY_REALITY_PUBLIC_KEY=\$PUB"   >> /root/relay-keys.txt
  - echo "RELAY_VLESS_UUID=${RELAY_UUID}"   >> /root/relay-keys.txt
  - echo "RELAY_SHORT_ID=${RELAY_SHORT_ID}" >> /root/relay-keys.txt
  # Записываем конфиг Xray (base64-строка сгенерирована локально перед деплоем)
  - mkdir -p /usr/local/etc/xray
  - echo "${XRAY_CONFIG_B64}" | base64 -d > /usr/local/etc/xray/config.json
  # Подставляем реальный приватный ключ в конфиг
  - PRIV=\$(grep PRIVATE /root/relay-keys.txt | cut -d'=' -f2)
  - sed -i "s|RELAY_PRIV_PLACEHOLDER|\$PRIV|" /usr/local/etc/xray/config.json
  # Запускаем Xray
  - systemctl enable xray
  - systemctl start xray
CLOUDINIT
)

# ─── Создание VM ──────────────────────────────────────────────────────────────
log "[1/4] Создание VM '${VM_NAME}' в ${YC_ZONE}..."
info "Тип: preemptible (экономия 70%), ~400-500₽/мес прогноз"

VM_ID=$(yc compute instance create \
    --name "$VM_NAME" \
    --zone "$YC_ZONE" \
    --folder-id "$YC_FOLDER_ID" \
    --cores "$VM_CORES" \
    --memory "${VM_MEMORY}GB" \
    --core-fraction 100 \
    --preemptible \
    --create-boot-disk \
        image-family=ubuntu-2204-lts,\
        image-folder-id=standard-images,\
        size=${VM_DISK}GB,\
        type=network-hdd \
    --network-interface subnet-name=default-ru-central1-a,nat-ip-version=ipv4 \
    --metadata "user-data=${CLOUD_INIT_SCRIPT}" \
    --ssh-key "$SSH_KEY_PATH" \
    --format json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

log "[2/4] VM создана: ${VM_ID}"

log "[3/4] Ожидание публичного IP..."
sleep 15
RELAY_IP=$(yc compute instance get "$VM_ID" --format json | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['network_interfaces'][0]['primary_v4_address']['one_to_one_nat']['address'])")

log "[4/4] Ожидание cloud-init (Xray устанавливается ~3 минуты)..."
echo -n "    Ожидаем"
for i in $(seq 1 18); do
    sleep 10; echo -n "."
done
echo ""

# Получаем ключи с relay VM
log "Получение relay ключей..."
sleep 5
RELAY_KEYS=$(ssh -i "$SSH_KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "ubuntu@${RELAY_IP}" "cat /root/relay-keys.txt" 2>/dev/null || echo "")

echo ""
echo "════════════════════════════════════════════════"
echo "  ✅  Relay VM развёрнута!"
echo "════════════════════════════════════════════════"
echo ""
echo "  VM ID:      ${VM_ID}"
echo "  VM Name:    ${VM_NAME}"
echo "  IP:         ${RELAY_IP}"
echo ""
echo "  Relay ключи (добавь в .env):"
echo "  RELAY_IP=${RELAY_IP}"
if [[ -n "$RELAY_KEYS" ]]; then
    echo "$RELAY_KEYS" | sed 's/^/  /'
fi
echo "  RELAY_SHORT_ID=${RELAY_SHORT_ID}"
echo ""
echo "  VLESS-ссылка (Layer 2):"
RELAY_PUB=$(echo "$RELAY_KEYS" | grep PUBLIC | cut -d'=' -f2 || echo "GET_FROM_RELAY")
echo "  vless://${RELAY_UUID}@${RELAY_IP}:443?security=reality&sni=${RELAY_SNI}&fp=chrome&pbk=${RELAY_PUB}&sid=${RELAY_SHORT_ID}&flow=xtls-rprx-vision&type=tcp#Layer2-Relay"
echo ""
echo "  ⚠️  Сохрани RELAY_IP и ключи в .env!"
echo "════════════════════════════════════════════════"

# Сохраняем локально
cat >> "${SCRIPT_DIR}/../.env" << EOF

# Relay (добавлено deploy-relay-yc.sh $(date '+%Y-%m-%d'))
RELAY_IP=${RELAY_IP}
RELAY_VLESS_UUID=${RELAY_UUID}
RELAY_SHORT_ID=${RELAY_SHORT_ID}
EOF
warn "RELAY_REALITY_PRIVATE_KEY и RELAY_REALITY_PUBLIC_KEY — скопируй из вывода выше в .env вручную"
