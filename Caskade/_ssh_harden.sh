#!/bin/bash
# SSH Hardening script
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
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
echo "SSH hardening применён."
