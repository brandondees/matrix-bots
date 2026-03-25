#!/usr/bin/env bash
# =============================================================================
# 01-secure-droplet.sh
# Run ONCE as root immediately after first SSH login to the droplet.
#
# Usage:
#   bash 01-secure-droplet.sh <deploy-username>
#
# Example:
#   bash 01-secure-droplet.sh matrix
# =============================================================================
set -euo pipefail

DEPLOY_USER="${1:?Usage: $0 <deploy-username>}"

echo ">>> Creating user: $DEPLOY_USER"
if id "$DEPLOY_USER" &>/dev/null; then
    echo "    User already exists, skipping creation."
else
    adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG sudo "$DEPLOY_USER"

echo ">>> Copying SSH authorized_keys to $DEPLOY_USER"
mkdir -p "/home/$DEPLOY_USER/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
    chmod 700 "/home/$DEPLOY_USER/.ssh"
    chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
else
    echo "    WARNING: /root/.ssh/authorized_keys not found. Add your public key manually."
fi

echo ">>> Hardening SSH config"
SSHD_CONF=/etc/ssh/sshd_config

# Disable root login
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONF"
grep -q '^PermitRootLogin' "$SSHD_CONF" || echo 'PermitRootLogin no' >> "$SSHD_CONF"

# Disable password authentication
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONF"
grep -q '^PasswordAuthentication' "$SSHD_CONF" || echo 'PasswordAuthentication no' >> "$SSHD_CONF"

# Disable challenge-response (covers PAM password prompts)
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONF"
grep -q '^ChallengeResponseAuthentication' "$SSHD_CONF" || echo 'ChallengeResponseAuthentication no' >> "$SSHD_CONF"

systemctl restart sshd

echo ">>> Configuring firewall (UFW)"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   comment 'SSH'
ufw allow 80/tcp   comment 'HTTP (Caddy ACME challenge)'
ufw allow 443/tcp  comment 'HTTPS'
ufw allow 443/udp  comment 'HTTP/3 (QUIC)'
ufw allow 8448/tcp comment 'Matrix federation'
ufw --force enable
ufw status verbose

echo ""
echo "================================================================"
echo "  Droplet secured."
echo "  IMPORTANT: Open a NEW terminal and verify you can SSH in as"
echo "  '$DEPLOY_USER' before closing this session."
echo "  Command: ssh $DEPLOY_USER@<droplet-ip>"
echo "================================================================"
