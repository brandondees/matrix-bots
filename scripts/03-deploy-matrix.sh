#!/usr/bin/env bash
# 03-deploy-matrix.sh
# Renders config templates and deploys the Matrix stack via Docker Compose.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
source "${ROOT_DIR}/.env"

MATRIX_HOSTNAME="${MATRIX_SUBDOMAIN}.${DOMAIN}"

echo "==> Deploying Matrix stack"
echo "    Homeserver: https://${MATRIX_HOSTNAME}"
echo "    Droplet:    ${DROPLET_USER}@${DROPLET_IP}"
echo ""

# Render templates locally into a temp directory
TMPDIR_RENDER=$(mktemp -d)
trap 'rm -rf "${TMPDIR_RENDER}"' EXIT

render_template() {
    sed \
        -e "s/__MATRIX_HOSTNAME__/${MATRIX_HOSTNAME}/g" \
        -e "s/__DOMAIN__/${DOMAIN}/g" \
        -e "s/__MATRIX_SUBDOMAIN__/${MATRIX_SUBDOMAIN}/g" \
        "$1" > "$2"
}

echo "--> Rendering config templates..."
render_template "${ROOT_DIR}/config/conduit.toml.template" "${TMPDIR_RENDER}/conduit.toml"
render_template "${ROOT_DIR}/config/Caddyfile.template"    "${TMPDIR_RENDER}/Caddyfile"

echo "--> Creating directory structure on droplet..."
ssh -i "${SSH_KEY}" -o ConnectTimeout=10 "${DROPLET_USER}@${DROPLET_IP}" \
    'mkdir -p ~/matrix/conduit ~/matrix/caddy'

echo "--> Copying files to droplet..."
scp -i "${SSH_KEY}" \
    "${ROOT_DIR}/config/docker-compose.yml" \
    "${DROPLET_USER}@${DROPLET_IP}:~/matrix/docker-compose.yml"

scp -i "${SSH_KEY}" \
    "${TMPDIR_RENDER}/conduit.toml" \
    "${DROPLET_USER}@${DROPLET_IP}:~/matrix/conduit/conduit.toml"

scp -i "${SSH_KEY}" \
    "${TMPDIR_RENDER}/Caddyfile" \
    "${DROPLET_USER}@${DROPLET_IP}:~/matrix/caddy/Caddyfile"

echo "--> Starting services..."
ssh -i "${SSH_KEY}" "${DROPLET_USER}@${DROPLET_IP}" bash <<'ENDSSH'
set -euo pipefail
cd ~/matrix

# sg runs the command with the docker group active without needing a re-login
sg docker -c "docker compose pull --quiet"
sg docker -c "docker compose up -d"

echo ""
echo "Waiting for services to start..."
sleep 5

sg docker -c "docker compose ps"
ENDSSH

echo ""
echo "==> Matrix stack deployed."
echo ""
echo "Monitor logs:"
echo "  ssh -i ${SSH_KEY} ${DROPLET_USER}@${DROPLET_IP} 'cd ~/matrix && docker compose logs -f'"
