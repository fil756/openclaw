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

# Always copy latest config to /data so changes propagate on redeploy
if [ -f /app/openclaw.json ]; then
  cp /app/openclaw.json /data/openclaw.json
  chown node:node /data/openclaw.json
fi

export OPENCLAW_STATE_DIR=/data
export OPENCLAW_CONFIG_PATH=/data/openclaw.json
export OPENCLAW_NO_RESPAWN=1

exec gosu node openclaw gateway run \
  --port 8080 \
  --bind lan \
  --token "${OPENCLAW_GATEWAY_TOKEN}"
