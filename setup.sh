#!/usr/bin/env bash
# setup.sh
# Master orchestration script. Runs all setup steps in order,
# pausing at the DNS step that requires manual action.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  Matrix Server Setup"
echo "========================================"
echo ""

# Verify .env exists
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
    echo "ERROR: .env not found."
    echo ""
    echo "Copy the example and fill in your values:"
    echo "  cp .env.example .env"
    echo "  \$EDITOR .env"
    exit 1
fi

source "${SCRIPT_DIR}/.env"

# Validate required variables
for VAR in DROPLET_IP SSH_KEY DROPLET_USER DOMAIN MATRIX_SUBDOMAIN; do
    if [[ -z "${!VAR:-}" ]]; then
        echo "ERROR: ${VAR} is not set in .env"
        exit 1
    fi
done

MATRIX_HOSTNAME="${MATRIX_SUBDOMAIN}.${DOMAIN}"

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "ERROR: SSH key not found at ${SSH_KEY}"
    exit 1
fi

echo "Configuration:"
printf "  %-20s %s\n" "Droplet IP:"      "${DROPLET_IP}"
printf "  %-20s %s\n" "SSH user:"        "${DROPLET_USER}"
printf "  %-20s %s\n" "Matrix hostname:" "${MATRIX_HOSTNAME}"
printf "  %-20s %s\n" "SSH key:"         "${SSH_KEY}"
echo ""
read -rp "Proceed? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo ""
echo "========================================"
echo "  Step 1/4 — Secure the droplet"
echo "========================================"
bash "${SCRIPT_DIR}/scripts/01-secure-droplet.sh"

echo ""
echo "========================================"
echo "  Step 2/4 — Install Docker"
echo "========================================"
bash "${SCRIPT_DIR}/scripts/02-install-docker.sh"

echo ""
echo "========================================"
echo "  Step 3/4 — DNS setup  [MANUAL STEP]"
echo "========================================"
echo ""
echo "Add the following DNS record in Namecheap before continuing:"
echo ""
echo "  Domain:  ${DOMAIN}"
echo "  Type:    A"
echo "  Host:    ${MATRIX_SUBDOMAIN}"
echo "  Value:   ${DROPLET_IP}"
echo "  TTL:     Automatic (or 300)"
echo ""
echo "Then wait for it to propagate. You can check with:"
echo "  dig +short ${MATRIX_HOSTNAME}"
echo "  (should return ${DROPLET_IP})"
echo ""
echo "Caddy will fail to provision TLS certificates if this isn't set correctly."
echo ""
read -rp "Press Enter once ${MATRIX_HOSTNAME} resolves to ${DROPLET_IP}..."

# Verify DNS resolves correctly
RESOLVED=$(dig +short "${MATRIX_HOSTNAME}" 2>/dev/null | tail -1 || true)
if [[ "${RESOLVED}" != "${DROPLET_IP}" ]]; then
    echo ""
    echo "WARNING: ${MATRIX_HOSTNAME} currently resolves to '${RESOLVED:-<nothing>}'"
    echo "         expected '${DROPLET_IP}'"
    echo ""
    echo "If you continue before DNS propagates, Caddy won't be able to get TLS certs."
    read -rp "Continue anyway? [y/N] " FORCE
    [[ "${FORCE}" =~ ^[Yy]$ ]] || { echo "Aborted. Re-run setup.sh once DNS propagates."; exit 1; }
fi

echo ""
echo "========================================"
echo "  Step 4/4 — Deploy Matrix stack"
echo "========================================"
bash "${SCRIPT_DIR}/scripts/03-deploy-matrix.sh"

echo ""
echo "========================================"
echo "  Setup complete!"
echo "========================================"
echo ""
echo "Next: create your admin user:"
echo "  bash scripts/04-create-admin.sh"
echo ""
echo "Then verify federation:"
echo "  https://federationtester.matrix.org/#${MATRIX_HOSTNAME}"
