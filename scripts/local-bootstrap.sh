#!/usr/bin/env bash
# =============================================================================
# local-bootstrap.sh
# Run from your LOCAL machine (not the droplet).
# Copies the bootstrap script to the droplet and runs it as root.
#
# Usage:
#   cp .env.example .env && nano .env   # fill in DROPLET_IP, DEPLOY_USER, etc.
#   bash scripts/local-bootstrap.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env not found. Copy .env.example to .env and fill it in."
    exit 1
fi
set -a; source "$ENV_FILE"; set +a

: "${DROPLET_IP:?DROPLET_IP must be set in .env}"
: "${DEPLOY_USER:?DEPLOY_USER must be set in .env}"
: "${DROPLET_SSH_KEY:?DROPLET_SSH_KEY must be set in .env}"

REPO_URL="https://github.com/brandondees/matrix-bots.git"
SSH_OPTS="-i ${DROPLET_SSH_KEY} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

echo "================================================================"
echo "  Bootstrapping droplet"
echo "  Host       : ${DROPLET_IP}"
echo "  Deploy user: ${DEPLOY_USER}"
echo "  Repo       : ${REPO_URL}"
echo "================================================================"
echo ""

# Determine which user can connect — root works on a fresh droplet;
# after SSH hardening runs it's locked out and we fall back to deploy user.
if ssh $SSH_OPTS "root@${DROPLET_IP}" true 2>/dev/null; then
    SSH_USER="root"
    SUDO=""
    echo ">>> Connecting as root"
else
    SSH_USER="${DEPLOY_USER}"
    SUDO="sudo"
    echo ">>> Root login disabled (already hardened) — connecting as ${DEPLOY_USER}"
fi

echo ">>> Copying bootstrap script to droplet"
scp $SSH_OPTS "$REPO_ROOT/scripts/00-bootstrap.sh" "${SSH_USER}@${DROPLET_IP}:/tmp/00-bootstrap.sh"

echo ">>> Running bootstrap on droplet"
ssh $SSH_OPTS "${SSH_USER}@${DROPLET_IP}" "${SUDO} bash /tmp/00-bootstrap.sh '${DEPLOY_USER}' '${REPO_URL}'"

echo ""
echo "================================================================"
echo "  Bootstrap done. Next steps:"
echo ""
echo "  1. Open a NEW terminal and verify deploy user login:"
echo "     ssh -i ${DROPLET_SSH_KEY} ${DEPLOY_USER}@${DROPLET_IP}"
echo ""
echo "  2. Once confirmed, continue on the droplet as ${DEPLOY_USER}:"
echo "     cd ~/matrix-bots"
echo "     bash scripts/02-install-docker.sh"
echo "================================================================"
