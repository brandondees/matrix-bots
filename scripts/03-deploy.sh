#!/usr/bin/env bash
# =============================================================================
# 03-deploy.sh
# Run as the deploy user from the root of this repo.
# Renders config templates, creates required directories, and starts the stack.
#
# Usage (from repo root):
#   cp .env.example .env && nano .env   # fill in your values first
#   bash scripts/03-deploy.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_DIR="$REPO_ROOT/matrix"
ENV_FILE="$REPO_ROOT/.env"

# ── Load environment ──────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env file not found."
    echo "  cp .env.example .env  then fill in your values."
    exit 1
fi
set -a; source "$ENV_FILE"; set +a  # values with special chars must be single-quoted in .env

: "${MATRIX_SERVER_NAME:?MATRIX_SERVER_NAME must be set in .env}"
: "${CONDUIT_REGISTRATION_TOKEN:?CONDUIT_REGISTRATION_TOKEN must be set in .env}"
: "${CONDUIT_ALLOW_REGISTRATION:=false}"

# ── Check dependencies ────────────────────────────────────────────────────────
for cmd in docker envsubst; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is not installed. Run 02-install-docker.sh first (and re-login)."
        exit 1
    fi
done

# ── Create runtime directories ────────────────────────────────────────────────
echo ">>> Creating directories"
mkdir -p "$MATRIX_DIR/caddy/data"
mkdir -p "$MATRIX_DIR/caddy/config"

# ── Render conduit.toml from template ─────────────────────────────────────────
echo ">>> Rendering conduit.toml"
TEMPLATE="$MATRIX_DIR/conduit/conduit.toml.template"
OUTPUT="$MATRIX_DIR/conduit/conduit.toml"

if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: Template not found at $TEMPLATE"
    exit 1
fi

envsubst < "$TEMPLATE" > "$OUTPUT"
echo "    Written: $OUTPUT"

# ── Start the stack ───────────────────────────────────────────────────────────
echo ">>> Starting Docker Compose stack"
cd "$MATRIX_DIR"
docker compose pull
docker compose up -d

# Restart conduit so it picks up any config changes (mounted files aren't
# detected as changes by docker compose, so an explicit restart is needed).
echo ">>> Restarting conduit to apply config"
docker compose restart conduit

echo ""
echo ">>> Stack status"
docker compose ps

echo ""
echo "================================================================"
echo "  Deployment complete."
echo ""
echo "  Watch startup logs:  docker compose -f $MATRIX_DIR/docker-compose.yml logs -f"
echo "  Caddy will auto-provision TLS certs — DNS must be propagated first."
echo ""
echo "  Next: create your admin user — see scripts/04-create-admin.sh"
echo "================================================================"
