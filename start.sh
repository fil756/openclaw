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

# Merge required infrastructure config into /data/openclaw.json on every boot.
# This preserves runtime additions (Telegram, tools, etc.) while ensuring our
# deployment flags (trustedProxies, origin fallback, sandbox off) always survive.
node -e '
const fs = require("fs");
const required = {
  gateway: {
    mode: "local",
    port: 8080,
    bind: "lan",
    trustedProxies: ["100.64.0.0/10","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"],
    controlUi: {
      dangerouslyAllowHostHeaderOriginFallback: true,
      allowInsecureAuth: true,
      dangerouslyDisableDeviceAuth: true
    }
  },
  agents: {
    defaults: {
      sandbox: { mode: "off" },
      model: process.env.OPENCLAW_AGENT_MODEL || "anthropic/claude-3-5-haiku-20241022"
    }
  }
};
function merge(target, source) {
  for (const key of Object.keys(source)) {
    if (source[key] && typeof source[key] === "object" && !Array.isArray(source[key])) {
      if (!target[key] || typeof target[key] !== "object") target[key] = {};
      merge(target[key], source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}
let config = {};
try { config = JSON.parse(fs.readFileSync("/data/openclaw.json", "utf8")); } catch {}
merge(config, required);
// Clean up invalid keys written by previous deploys
if (config.agents && config.agents.defaults) {
  delete config.agents.defaults.modelFallbacks;
}
fs.writeFileSync("/data/openclaw.json", JSON.stringify(config, null, 2) + "\n");
'
chown node:node /data/openclaw.json

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
