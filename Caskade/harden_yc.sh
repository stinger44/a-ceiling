#!/bin/bash
# harden_yc.sh — Hardening entry ноды (yc, 111.88.249.82)
#
# Что делает:
#   1. UFW — разрешаем только нужные порты, всё остальное DROP
#   2. SSH hardening — только ключи, отключаем root-логин
#   3. fail2ban — блокируем брутфорс SSH
#   4. sysctl — сетевая защита (SYN flood, ICMP, spoofing)
#   5. unattended-upgrades — авто-патчинг безопасности
#
# ВАЖНО: запускать после подтверждения что SSH работает по ключу!
# Запуск: bash harden_yc.sh

set -euo pipefail

SSH_ALIAS="yc"

log()  { echo ""; echo "══════════════════════════════════════════"; echo "  [$(date '+%H:%M:%S')] $*"; echo "══════════════════════════════════════════"; }
info() { echo "  → $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# ПРЕДВАРИТЕЛЬНАЯ ПРОВЕРКА: убеждаемся что SSH работает по ключу
# ─────────────────────────────────────────────────────────────────────────────
log "Проверка SSH подключения..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${SSH_ALIAS}" "echo 'SSH OK'"; then
  echo "ОШИБКА: SSH не работает по ключу. Настрой ключ перед запуском hardening!"
  exit 1
fi
info "SSH по ключу — OK"

# ─────────────────────────────────────────────────────────────────────────────
# 1. UFW — Firewall
# ─────────────────────────────────────────────────────────────────────────────
log "Настраиваем UFW (firewall)..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'UFW_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Устанавливаем ufw если нет
apt-get install -y ufw > /dev/null

# Сбрасываем всё и начинаем с чистого листа
ufw --force reset

# Политика по умолчанию: всё входящее — DROP, исходящее — ALLOW
ufw default deny incoming
ufw default allow outgoing

# ── Разрешённые входящие порты ───────────────────────────────────────────────

# SSH — строго необходим, иначе потеряем доступ
ufw allow 22/tcp comment 'SSH'

# Xray VLESS+Reality — основной VPN-порт (клиенты подключаются сюда)
ufw allow 443/tcp comment 'Xray VLESS+Reality'

# nginx маскировка — Reality перенаправляет сюда «посторонних»
ufw allow 4433/tcp comment 'nginx masquerade'

# ── Ограничиваем SSH брутфорс через UFW rate limiting ────────────────────────
# (дополнительно к fail2ban — двойная защита)
ufw limit 22/tcp comment 'SSH rate limit'

# ── Включаем UFW ─────────────────────────────────────────────────────────────
ufw --force enable

echo "UFW статус:"
ufw status verbose
UFW_EOF

info "UFW настроен."

# ─────────────────────────────────────────────────────────────────────────────
# 2. SSH Hardening
# ─────────────────────────────────────────────────────────────────────────────
log "Hardening SSH..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'SSH_EOF'
set -euo pipefail

SSHD="/etc/ssh/sshd_config"

# Бэкап оригинала (один раз)
[ ! -f "${SSHD}.orig" ] && cp "${SSHD}" "${SSHD}.orig"

# Функция: установить или заменить параметр в sshd_config
set_ssh_param() {
  local key="$1"
  local val="$2"
  # Убираем все существующие строки с этим ключом (включая закомментированные)
  sed -i "s|^#\?${key}.*||g" "${SSHD}"
  # Добавляем в конец
  echo "${key} ${val}" >> "${SSHD}"
}

set_ssh_param "PermitRootLogin"          "no"           # root-логин запрещён
set_ssh_param "PasswordAuthentication"   "no"           # только ключи
set_ssh_param "PubkeyAuthentication"     "yes"          # ключи обязательны
set_ssh_param "AuthenticationMethods"    "publickey"    # только publickey
set_ssh_param "MaxAuthTries"             "3"            # макс 3 попытки
set_ssh_param "LoginGraceTime"           "20"           # 20 сек на аутентификацию
set_ssh_param "ClientAliveInterval"      "300"          # keepalive 5 мин
set_ssh_param "ClientAliveCountMax"      "2"            # 2 раза, потом дроп
set_ssh_param "X11Forwarding"           "no"            # отключаем X11
set_ssh_param "AllowAgentForwarding"    "no"            # отключаем agent forwarding
set_ssh_param "AllowTcpForwarding"      "no"            # отключаем TCP forwarding
set_ssh_param "PermitEmptyPasswords"    "no"            # пустые пароли запрещены
set_ssh_param "UseDNS"                  "no"            # не резолвим DNS (быстрее)
set_ssh_param "MaxSessions"             "5"             # макс 5 сессий
set_ssh_param "Banner"                  "none"          # не показываем баннер

# Проверяем конфиг перед рестартом
sshd -t && echo "sshd_config OK" || { echo "ОШИБКА в sshd_config!"; cp "${SSHD}.orig" "${SSHD}"; exit 1; }

# Ubuntu: сервис называется 'ssh', не 'sshd'
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
echo "SSH hardening применён."
SSH_EOF

info "SSH hardening — OK."

# ─────────────────────────────────────────────────────────────────────────────
# 3. fail2ban — блокируем брутфорс
# ─────────────────────────────────────────────────────────────────────────────
log "Устанавливаем и настраиваем fail2ban..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'F2B_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get install -y fail2ban > /dev/null

# Локальный конфиг (не трогаем jail.conf — он перезапишется при обновлении)
cat > /etc/fail2ban/jail.local << 'JAIL'
[DEFAULT]
# Банить на 1 час после 5 неудач за 10 минут
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

# Бан через iptables — полный DROP пакетов
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400  ; SSH: бан на 24 часа — строже чем дефолт

[nginx-limit-req]
enabled  = true
filter   = nginx-limit-req
port     = http,https,4433
logpath  = /var/log/nginx/error.log
maxretry = 10
JAIL

systemctl enable fail2ban
systemctl restart fail2ban

echo "fail2ban статус:"
fail2ban-client status
F2B_EOF

info "fail2ban настроен."

# ─────────────────────────────────────────────────────────────────────────────
# 4. sysctl — сетевая защита ядра
# ─────────────────────────────────────────────────────────────────────────────
log "Применяем sysctl hardening..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'SYSCTL_EOF'
set -euo pipefail

cat > /etc/sysctl.d/99-hardening.conf << 'SYSCTL'
# ── Защита от SYN flood ───────────────────────────────────────────────────────
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# ── Защита от IP spoofing ─────────────────────────────────────────────────────
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ── Отключаем ICMP редиректы (не маршрутизатор) ──────────────────────────────
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# ── Отключаем source routing ─────────────────────────────────────────────────
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# ── ICMP: игнорируем broadcast ping (Smurf-атаки) ────────────────────────────
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# ── TCP TIME_WAIT: защита от sequence-number атак ────────────────────────────
net.ipv4.tcp_rfc1337 = 1

# ── Логируем подозрительные пакеты (martians) ────────────────────────────────
net.ipv4.conf.all.log_martians = 1

# ── Защита /proc от других пользователей ─────────────────────────────────────
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
SYSCTL

# Применяем без перезагрузки
sysctl -p /etc/sysctl.d/99-hardening.conf
echo "sysctl hardening применён."
SYSCTL_EOF

info "sysctl — OK."

# ─────────────────────────────────────────────────────────────────────────────
# 5. Automatic security updates
# ─────────────────────────────────────────────────────────────────────────────
log "Настраиваем автоматические security updates..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'UU_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get install -y unattended-upgrades > /dev/null

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'APT'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
// Удаляем неиспользуемые зависимости
Unattended-Upgrade::Remove-Unused-Dependencies "true";
// Перезагружаем при необходимости (ядро, libc)
Unattended-Upgrade::Automatic-Reboot "false";
// Логируем
Unattended-Upgrade::Mail "";
Unattended-Upgrade::MailOnlyOnError "true";
APT

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades
echo "unattended-upgrades настроен."
UU_EOF

info "Auto security updates — OK."

# ─────────────────────────────────────────────────────────────────────────────
# Итоговый статус
# ─────────────────────────────────────────────────────────────────────────────
log "Итоговый статус сервера..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'STATUS_EOF'
echo ""
echo "══ UFW ══════════════════════════════════"
ufw status numbered

echo ""
echo "══ fail2ban ════════════════════════════"
fail2ban-client status

echo ""
echo "══ Открытые порты ══════════════════════"
ss -tlnp | grep -E '(22|443|4433)' || true

echo ""
echo "══ SSH config (ключевые параметры) ═════"
grep -E "^(PermitRootLogin|PasswordAuthentication|MaxAuthTries)" /etc/ssh/sshd_config
STATUS_EOF

echo ""
echo "✅ Hardening завершён!"
echo ""
echo "   Защита:"
echo "   ├── UFW: открыто только 22/tcp, 443/tcp, 4433/tcp"
echo "   ├── SSH: только ключи, root запрещён, 3 попытки макс"
echo "   ├── fail2ban: SSH бан 24ч после 3 неудач"
echo "   ├── sysctl: SYN-flood, spoofing, ICMP защита"
echo "   └── auto-updates: security патчи каждые 24ч"
