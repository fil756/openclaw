# OpenClaw Deploy

Deploy-only repository for running [OpenClaw](https://github.com/openclaw/openclaw) on Railway (or any Docker host). Contains **only configuration files** — no application source code.

## Repository Structure

```
openclaw-deploy/
├── Dockerfile         # Installs OpenClaw from npm at a pinned version
├── openclaw.json      # Gateway configuration (auth, proxies, Control UI)
├── start.sh           # Container startup script (permissions, state migration)
├── railway.toml       # Railway deployment settings
├── .env.example       # Environment variable template
└── README.md
```

## Initial Setup

### 1. Create a GitHub repo

```bash
cd openclaw-deploy
git init
git add .
git commit -m "Initial OpenClaw deploy config"
git remote add origin https://github.com/YOUR_USER/openclaw-deploy.git
git push -u origin main
```

### 2. Deploy to Railway

1. Create a new project in [Railway](https://railway.com)
2. Connect your `openclaw-deploy` GitHub repo
3. Add a **Volume** mounted at `/data`
4. Set **Service Variables**:
   - `OPENCLAW_GATEWAY_TOKEN` — a strong secret token for dashboard access
   - `ANTHROPIC_API_KEY` — your Anthropic API key
   - Any other provider API keys as needed

Railway will auto-detect the `Dockerfile` and deploy.

### 3. Access the Dashboard

Open your Railway service URL in a browser. On first connect, approve the device:

```bash
# Via Railway shell
openclaw devices approve --latest
```

## Upgrading OpenClaw

To upgrade to a new version, edit one line in `Dockerfile`:

```dockerfile
ARG OPENCLAW_VERSION=2026.3.23    # ← change this to the new version
```

Then commit and push:

```bash
git add Dockerfile
git commit -m "Upgrade OpenClaw to vXXXX.X.XX"
git push
```

Railway will automatically rebuild and redeploy with the new version. Your configuration and state in `/data` are preserved across upgrades.

### Checking for New Versions

```bash
npm view openclaw version
```

Or watch the [OpenClaw releases page](https://github.com/openclaw/openclaw/releases).

## Configuration Reference

### `openclaw.json`

| Key | Description |
|-----|-------------|
| `gateway.mode` | Gateway mode (`local` for single-user) |
| `gateway.port` | Listen port (must match Railway port config) |
| `gateway.bind` | `lan` for Railway (binds to 0.0.0.0), `loopback` for local-only |
| `gateway.trustedProxies` | CIDR ranges of trusted proxy IPs (Railway uses 100.64.0.0/10) |
| `gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback` | Use Host header for origin validation (required behind Railway's TLS proxy) |
| `gateway.controlUi.allowedOrigins` | Explicit allowed origins (alternative to Host header fallback) |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | **Required.** Auth token for dashboard and API access |
| `ANTHROPIC_API_KEY` | API key for Anthropic models |
| `OPENAI_API_KEY` | API key for OpenAI models |
| `OPENCLAW_STATE_DIR` | State directory (set to `/data` for persistence) |
| `OPENCLAW_CONFIG_PATH` | Config file path (set to `/data/openclaw.json`) |
| `OPENCLAW_NO_RESPAWN` | Disable process respawn in containers (set to `1`) |

## Why This Approach?

Instead of forking the entire OpenClaw source, this repo:

- **Zero merge conflicts** — no source code to drift from upstream
- **One-line upgrades** — change the version number in `Dockerfile`
- **Clean separation** — your config is yours, the app is upstream's
- **Smaller repo** — ~6 files vs ~5000+ in the full source
