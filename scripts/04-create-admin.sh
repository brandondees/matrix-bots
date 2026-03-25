#!/usr/bin/env bash
# =============================================================================
# 04-create-admin.sh
# Creates the initial admin user on the Conduit homeserver.
#
# The Matrix registration API requires a two-step flow:
#   1. POST /register to get a session ID from the server
#   2. POST /register again with credentials + session ID + registration token
#
# This script temporarily enables registration, runs the flow, then
# disables registration and restarts Conduit.
#
# Usage (from repo root):
#   bash scripts/04-create-admin.sh <username>
# =============================================================================
set -euo pipefail

ADMIN_USER="${1:?Usage: $0 <username>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_DIR="$REPO_ROOT/matrix"
ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env not found"; exit 1
fi
set -a; source "$ENV_FILE"; set +a

: "${MATRIX_SERVER_NAME:?MATRIX_SERVER_NAME must be set in .env}"
: "${CONDUIT_REGISTRATION_TOKEN:?CONDUIT_REGISTRATION_TOKEN must be set in .env}"

HOMESERVER_URL="https://${MATRIX_SERVER_NAME}"
REGISTER_URL="${HOMESERVER_URL}/_matrix/client/v3/register"

# ── Helper: disable registration and restart, then exit with given code ────────
cleanup_and_exit() {
    local exit_code="${1:-1}"
    echo ">>> Disabling registration in conduit.toml"
    sed -i 's/^allow_registration = true/allow_registration = false/' "$MATRIX_DIR/conduit/conduit.toml"
    echo ">>> Restarting Conduit with registration disabled"
    cd "$MATRIX_DIR" && docker compose restart conduit
    exit "$exit_code"
}
trap 'cleanup_and_exit 1' ERR

# ── Enable registration temporarily ───────────────────────────────────────────
echo ">>> Enabling registration temporarily in conduit.toml"
sed -i 's/^allow_registration = false/allow_registration = true/' "$MATRIX_DIR/conduit/conduit.toml"

echo ">>> Restarting Conduit"
cd "$MATRIX_DIR"
docker compose restart conduit

echo "    Waiting for Conduit to be ready..."
for i in $(seq 1 15); do
    if curl -sf "${HOMESERVER_URL}/_matrix/client/versions" -o /dev/null 2>&1; then
        echo "    Conduit is ready."
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "ERROR: Conduit did not become ready in time. Check logs:"
        echo "  docker compose -f $MATRIX_DIR/docker-compose.yml logs conduit"
        cleanup_and_exit 1
    fi
    sleep 2
done

# ── Collect password ───────────────────────────────────────────────────────────
echo ""
echo ">>> Registering user @${ADMIN_USER}:${MATRIX_SERVER_NAME}"
read -s -r -p "Password for @${ADMIN_USER}: " PASSWORD
echo ""
read -s -r -p "Confirm password: " PASSWORD2
echo ""

if [ "$PASSWORD" != "$PASSWORD2" ]; then
    echo "ERROR: Passwords do not match."
    cleanup_and_exit 1
fi

# ── Step 1: Get session ID ─────────────────────────────────────────────────────
echo ">>> Step 1/2: Getting registration session from server"
SESSION_RESPONSE=$(curl -sf \
    -X POST "${REGISTER_URL}?kind=user" \
    -H "Content-Type: application/json" \
    -d '{"kind":"user"}' 2>&1 || true)

SESSION_ID=$(echo "$SESSION_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('session', ''))
" 2>/dev/null || true)

if [ -z "$SESSION_ID" ]; then
    echo "    WARNING: Could not extract session ID from server response."
    echo "    Response was: $SESSION_RESPONSE"
    echo "    Proceeding without session ID (some Conduit versions allow this)."
fi

# ── Step 2: Register with credentials + token ─────────────────────────────────
echo ">>> Step 2/2: Registering user"

AUTH_BLOCK="{\"type\":\"m.login.registration_token\",\"token\":\"${CONDUIT_REGISTRATION_TOKEN}\""
if [ -n "$SESSION_ID" ]; then
    AUTH_BLOCK="${AUTH_BLOCK},\"session\":\"${SESSION_ID}\""
fi
AUTH_BLOCK="${AUTH_BLOCK}}"

HTTP_STATUS=$(curl -s \
    -o /tmp/conduit_register_response.json \
    -w "%{http_code}" \
    -X POST "${REGISTER_URL}?kind=user" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"${ADMIN_USER}\",
        \"password\": \"${PASSWORD}\",
        \"auth\": ${AUTH_BLOCK}
    }")

echo ">>> Response (HTTP $HTTP_STATUS):"
python3 -m json.tool /tmp/conduit_register_response.json 2>/dev/null \
    || cat /tmp/conduit_register_response.json
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "================================================================"
    echo "  Admin user @${ADMIN_USER}:${MATRIX_SERVER_NAME} created."
    cleanup_and_exit 0
else
    echo "ERROR: Registration failed (HTTP $HTTP_STATUS). Check response above."
    cleanup_and_exit 1
fi
