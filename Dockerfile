# OpenClaw Gateway - Deploy-only Dockerfile
# Installs OpenClaw from npm instead of building from source.
# Update OPENCLAW_VERSION to upgrade.

ARG OPENCLAW_VERSION=2026.3.24
ARG NODE_IMAGE=node:24-bookworm-slim

FROM ${NODE_IMAGE}

ARG OPENCLAW_VERSION

WORKDIR /app

# Install system utilities required by the gateway runtime
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      procps hostname curl git lsof openssl gosu ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Enable corepack for pnpm support
RUN corepack enable

# Install OpenClaw from npm at the pinned version
RUN npm install -g "openclaw@${OPENCLAW_VERSION}"

# Create data directory for persistent state (Railway volume mount target)
RUN mkdir -p /data && chown -R node:node /data && chmod 755 /data

# Copy deploy configuration
COPY openclaw.json /app/openclaw.json
COPY start.sh /app/start.sh
RUN chown node:node /app/openclaw.json && chmod +x /app/start.sh

ENV NODE_ENV=production

# Health check against the gateway's built-in liveness endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD curl -f http://127.0.0.1:8080/healthz || exit 1

# start.sh runs as root initially to fix volume permissions, then switches to node
CMD ["/app/start.sh"]
