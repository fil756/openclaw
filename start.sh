#!/bin/bash
set -e

echo "Starting OpenClaw Gateway..."

# Fix data directory permissions (Railway mounts volumes as root)
if [ -d /data ]; then
  chown -R node:node /data
  chmod -R 755 /data
fi

mkdir -p /data

# Migrate legacy state if present
legacy_state_dir="${HOME:-/home/node}/.openclaw"
if [ -d "$legacy_state_dir" ] && [ "$legacy_state_dir" != "/data" ]; then
  cp -a -n "$legacy_state_dir"/. /data/ 2>/dev/null || true
  chown -R node:node /data
fi

# Only seed config on first boot — never overwrite runtime config in /data
if [ ! -f /data/openclaw.json ] && [ -f /app/openclaw.json ]; then
  cp /app/openclaw.json /data/openclaw.json
  chown node:node /data/openclaw.json
fi

export OPENCLAW_STATE_DIR=/data
export OPENCLAW_WORKSPACE_DIR=/data/.openclaw/workspace
export OPENCLAW_CONFIG_PATH=/data/openclaw.json
export OPENCLAW_NO_RESPAWN=1
export OPENCLAW_AGENT_MODEL="${OPENCLAW_AGENT_MODEL:-anthropic/claude-3-5-haiku-20241022}"

# Symlink workspace so agent sessions use persistent volume
mkdir -p /data/.openclaw/workspace
rm -rf /home/node/.openclaw/workspace
mkdir -p /home/node/.openclaw
ln -sf /data/.openclaw/workspace /home/node/.openclaw/workspace

exec gosu node openclaw gateway run \
  --port 8080 \
  --bind lan \
  --token "${OPENCLAW_GATEWAY_TOKEN}"
