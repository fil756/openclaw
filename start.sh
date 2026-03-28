#!/bin/bash
set -e

echo "Starting OpenClaw Gateway..."

# Fix data directory permissions (Railway mounts volumes as root)
if [ -d /data ]; then
  chown -R node:node /data
  chmod 700 /data
  
  # Secure credentials directory
  if [ -d /data/credentials ]; then
    chmod 700 /data/credentials
    # Secure individual credential files
    find /data/credentials -type f -name '*.json' -exec chmod 600 {} \;
  fi
  
  # Secure config file
  if [ -f /data/openclaw.json ]; then
    chmod 600 /data/openclaw.json
  fi
fi

mkdir -p /data
mkdir -p /data/credentials

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
    auth: {
      token: process.env.OPENCLAW_GATEWAY_TOKEN
    },
    controlUi: {
      dangerouslyAllowHostHeaderOriginFallback: true,
      allowInsecureAuth: true,
      dangerouslyDisableDeviceAuth: true
    }
  },
  agents: {
    defaults: {
      sandbox: { mode: "off" },
      model: process.env.OPENCLAW_AGENT_MODEL || "anthropic/claude-haiku-4-5",
      models: {
        "anthropic/claude-haiku-4-5": { alias: "Haiku" },
        "anthropic/claude-sonnet-4-6": { alias: "Sonnet" },
        "anthropic/claude-opus-4-6": { alias: "Opus" }
      },
      heartbeat: {
        every: "60m",
        model: "openrouter/google/gemini-2.5-flash-lite",
        target: "last",
        lightContext: true,
        isolatedSession: true
      }
    }
  },
  tools: {
    profile: "coding"
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
  if (config.agents.defaults.heartbeat) {
    delete config.agents.defaults.heartbeat.intervalMinutes;
  }
}
if (config.channels && config.channels.telegram) {
  delete config.channels.telegram.dmAllowlist;
}
// Replace broken model IDs throughout the entire config
let out = JSON.stringify(config, null, 2);
out = out.replace(/openrouter\/meta-llama\/llama-3\.3-70b-instruct:free/g, "openrouter/mistralai/mistral-small-3.1-24b-instruct:free");
out = out.replace(/meta-llama\/llama-3\.3-70b-instruct:free/g, "mistralai/mistral-small-3.1-24b-instruct:free");
out = out.replace(/meta-llama\/llama-3\.3-70b:free/g, "mistralai/mistral-small-3.1-24b-instruct:free");
out = out.replace(/claude-3-5-haiku-20241022/g, "claude-haiku-4-5");
fs.writeFileSync("/data/openclaw.json", out + "\n");
'
chown node:node /data/openclaw.json

# Fix broken model IDs in ALL state/session files (not just openclaw.json)
find /data -name '*.json' -type f -exec grep -l -E 'openrouter/.*:free|llama-3\.3-70b|mistral.*:free|gpt-4o-mini|claude-3-5-haiku-20241022' {} \; 2>/dev/null | while read f; do
  sed -i \
    -e 's|openrouter/meta-llama/llama-3\.3-70b-instruct:free|anthropic/claude-haiku-4-5|g' \
    -e 's|openrouter/mistralai/mistral-small-3\.1-24b-instruct:free|anthropic/claude-haiku-4-5|g' \
    -e 's|meta-llama/llama-3\.3-70b-instruct:free|claude-haiku-4-5|g' \
    -e 's|mistralai/mistral-small-3\.1-24b-instruct:free|claude-haiku-4-5|g' \
    -e 's|meta-llama/llama-3\.3-70b:free|claude-haiku-4-5|g' \
    -e 's|openai/gpt-4o-mini|anthropic/claude-haiku-4-5|g' \
    -e 's|gpt-4o-mini|claude-haiku-4-5|g' \
    -e 's|claude-3-5-haiku-20241022|claude-haiku-4-5|g' \
    "$f"
done

export OPENCLAW_STATE_DIR=/data
export OPENCLAW_WORKSPACE_DIR=/data/.openclaw/workspace
export OPENCLAW_CONFIG_PATH=/data/openclaw.json
export OPENCLAW_NO_RESPAWN=1
export OPENCLAW_AGENT_MODEL="${OPENCLAW_AGENT_MODEL:-anthropic/claude-haiku-4-5}"

# Symlink workspace so agent sessions use persistent volume
mkdir -p /data/.openclaw/workspace
rm -rf /home/node/.openclaw/workspace
mkdir -p /home/node/.openclaw
ln -sf /data/.openclaw/workspace /home/node/.openclaw/workspace

exec gosu node openclaw gateway run \
  --port 8080 \
  --bind lan \
  --token "${OPENCLAW_GATEWAY_TOKEN}"
