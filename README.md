# matrix-bots

Infrastructure-as-code for a self-hosted Matrix homeserver ([Conduit](https://github.com/element-hq/conduit)) on a DigitalOcean droplet, with bots wired to an [OpenFang](https://github.com/openfang) camera installation.

- **Reverse proxy**: [Caddy](https://caddyproject.dev) (auto-TLS via Let's Encrypt)
- **Homeserver**: [Conduit](https://github.com/element-hq/conduit) (lightweight, privacy-focused)
- **Containerized**: Docker Compose
- **Privacy defaults**: registration disabled, telemetry off, no update checks

---

## Prerequisites

- A DigitalOcean droplet running Ubuntu 22.04+ (already provisioned)
- Your SSH public key added to the droplet during provisioning
- A domain name with a DNS A record pointing to the droplet (see Step 1)
- This repo cloned locally

---

## SSH Key Setup (Local Machine)

If you created a dedicated SSH key for this droplet, tell your SSH client to use it.

Add a `Host` entry to `~/.ssh/config` on your local machine:

```
Host matrix-droplet
    HostName <droplet-ip>
    User root
    IdentityFile ~/.ssh/your_key_name
```

Then `ssh matrix-droplet` connects with the right key. After Step 2, change `User` to your deploy username.

---

## Step 1 — DNS Records (Manual, ~5 min + propagation)

In your Namecheap (or registrar) DNS console, add:

| Type | Host | Value |
|------|------|-------|
| `A` | `matrix` | `<your-droplet-IP>` |

This gives you `matrix.yourdomain.com` as your homeserver URL.

> **Optional**: If you want your Matrix ID to be `@you:yourdomain.com` instead of
> `@you:matrix.yourdomain.com`, you also need `.well-known` delegation. Skip this
> for now — it can be added later without disruption.

**Wait for DNS to propagate before running the deploy script.** Check with:
```bash
dig +short matrix.yourdomain.com
# Should return your droplet IP
```

---

## Step 2 — Bootstrap the Droplet (Script)

The droplet starts with no git installed. Copy the bootstrap script from your local machine, then run it as root:

```bash
# From your local machine:
scp scripts/00-bootstrap.sh root@<droplet-ip>:~/
ssh root@<droplet-ip> 'bash ~/00-bootstrap.sh <deploy-username> <repo-url>'

# Example:
ssh root@<droplet-ip> 'bash ~/00-bootstrap.sh matrix https://github.com/you/matrix-bots.git'
```

This script:
- Installs git, curl, and gettext-base (prereqs for later scripts)
- Creates a non-root deploy user and grants sudo
- Copies root's authorized_keys to the deploy user
- Hardens SSH (disables root login and password auth)
- Configures UFW to allow only ports 22, 80, 443, 8448
- Clones this repo into `/home/<deploy-username>/matrix-bots`

**Before closing your root session**, open a new terminal and verify you can log in as the new user:

```bash
ssh <deploy-username>@<droplet-ip>
```

Once confirmed, update your `~/.ssh/config` to use the deploy username, and your root session is no longer needed.

---

## Step 3 — Install Docker (Script)

SSH in as your deploy user and run:

```bash
cd ~/matrix-bots
bash scripts/02-install-docker.sh
```

Then **log out and back in** so the docker group takes effect:

```bash
exit
ssh <deploy-username>@<droplet-ip>
```

---

## Step 4 — Configure Your Environment (Manual)

On the droplet, create your `.env` file from the template:

```bash
cd ~/matrix-bots
cp .env.example .env
nano .env
```

Fill in:

| Variable | Value |
|----------|-------|
| `MATRIX_SERVER_NAME` | `matrix.yourdomain.com` |
| `DEPLOY_USER` | your deploy username |
| `CONDUIT_REGISTRATION_TOKEN` | Generate with `openssl rand -hex 32` |
| `CONDUIT_ALLOW_REGISTRATION` | leave as `false` |

`.env` is gitignored and never committed.

---

## Step 5 — Deploy the Stack (Script)

```bash
cd ~/matrix-bots
bash scripts/03-deploy.sh
```

This script:
- Validates your `.env`
- Renders `conduit.toml` from the template using your env values
- Pulls Docker images and starts Conduit + Caddy

Watch logs to confirm startup:

```bash
docker compose -f ~/matrix-bots/matrix/docker-compose.yml logs -f
```

Caddy will automatically provision a TLS certificate on first request. **DNS must be propagated first** or this fails.

---

## Step 6 — Create Your Admin User (Script)

```bash
cd ~/matrix-bots
bash scripts/04-create-admin.sh yourusername
```

This script:
1. Temporarily enables registration in `conduit.toml`
2. Restarts Conduit and waits for it to be ready
3. Runs the Matrix two-step registration flow with your token
4. Prompts for a password
5. Disables registration and restarts Conduit

After this, registration is permanently closed.

---

## Step 7 — Verify

Check federation is working:

```
https://federationtester.matrix.org/#matrix.yourdomain.com
```

---

## Step 8 — Connect a Client

Install [Element Desktop](https://element.io/download) or [FluffyChat](https://fluffychat.im).

On first login, set the homeserver to `https://matrix.yourdomain.com`.

---

## Step 9 — Wire Up OpenFang

In your OpenFang config, add a Matrix channel entry. The exact keys depend on your version — check `channels.matrix` in the OpenFang docs. You'll need:

- Homeserver URL: `https://matrix.yourdomain.com`
- A bot user account (create one by re-running `04-create-admin.sh` with registration temporarily enabled again)
- The room ID you want the bot to post to

---

## Repo Structure

```
.
├── .env.example                  # Template — copy to .env, never commit .env
├── .gitignore
├── scripts/
│   ├── 00-bootstrap.sh           # scp to droplet and run as root — installs prereqs, clones repo, hardens SSH
│   ├── 01-secure-droplet.sh      # Called by 00-bootstrap.sh; also safe to run standalone
│   ├── 02-install-docker.sh      # Run as deploy user: install Docker + gettext-base
│   ├── 03-deploy.sh              # Render configs + start Docker Compose
│   └── 04-create-admin.sh        # Register initial admin user via Matrix API
└── matrix/
    ├── docker-compose.yml
    ├── conduit/
    │   └── conduit.toml.template # Rendered to conduit.toml by deploy script
    └── caddy/
        └── config/
            └── Caddyfile
```

---

## Day-2 Operations

**Restart the stack:**
```bash
docker compose -f ~/matrix-bots/matrix/docker-compose.yml restart
```

**Update images:**
```bash
cd ~/matrix-bots/matrix
docker compose pull && docker compose up -d
```

**View logs:**
```bash
docker compose -f ~/matrix-bots/matrix/docker-compose.yml logs -f [conduit|caddy]
```

**Backup Conduit data:**
```bash
# The named volume 'matrix_conduit_data' holds all message data
docker run --rm \
    -v matrix_conduit_data:/data \
    -v $(pwd):/backup \
    alpine tar czf /backup/conduit-backup-$(date +%Y%m%d).tar.gz /data
```

---

## Privacy Notes

- Registration is disabled by default — no one can create accounts without your token
- `allow_check_for_updates = false` prevents Conduit from phoning home
- Caddy only logs to stdout (no persistent access logs by default)
- All traffic is TLS; Caddy handles cert rotation automatically
- The `conduit_data` Docker volume is local to the droplet — back it up to an encrypted destination
