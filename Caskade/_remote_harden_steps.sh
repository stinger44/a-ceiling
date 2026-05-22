#!/bin/bash
# remote_harden_steps.sh — запускается на сервере через sudo
# Шаги: fail2ban + sysctl + unattended-upgrades
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== fail2ban ==="
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
echo "fail2ban OK."

echo "=== sysctl ==="
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

echo "=== unattended-upgrades ==="
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

echo "=== Итоговый статус ==="
ufw status numbered
echo ""
fail2ban-client status
