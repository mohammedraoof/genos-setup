#!/usr/bin/env bash
# Harden an Ubuntu 26.04 server after verifying out-of-band console access.
#
# Required:
#   ADMIN_USER=genos RESET_UFW=yes \
#     sudo ./scripts/harden-ubuntu-server.sh
# Optional:
#   SSH_PORT=22  (defaults to 22)
#
set -Eeuo pipefail
umask 027

ADMIN_USER="${ADMIN_USER:-}"
SSH_PORT="${SSH_PORT:-22}"
RESET_UFW="${RESET_UFW:-}"

die() {
  echo "Error: $*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root (for example, with sudo)."
}

validate_inputs() {
  [[ -n "${ADMIN_USER}" ]] || die "Set ADMIN_USER to the existing SSH administrator."
  id "${ADMIN_USER}" >/dev/null 2>&1 || die "ADMIN_USER does not exist: ${ADMIN_USER}"
  [[ "${RESET_UFW}" == "yes" ]] || die "Set RESET_UFW=yes to explicitly replace existing UFW rules."
  [[ "${SSH_PORT}" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) \
    || die "SSH_PORT must be a valid TCP port."

  local home_dir
  home_dir="$(getent passwd "${ADMIN_USER}" | cut -d: -f6)"
  [[ -n "${home_dir}" ]] || die "Could not determine the home directory for ${ADMIN_USER}."
}

require_ubuntu_2604() {
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "26.04" ]] \
    || die "This script supports Ubuntu 26.04 only."
}

configure_automatic_updates() {
  cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
}

configure_sysctl() {
  cat >/etc/sysctl.d/99-server-hardening.conf <<'EOF'
# Network hardening for a typical Internet-facing Linux server.
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
  sysctl --system >/dev/null
}

configure_ssh() {
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-server-hardening.conf <<EOF
# Managed by harden-ubuntu-server.sh
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
GatewayPorts no
PermitTunnel no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ${ADMIN_USER}
EOF
  sshd -t || die "SSH configuration validation failed; no SSH service was restarted."
  systemctl reload ssh
}

configure_firewall() {
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  ufw allow "${SSH_PORT}/tcp"
  ufw allow 443/tcp

  ufw --force enable
}

configure_fail2ban() {
  cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 3
findtime = 10m
bantime = 1h
EOF
  systemctl enable --now fail2ban
}

main() {
  require_root
  require_ubuntu_2604
  validate_inputs

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    unattended-upgrades ufw fail2ban auditd apparmor apparmor-utils

  configure_automatic_updates
  systemctl enable --now apparmor auditd
  configure_sysctl
  configure_ssh
  configure_fail2ban
  configure_firewall

  echo "Hardening complete. Keep this SSH session open and test a second login before disconnecting."
  echo "SSH is allowed from any address on port ${SSH_PORT}; HTTPS is allowed on port 443."
}

main "$@"
