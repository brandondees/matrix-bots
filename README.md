# matrix-bots

Infrastructure and configuration for a self-hosted Matrix homeserver (Conduit) on DigitalOcean, with bots connecting an OpenFang installation.

Stack: **Conduit** (Matrix homeserver) + **Caddy** (reverse proxy / TLS) via Docker Compose.

## Architecture

```
Internet
   │
   ├── :80/:443   ──► Caddy ──► Conduit (6167)
   └── :8448      ──► Caddy ──► Conduit (6167, Matrix federation)
```

TLS certificates are provisioned automatically by Caddy via Let's Encrypt.

---

## Prerequisites

- macOS or Linux on your local machine
- DigitalOcean droplet already created (Ubuntu 22.04 LTS recommended)
- SSH key added to the droplet at creation time
- A domain name with DNS managed via Namecheap (or any registrar)
- `dig` installed locally (`brew install bind` on macOS if missing)

---

## Setup

### Step 0 — Configure your environment  *(manual, ~2 min)*

```bash
cp .env.example .env
$EDITOR .env
```

Fill in:

| Variable | Description | Example |
|---|---|---|
| `DROPLET_IP` | Your droplet's IP address | `1.2.3.4` |
| `SSH_KEY` | Path to your SSH private key | `~/.ssh/id_ed25519` |
| `DROPLET_USER` | Non-root user to create | `matrix` |
| `DOMAIN` | Your root domain | `example.com` |
| `MATRIX_SUBDOMAIN` | Subdomain for Matrix | `matrix` → `matrix.example.com` |

Your Matrix homeserver will be at `https://${MATRIX_SUBDOMAIN}.${DOMAIN}`.
Your MXIDs will look like `@you:matrix.example.com`.

---

### Step 1-4 — Run automated setup

```bash
./setup.sh
```

This runs four steps automatically, pausing once for manual DNS configuration:

| Step | What it does | Manual? |
|---|---|---|
| 1 | Secure the droplet (create user, harden SSH, firewall) | No |
| 2 | Install Docker | No |
| 3 | **Add DNS records** (see below) | **Yes** |
| 4 | Deploy Matrix stack (Conduit + Caddy) | No |

### DNS records to add in Namecheap  *(during Step 3 pause)*

In Namecheap → Domain List → your domain → **Advanced DNS**:

| Type | Host | Value | TTL |
|---|---|---|---|
| A Record | `matrix` | `<your droplet IP>` | Automatic |

Wait for propagation before continuing (usually 1–5 min with Namecheap).
The script will verify resolution before proceeding.

---

### Step 5 — Create your admin user  *(run after setup.sh completes)*

```bash
bash scripts/04-create-admin.sh
```

This:
1. Temporarily enables registration with a one-time token
2. Registers your admin user via the Matrix API
3. Immediately disables registration again

You'll be prompted for a username and password interactively. The password is never written to disk or shell history.

---

### Step 6 — Verify  *(manual, ~1 min)*

Check federation is working:
```
https://federationtester.matrix.org/#matrix.example.com
```

Connect a client (Element Desktop, FluffyChat, etc.):
- Homeserver URL: `https://matrix.example.com`
- Log in with the credentials from Step 5

---

## Day-to-day operations

### SSH into the droplet
```bash
source .env
ssh -i "${SSH_KEY}" "${DROPLET_USER}@${DROPLET_IP}"
```

### View logs
```bash
# On the droplet:
cd ~/matrix
docker compose logs -f
docker compose logs -f conduit
docker compose logs -f caddy
```

### Restart services
```bash
cd ~/matrix
docker compose restart
```

### Update Conduit and Caddy
```bash
cd ~/matrix
docker compose pull
docker compose up -d
```

### Add another user
Edit `~/matrix/conduit/conduit.toml` on the droplet:
```toml
allow_registration = true
registration_token = "some-random-token"
```
Restart conduit, have the user register with that token, then remove the token and restart again.

---

## Redeploy from scratch

If you need to re-render and push config changes from this repo:
```bash
bash scripts/03-deploy-matrix.sh
```

---

## OpenFang integration

In your OpenFang config, add a Matrix channel pointing at your homeserver.
Create a dedicated bot user first:

1. Run `bash scripts/04-create-admin.sh` again with a bot username (e.g. `fangbot`)
2. Use the bot's MXID and credentials in OpenFang's `channels.matrix` config:
   ```yaml
   homeserver_url: https://matrix.example.com
   user_id: "@fangbot:matrix.example.com"
   access_token: "<token from login>"
   ```

To get an access token for the bot:
```bash
curl -X POST "https://matrix.example.com/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"fangbot","password":"<password>"}'
```

---

## Repository structure

```
.
├── setup.sh                    # Master orchestration script
├── .env.example                # Config template (copy to .env)
├── .gitignore
├── config/
│   ├── conduit.toml.template   # Conduit homeserver config
│   ├── Caddyfile.template      # Caddy reverse proxy config
│   └── docker-compose.yml      # Docker Compose stack
└── scripts/
    ├── 01-secure-droplet.sh    # Harden SSH, create user, configure firewall
    ├── 02-install-docker.sh    # Install Docker
    ├── 03-deploy-matrix.sh     # Render templates and deploy stack
    └── 04-create-admin.sh      # Create first/additional Matrix users
```

The `config/` directory contains templates with `__PLACEHOLDER__` variables. Scripts render them using `sed` before copying to the server — no extra tooling required.

`.env` is gitignored. Never commit it.
