#!/bin/bash
# harden_server.sh — Universal server hardening
#
# Использование:
#   bash harden_server.sh <ssh-alias> <ssh-port> <extra-ports...>
#
# Примеры:
#   bash harden_server.sh node_d 22   2223
#   bash harden_server.sh aesa   22222 2223
#   bash harden_server.sh remna  22222 80 443
#
# Что делает:
#   1. UFW — открывает только указанные порты, остальное DROP
#   2. SSH hardening — только ключи, root запрещён
#   3. fail2ban — бан SSH брутфорса
#   4. sysctl — сетевая защита ядра
#   5. unattended-upgrades — автопатчинг безопасности

set -euo pipefail

# ── Аргументы ────────────────────────────────────────────────────────────────
if [ $# -lt 2 ]; then
  echo "Использование: $0 <ssh-alias> <ssh-port> [extra-port/proto ...]"
  echo "Пример: $0 node_d 22 2223/tcp"
  exit 1
fi

SSH_ALIAS="$1"
SSH_PORT="$2"
shift 2
EXTRA_PORTS=("$@")   # массив дополнительных портов

log()  { echo ""; echo "══════════════════════════════════════════"; echo "  [$(date '+%H:%M:%S')] [$SSH_ALIAS] $*"; echo "══════════════════════════════════════════"; }
info() { echo "  → $*"; }

# ── Проверка SSH доступа ──────────────────────────────────────────────────────
log "Проверка SSH ($SSH_ALIAS)..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -p "${SSH_PORT}" "${SSH_ALIAS}" "echo 'SSH OK'" 2>/dev/null; then
  # Пробуем без -p (если порт уже в ~/.ssh/config)
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "${SSH_ALIAS}" "echo 'SSH OK'"; then
    echo "ОШИБКА: не могу подключиться к ${SSH_ALIAS}. Прерываю."
    exit 1
  fi
fi
info "SSH OK"

# ── 1. UFW ────────────────────────────────────────────────────────────────────
log "Настраиваем UFW..."

# Строим список портов для heredoc
PORTS_BLOCK=""
PORTS_BLOCK+="ufw allow ${SSH_PORT}/tcp comment 'SSH'\n"
PORTS_BLOCK+="ufw limit ${SSH_PORT}/tcp comment 'SSH rate limit'\n"
for port in "${EXTRA_PORTS[@]:-}"; do
  [ -z "$port" ] && continue
  # Добавляем /tcp если нет протокола
  [[ "$port" == */* ]] || port="${port}/tcp"
  PORTS_BLOCK+="ufw allow ${port} comment 'service'\n"
done

ssh "${SSH_ALIAS}" 'sudo bash -s' << UFW_EOF
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y ufw > /dev/null
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
$(printf '%b' "${PORTS_BLOCK}")
ufw --force enable
echo "UFW статус:"
ufw status verbose
UFW_EOF
info "UFW — OK."

# ── 2. SSH hardening ──────────────────────────────────────────────────────────
log "SSH hardening..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'SSH_EOF'
set -euo pipefail

SSHD="/etc/ssh/sshd_config"
[ ! -f "${SSHD}.orig" ] && cp "${SSHD}" "${SSHD}.orig"

set_param() {
  local key="$1" val="$2"
  sed -i "s|^#\?${key}[[:space:]].*||g" "${SSHD}"
  echo "${key} ${val}" >> "${SSHD}"
}

set_param "PermitRootLogin"        "no"
set_param "PasswordAuthentication" "no"
set_param "PubkeyAuthentication"   "yes"
set_param "AuthenticationMethods"  "publickey"
set_param "MaxAuthTries"           "3"
set_param "LoginGraceTime"         "20"
set_param "ClientAliveInterval"    "300"
set_param "ClientAliveCountMax"    "2"
set_param "X11Forwarding"         "no"
set_param "AllowAgentForwarding"  "no"
set_param "AllowTcpForwarding"    "no"
set_param "PermitEmptyPasswords"  "no"
set_param "UseDNS"                "no"
set_param "MaxSessions"           "5"
set_param "Banner"                "none"

sshd -t && echo "sshd_config OK" || {
  echo "ОШИБКА: откатываем sshd_config"
  cp "${SSHD}.orig" "${SSHD}"
  exit 1
}
# Ubuntu: ssh, Debian/CentOS: sshd
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
echo "SSH hardening применён."
SSH_EOF
info "SSH hardening — OK."

# ── 3. fail2ban ───────────────────────────────────────────────────────────────
log "Устанавливаем fail2ban..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'F2B_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y fail2ban > /dev/null

cat > /etc/fail2ban/jail.local << 'JAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400
JAIL

systemctl enable fail2ban
systemctl restart fail2ban
sleep 2
fail2ban-client status
F2B_EOF
info "fail2ban — OK."

# ── 4. sysctl ─────────────────────────────────────────────────────────────────
log "sysctl hardening..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'SYSCTL_EOF'
set -euo pipefail

cat > /etc/sysctl.d/99-hardening.conf << 'SYSCTL'
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.log_martians = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
SYSCTL

sysctl -p /etc/sysctl.d/99-hardening.conf
echo "sysctl OK."
SYSCTL_EOF
info "sysctl — OK."

# ── 5. unattended-upgrades ────────────────────────────────────────────────────
log "Auto security updates..."

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'UU_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y unattended-upgrades > /dev/null

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'APT'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
APT

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades
echo "unattended-upgrades OK."
UU_EOF
info "Auto-updates — OK."

# ── Итог ──────────────────────────────────────────────────────────────────────
log "Итоговый статус [$SSH_ALIAS]..."
ssh "${SSH_ALIAS}" 'sudo bash -s' << 'STATUS_EOF'
echo "── UFW ──────────────────────────────────"
ufw status numbered
echo ""
echo "── fail2ban ─────────────────────────────"
fail2ban-client status 2>/dev/null || echo "запускается..."
echo ""
echo "── Открытые порты ───────────────────────"
ss -tlnp
STATUS_EOF

echo ""
echo "✅ [$SSH_ALIAS] Hardening завершён!"
