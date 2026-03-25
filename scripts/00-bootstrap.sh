#!/usr/bin/env bash
# =============================================================================
# 00-bootstrap.sh
# Run ONCE as root on a fresh droplet that has no git installed yet.
#
# This is the ONLY script you need to copy to the droplet manually.
# It installs prerequisites, clones this repo, secures the droplet,
# and sets up the deploy user — all in one shot.
#
# From your local machine:
#   scp scripts/00-bootstrap.sh root@<droplet-ip>:~/
#   ssh root@<droplet-ip> 'bash ~/00-bootstrap.sh <deploy-username> <repo-url>'
#
# Example:
#   bash ~/00-bootstrap.sh matrix https://github.com/you/matrix-bots.git
# =============================================================================
set -euo pipefail

DEPLOY_USER="${1:?Usage: $0 <deploy-username> <repo-url>}"
REPO_URL="${2:?Usage: $0 <deploy-username> <repo-url>}"
REPO_DIR="/home/$DEPLOY_USER/matrix-bots"

echo "================================================================"
echo "  Matrix Bots Bootstrap"
echo "  Deploy user : $DEPLOY_USER"
echo "  Repo        : $REPO_URL"
echo "  Target dir  : $REPO_DIR"
echo "================================================================"
echo ""

# ── Install prerequisites ─────────────────────────────────────────────────────
echo ">>> Installing prerequisites (git, curl, gettext-base)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends git curl gettext-base ca-certificates ufw

# ── Create deploy user (same logic as 01-secure-droplet.sh) ───────────────────
echo ">>> Creating deploy user: $DEPLOY_USER"
if id "$DEPLOY_USER" &>/dev/null; then
    echo "    User already exists, skipping."
else
    adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG sudo "$DEPLOY_USER"

# ── Copy SSH authorized_keys ───────────────────────────────────────────────────
echo ">>> Copying SSH authorized_keys to $DEPLOY_USER"
mkdir -p "/home/$DEPLOY_USER/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
    chmod 700 "/home/$DEPLOY_USER/.ssh"
    chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
else
    echo "    WARNING: /root/.ssh/authorized_keys not found."
    echo "    Add your public key to /home/$DEPLOY_USER/.ssh/authorized_keys manually."
fi

# ── Clone repo as deploy user ─────────────────────────────────────────────────
echo ">>> Cloning repo to $REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then
    echo "    Repo already cloned, pulling latest."
    sudo -u "$DEPLOY_USER" git -C "$REPO_DIR" pull
else
    sudo -u "$DEPLOY_USER" git clone "$REPO_URL" "$REPO_DIR"
fi

# ── Harden SSH ────────────────────────────────────────────────────────────────
echo ">>> Hardening SSH config"
SSHD_CONF=/etc/ssh/sshd_config

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONF"
grep -q '^PermitRootLogin' "$SSHD_CONF" || echo 'PermitRootLogin no' >> "$SSHD_CONF"

sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONF"
grep -q '^PasswordAuthentication' "$SSHD_CONF" || echo 'PasswordAuthentication no' >> "$SSHD_CONF"

sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONF"
grep -q '^ChallengeResponseAuthentication' "$SSHD_CONF" || echo 'ChallengeResponseAuthentication no' >> "$SSHD_CONF"

systemctl restart sshd

# ── Firewall ──────────────────────────────────────────────────────────────────
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
echo "  Bootstrap complete!"
echo ""
echo "  IMPORTANT: Before closing this session, open a NEW terminal"
echo "  and verify you can SSH in as $DEPLOY_USER:"
echo ""
echo "    ssh $DEPLOY_USER@<droplet-ip>"
echo ""
echo "  Once confirmed, continue from the droplet as $DEPLOY_USER:"
echo ""
echo "    cd $REPO_DIR"
echo "    bash scripts/02-install-docker.sh"
echo "================================================================"
