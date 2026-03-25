#!/usr/bin/env bash
# =============================================================================
# 02-install-docker.sh
# Run as the deploy user (not root) after 01-secure-droplet.sh completes.
# Installs Docker Engine and adds the current user to the docker group.
# =============================================================================
set -euo pipefail

echo ">>> Installing prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# gettext-base provides envsubst, used by 03-deploy.sh to render conduit.toml
apt-get install -y --no-install-recommends curl gettext-base ca-certificates

echo ">>> Installing Docker"
if command -v docker &>/dev/null; then
    echo "    Docker already installed: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
fi

echo ">>> Adding $USER to the docker group"
sudo usermod -aG docker "$USER"

echo ""
echo "================================================================"
echo "  Docker installed."
echo "  You must log out and back in (or run 'newgrp docker') for the"
echo "  group change to take effect before running 03-deploy.sh."
echo "================================================================"
