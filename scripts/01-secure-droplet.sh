#!/usr/bin/env bash
# 01-secure-droplet.sh
# Run from your local machine. SSHes in as root and hardens the droplet:
#   - Creates a non-root sudo user
#   - Installs your SSH public key for that user
#   - Disables root login and password auth
#   - Configures UFW firewall
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../.env"

MATRIX_HOSTNAME="${MATRIX_SUBDOMAIN}.${DOMAIN}"
SSH_PUB_KEY="$(cat "${SSH_KEY}.pub")"

echo "==> Securing droplet at ${DROPLET_IP}"
echo "    Creating user: ${DROPLET_USER}"
echo ""

ssh -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    "root@${DROPLET_IP}" \
    DROPLET_USER="${DROPLET_USER}" \
    SSH_PUB_KEY="${SSH_PUB_KEY}" \
    bash <<'ENDSSH'
set -euo pipefail

echo "--> Creating user ${DROPLET_USER}..."
if ! id "${DROPLET_USER}" &>/dev/null; then
    adduser --disabled-password --gecos "" "${DROPLET_USER}"
fi

# Passwordless sudo (needed for automated docker/service management)
usermod -aG sudo "${DROPLET_USER}"
echo "${DROPLET_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${DROPLET_USER}"
chmod 440 "/etc/sudoers.d/${DROPLET_USER}"

echo "--> Installing SSH key for ${DROPLET_USER}..."
mkdir -p "/home/${DROPLET_USER}/.ssh"
echo "${SSH_PUB_KEY}" > "/home/${DROPLET_USER}/.ssh/authorized_keys"
chmod 700 "/home/${DROPLET_USER}/.ssh"
chmod 600 "/home/${DROPLET_USER}/.ssh/authorized_keys"
chown -R "${DROPLET_USER}:${DROPLET_USER}" "/home/${DROPLET_USER}/.ssh"

echo "--> Hardening SSH..."
# Make a backup before modifying
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Validate config before restarting
sshd -t
systemctl restart sshd
echo "    SSH hardened (root login and password auth disabled)"

echo "--> Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   comment 'SSH'
ufw allow 80/tcp   comment 'HTTP (Caddy ACME challenges)'
ufw allow 443/tcp  comment 'HTTPS'
ufw allow 443/udp  comment 'HTTPS/QUIC'
ufw allow 8448/tcp comment 'Matrix federation'
ufw --force enable
echo "    Firewall active"

echo ""
echo "Droplet secured successfully."
ENDSSH

echo ""
echo "==> Done. Test access with:"
echo "    ssh -i ${SSH_KEY} ${DROPLET_USER}@${DROPLET_IP}"
