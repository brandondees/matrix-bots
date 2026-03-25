#!/usr/bin/env bash
# =============================================================================
# 05-create-bot-user.sh
# Run from your LOCAL machine (not the droplet).
# Creates the openfang-bot Matrix account using the registration token flow.
# Reads credentials from .env — nothing sensitive is sent to the droplet.
#
# Usage (from repo root):
#   bash scripts/05-create-bot-user.sh
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
: "${MATRIX_SERVER_NAME:?MATRIX_SERVER_NAME must be set in .env}"
: "${CONDUIT_REGISTRATION_TOKEN:?CONDUIT_REGISTRATION_TOKEN must be set in .env}"
: "${OPENFANG_BOT_PASSWORD:?OPENFANG_BOT_PASSWORD must be set in .env}"

BOT_USER="openfang-bot"
HOMESERVER_URL="https://${MATRIX_SERVER_NAME}"
REGISTER_URL="${HOMESERVER_URL}/_matrix/client/v3/register"
SSH_OPTS="-i ${DROPLET_SSH_KEY} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
REMOTE="${DEPLOY_USER}@${DROPLET_IP}"
CONDUIT_TOML="/home/${DEPLOY_USER}/matrix-bots/matrix/conduit/conduit.toml"
MATRIX_DIR="/home/${DEPLOY_USER}/matrix-bots/matrix"

cleanup_and_exit() {
    local exit_code="${1:-1}"
    echo ">>> Disabling registration on droplet"
    ssh $SSH_OPTS "$REMOTE" \
        "sed -i 's/^allow_registration = true/allow_registration = false/' $CONDUIT_TOML \
         && docker compose -f $MATRIX_DIR/docker-compose.yml restart conduit"
    exit "$exit_code"
}
trap 'cleanup_and_exit 1' ERR

echo "================================================================"
echo "  Creating bot user @${BOT_USER}:${MATRIX_SERVER_NAME}"
echo "  Homeserver: ${HOMESERVER_URL}"
echo "================================================================"
echo ""

# ── Enable registration on the droplet ────────────────────────────────────────
echo ">>> Enabling registration on droplet"
ssh $SSH_OPTS "$REMOTE" \
    "sed -i 's/^allow_registration = false/allow_registration = true/' $CONDUIT_TOML \
     && docker compose -f $MATRIX_DIR/docker-compose.yml restart conduit"

echo "    Waiting for Conduit to be ready..."
for i in $(seq 1 15); do
    if curl -sf "${HOMESERVER_URL}/_matrix/client/versions" -o /dev/null 2>&1; then
        echo "    Conduit is ready."
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "ERROR: Conduit did not become ready in time."
        cleanup_and_exit 1
    fi
    sleep 2
done

# ── Step 1: Get session ID ─────────────────────────────────────────────────────
echo ">>> Step 1/2: Getting registration session"
SESSION_RESPONSE=$(curl -s \
    -X POST "${REGISTER_URL}?kind=user" \
    -H "Content-Type: application/json" \
    -d '{"kind":"user"}' || true)

SESSION_ID=$(echo "$SESSION_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('session', ''))
" 2>/dev/null || true)

# ── Step 2: Register ───────────────────────────────────────────────────────────
echo ">>> Step 2/2: Registering @${BOT_USER}"

AUTH_BLOCK="{\"type\":\"m.login.registration_token\",\"token\":\"${CONDUIT_REGISTRATION_TOKEN}\""
[ -n "$SESSION_ID" ] && AUTH_BLOCK="${AUTH_BLOCK},\"session\":\"${SESSION_ID}\""
AUTH_BLOCK="${AUTH_BLOCK}}"

HTTP_STATUS=$(curl -s \
    -o /tmp/bot_register_response.json \
    -w "%{http_code}" \
    -X POST "${REGISTER_URL}?kind=user" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"${BOT_USER}\",
        \"password\": \"${OPENFANG_BOT_PASSWORD}\",
        \"auth\": ${AUTH_BLOCK}
    }")

echo ">>> Response (HTTP $HTTP_STATUS):"
python3 -m json.tool /tmp/bot_register_response.json 2>/dev/null \
    || cat /tmp/bot_register_response.json
echo ""

if [ "$HTTP_STATUS" != "200" ]; then
    echo "ERROR: Registration failed (HTTP $HTTP_STATUS)."
    cleanup_and_exit 1
fi

# ── Disable registration ───────────────────────────────────────────────────────
echo ">>> Disabling registration on droplet"
ssh $SSH_OPTS "$REMOTE" \
    "sed -i 's/^allow_registration = true/allow_registration = false/' $CONDUIT_TOML \
     && docker compose -f $MATRIX_DIR/docker-compose.yml restart conduit"

# ── Get access token ───────────────────────────────────────────────────────────
echo ""
echo ">>> Fetching access token for @${BOT_USER}"
echo "    Waiting for Conduit to be ready..."
for i in $(seq 1 15); do
    if curl -sf "${HOMESERVER_URL}/_matrix/client/versions" -o /dev/null 2>&1; then
        break
    fi
    [ "$i" -eq 15 ] && echo "ERROR: Conduit not ready after restart." && exit 1
    sleep 2
done

curl -s -X POST "${HOMESERVER_URL}/_matrix/client/v3/login" \
    -H "Content-Type: application/json" \
    -d "{
        \"type\": \"m.login.password\",
        \"identifier\": {\"type\": \"m.id.user\", \"user\": \"${BOT_USER}\"},
        \"password\": \"${OPENFANG_BOT_PASSWORD}\"
    }" | python3 -m json.tool

echo ""
echo "================================================================"
echo "  Bot user @${BOT_USER}:${MATRIX_SERVER_NAME} created."
echo "  Copy the access_token above into your OpenFang config."
echo "================================================================"
