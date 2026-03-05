#!/bin/bash
set -e  # Exit on error

# Helper: Print usage message
usage() {
  echo "Usage: $0 <Tailscale Auth Key> [Tailscale API Key]"
  echo
  echo "Example: $0 tskey-auth-<YOUR_KEY> tskey-api-<YOUR_API_KEY>"
  echo
  echo "  Tailscale Auth Key: required, used to authenticate the node"
  echo "  Tailscale API Key:  optional, used to delete an existing node with the same hostname"
  echo "                      Can also be set via TS_API_KEY environment variable"
  exit 1
}

# Step 1: Check that the auth key is provided
if [ -z "$1" ]; then
  echo "❌ ERROR: No authentication key provided."
  usage
fi

AUTH_KEY="$1"
API_KEY="${2:-$TS_API_KEY}"

# Step 2: Install Tailscale from official source
echo "🔧 Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sudo sh

# Step 3: Write userspace systemd service file
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

# Step 4: Stop and disable the default Tailscale service
echo "🛑 Stopping and disabling default Tailscale service..."
sudo systemctl stop tailscaled 2>/dev/null || true
sudo systemctl disable tailscaled 2>/dev/null || true

# Step 5: Enable and start the userspace service
echo "✅ Enabling and starting userspace Tailscale service..."
sudo systemctl enable tailscaled-userspace
sudo systemctl start tailscaled-userspace

HOSTNAME="ap-ollama-tailscale"

# Step 6: Delete existing Tailscale node(s) with same hostname (if API key provided)
if [ -n "$API_KEY" ]; then
  echo "🔍 Checking for existing Tailscale node with hostname '$HOSTNAME'..."
  DEVICES=$(curl -sf -u "${API_KEY}:" "https://api.tailscale.com/api/v2/tailnet/-/devices" || true)
  if [ -n "$DEVICES" ]; then
    # Use python3 for reliable JSON parsing (available on all Ubuntu installs)
    DEVICE_IDS=$(echo "$DEVICES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for d in data.get('devices', []):
    if d.get('hostname') == '$HOSTNAME':
        print(d['id'])
" 2>/dev/null || true)
    if [ -n "$DEVICE_IDS" ]; then
      echo "$DEVICE_IDS" | while read -r DEVICE_ID; do
        echo "🗑️  Deleting existing node '$HOSTNAME' (ID: $DEVICE_ID)..."
        curl -sf -X DELETE -u "${API_KEY}:" "https://api.tailscale.com/api/v2/device/${DEVICE_ID}" || true
        echo "✅ Node $DEVICE_ID deleted."
      done
    else
      echo "ℹ️  No existing node found with hostname '$HOSTNAME'."
    fi
  fi
else
  echo "ℹ️  No API key provided, skipping hostname conflict check."
fi

# Step 7: Log in using the provided auth key
echo "🚀 Connecting to Tailscale using the specified auth key..."
sudo tailscale up --authkey="$AUTH_KEY" --reset --hostname="$HOSTNAME"

echo "🎉 Tailscale setup complete via userspace mode."
