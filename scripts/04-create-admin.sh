#!/usr/bin/env bash
# 04-create-admin.sh
# Creates the first admin user on the Matrix homeserver.
# Works by temporarily enabling registration with a one-time token,
# registering via the API, then disabling registration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
source "${ROOT_DIR}/.env"

MATRIX_HOSTNAME="${MATRIX_SUBDOMAIN}.${DOMAIN}"
HOMESERVER_URL="https://${MATRIX_HOSTNAME}"

echo "==> Create admin user on ${HOMESERVER_URL}"
echo ""

# Collect credentials interactively
read -rp "Admin username (no spaces, e.g. admin): " ADMIN_USER
if [[ -z "${ADMIN_USER}" || "${ADMIN_USER}" =~ [[:space:]] ]]; then
    echo "ERROR: Username cannot be empty or contain spaces"
    exit 1
fi

read -rsp "Password (min 12 chars): " ADMIN_PASSWORD
echo ""
read -rsp "Confirm password: " ADMIN_PASSWORD_CONFIRM
echo ""

if [[ "${ADMIN_PASSWORD}" != "${ADMIN_PASSWORD_CONFIRM}" ]]; then
    echo "ERROR: Passwords do not match"
    exit 1
fi
if [[ ${#ADMIN_PASSWORD} -lt 12 ]]; then
    echo "ERROR: Password must be at least 12 characters"
    exit 1
fi

# Generate a one-time registration token
REG_TOKEN="$(openssl rand -hex 24)"

echo ""
echo "--> Enabling registration with temporary token..."

# Render a conduit.toml with registration temporarily enabled
TMPDIR_REG=$(mktemp -d)
trap 'rm -rf "${TMPDIR_REG}"' EXIT

MATRIX_HOSTNAME="${MATRIX_HOSTNAME}" \
sed \
    -e "s/__MATRIX_HOSTNAME__/${MATRIX_HOSTNAME}/g" \
    "${ROOT_DIR}/config/conduit.toml.template" \
    > "${TMPDIR_REG}/conduit.toml"

# Append registration settings
cat >> "${TMPDIR_REG}/conduit.toml" <<EOF

# Temporary — removed after admin user is created
allow_registration = true
registration_token = "${REG_TOKEN}"
EOF

# Fix the duplicate allow_registration line (template has it as false, we append true)
# Keep only the last occurrence
grep -v "^allow_registration = false" "${TMPDIR_REG}/conduit.toml" > "${TMPDIR_REG}/conduit_reg.toml"
mv "${TMPDIR_REG}/conduit_reg.toml" "${TMPDIR_REG}/conduit.toml"

scp -i "${SSH_KEY}" \
    "${TMPDIR_REG}/conduit.toml" \
    "${DROPLET_USER}@${DROPLET_IP}:~/matrix/conduit/conduit.toml"

ssh -i "${SSH_KEY}" "${DROPLET_USER}@${DROPLET_IP}" \
    'cd ~/matrix && sg docker -c "docker compose restart conduit"'

echo "    Waiting for Conduit to restart..."
sleep 8

echo "--> Registering @${ADMIN_USER}:${MATRIX_HOSTNAME}..."

HTTP_STATUS=$(curl -s -o /tmp/matrix_reg_response.json -w "%{http_code}" \
    -X POST "${HOMESERVER_URL}/_matrix/client/v3/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"${ADMIN_USER}\",
        \"password\": \"${ADMIN_PASSWORD}\",
        \"auth\": {
            \"type\": \"m.login.registration_token\",
            \"token\": \"${REG_TOKEN}\"
        }
    }")

if [[ "${HTTP_STATUS}" != "200" ]]; then
    echo "ERROR: Registration failed (HTTP ${HTTP_STATUS})"
    echo "Response:"
    cat /tmp/matrix_reg_response.json
    echo ""
    echo "Restoring original config and restarting..."
    MATRIX_HOSTNAME="${MATRIX_HOSTNAME}" \
    sed -e "s/__MATRIX_HOSTNAME__/${MATRIX_HOSTNAME}/g" \
        "${ROOT_DIR}/config/conduit.toml.template" \
        | ssh -i "${SSH_KEY}" "${DROPLET_USER}@${DROPLET_IP}" \
            'cat > ~/matrix/conduit/conduit.toml && cd ~/matrix && sg docker -c "docker compose restart conduit"'
    exit 1
fi

echo "    Registration successful."
rm -f /tmp/matrix_reg_response.json

echo "--> Disabling registration..."

# Restore the original (registration disabled) config
sed -e "s/__MATRIX_HOSTNAME__/${MATRIX_HOSTNAME}/g" \
    "${ROOT_DIR}/config/conduit.toml.template" \
    | ssh -i "${SSH_KEY}" "${DROPLET_USER}@${DROPLET_IP}" \
        'cat > ~/matrix/conduit/conduit.toml && cd ~/matrix && sg docker -c "docker compose restart conduit"'

echo "    Registration disabled."

echo ""
echo "==> Admin user created!"
echo ""
echo "    MXID:       @${ADMIN_USER}:${MATRIX_HOSTNAME}"
echo "    Homeserver: ${HOMESERVER_URL}"
echo ""
echo "Connect with Element Desktop or FluffyChat:"
echo "  Homeserver URL: ${HOMESERVER_URL}"
echo ""
echo "Verify federation:"
echo "  https://federationtester.matrix.org/#${MATRIX_HOSTNAME}"
