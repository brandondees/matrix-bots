#!/usr/bin/env bash
# 02-install-docker.sh
# Installs Docker on the droplet using the official convenience script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../.env"

echo "==> Installing Docker on ${DROPLET_IP} as ${DROPLET_USER}"

ssh -i "${SSH_KEY}" -o ConnectTimeout=10 "${DROPLET_USER}@${DROPLET_IP}" bash <<'ENDSSH'
set -euo pipefail

if command -v docker &>/dev/null; then
    echo "Docker already installed: $(docker --version)"
    exit 0
fi

echo "--> Downloading and running Docker install script..."
curl -fsSL https://get.docker.com | sudo sh

echo "--> Adding ${USER} to docker group..."
sudo usermod -aG docker "${USER}"

echo ""
echo "Docker installed: $(docker --version)"
echo "NOTE: Group membership takes effect in new sessions (handled by setup.sh via sg)."
ENDSSH

echo ""
echo "==> Docker installed."
