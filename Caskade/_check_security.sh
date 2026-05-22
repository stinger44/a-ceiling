#!/bin/bash
# Проверка итогового состояния безопасности yc-сервера
SSH_ALIAS="yc"

ssh "${SSH_ALIAS}" 'sudo bash -s' << 'CHECK_EOF'

echo "══ 1. UFW ════════════════════════════════"
ufw status numbered

echo ""
echo "══ 2. fail2ban ══════════════════════════"
systemctl is-active fail2ban && fail2ban-client status || echo "fail2ban не активен"

echo ""
echo "══ 3. SSH config ════════════════════════"
grep -E "^(PermitRootLogin|PasswordAuthentication|MaxAuthTries|LoginGraceTime|AuthenticationMethods)" /etc/ssh/sshd_config

echo ""
echo "══ 4. sysctl сетевая защита ════════════"
sysctl net.ipv4.tcp_syncookies \
       net.ipv4.conf.all.rp_filter \
       net.ipv4.icmp_echo_ignore_broadcasts \
       net.ipv4.conf.all.accept_redirects \
       net.ipv4.conf.all.log_martians

echo ""
echo "══ 5. Открытые порты ════════════════════"
ss -tlnp | grep -E ':(22|443|4433) '

echo ""
echo "══ 6. unattended-upgrades ══════════════"
systemctl is-active unattended-upgrades

CHECK_EOF
