#!/bin/bash
set -e  # Exit on error

# Load credentials from .env file in the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ ERROR: .env file not found at $ENV_FILE"
  echo "Create a .env file with the following variables:"
  echo "  TS_OAUTH_CLIENT_ID=<your-client-id>"
  echo "  TS_OAUTH_CLIENT_SECRET=<your-client-secret>"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "$TS_OAUTH_CLIENT_ID" ] || [ -z "$TS_OAUTH_CLIENT_SECRET" ]; then
  echo "❌ ERROR: TS_OAUTH_CLIENT_ID and TS_OAUTH_CLIENT_SECRET must be set in .env"
  exit 1
fi

# Step 1: Install Tailscale from official source
echo "🔧 Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sudo sh

# Step 2: Write userspace systemd service file
echo "📝 Writing systemd unit file for userspace Tailscaled..."
cat <<'EOF' | sudo tee /etc/systemd/system/tailscaled-userspace.service > /dev/null
[Unit]
Description=Tailscale node agent (userspace)
Documentation=https://tailscale.com/
Wants=network-pre.target
After=network-pre.target NetworkManager.service systemd-resolved.service

[Service]
EnvironmentFile=-/etc/default/tailscaled
ExecStartPre=/usr/bin/mkdir -p /var/run/tailscale
ExecStart=/usr/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock --tun=userspace-networking
ExecStopPost=/usr/bin/rm -f /var/run/tailscale/tailscaled.sock
Restart=on-failure
RestartSec=5
KillMode=mixed
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Step 3: Stop and disable the default Tailscale service
echo "🛑 Stopping and disabling default Tailscale service..."
sudo systemctl stop tailscaled 2>/dev/null || true
sudo systemctl disable tailscaled 2>/dev/null || true

# Step 4: Enable and start the userspace service
echo "✅ Enabling and starting userspace Tailscale service..."
sudo systemctl enable tailscaled-userspace
sudo systemctl start tailscaled-userspace

HOSTNAME="ap-ollama-tailscale"

# Step 5: Exchange OAuth client credentials for a short-lived Bearer token
echo "🔑 Fetching OAuth access token..."
TOKEN_RESPONSE=$(curl -sf -X POST "https://api.tailscale.com/api/v2/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${TS_OAUTH_CLIENT_ID}" \
  -d "client_secret=${TS_OAUTH_CLIENT_SECRET}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'access_token' not in data:
    raise SystemExit('OAuth token error: ' + data.get('message', str(data)))
print(data['access_token'])
")

echo "✅ OAuth token obtained."

# Step 6: Delete existing Tailscale node(s) with same hostname
echo "🔍 Checking for existing Tailscale node with hostname '$HOSTNAME'..."
DEVICES=$(curl -sf "https://api.tailscale.com/api/v2/tailnet/-/devices" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" || true)

if [ -n "$DEVICES" ]; then
  DEVICE_IDS=$(echo "$DEVICES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for d in data.get('devices', []):
    if d.get('hostname') == '$HOSTNAME':
        print(d.get('nodeId') or d['id'])
" 2>/dev/null || true)

  if [ -n "$DEVICE_IDS" ]; then
    echo "$DEVICE_IDS" | while read -r DEVICE_ID; do
      echo "🗑️  Deleting existing node '$HOSTNAME' (ID: $DEVICE_ID)..."
      curl -sf -X DELETE "https://api.tailscale.com/api/v2/device/${DEVICE_ID}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" || true
      echo "✅ Node $DEVICE_ID deleted."
    done
  else
    echo "ℹ️  No existing node found with hostname '$HOSTNAME'."
  fi
fi

# Step 7: Generate a one-time ephemeral auth key via OAuth token
echo "🔑 Generating ephemeral auth key..."
AUTH_KEY_RESPONSE=$(curl -sf -X POST "https://api.tailscale.com/api/v2/tailnet/-/keys" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "capabilities": {
      "devices": {
        "create": {
          "reusable": false,
          "ephemeral": true,
          "preauthorized": true,
          "tags": ["tag:mbp13-auto-gen"]
        }
      }
    }
  }')

AUTH_KEY=$(echo "$AUTH_KEY_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'key' not in data:
    raise SystemExit('Auth key creation error: ' + data.get('message', str(data)))
print(data['key'])
")

echo "✅ Ephemeral auth key generated."

# Step 8: Log in using the generated ephemeral auth key
echo "🚀 Connecting to Tailscale..."
sudo tailscale up --authkey="$AUTH_KEY" --reset --hostname="$HOSTNAME"

echo "🎉 Tailscale setup complete via userspace mode."
