#!/bin/bash
set -e  # Exit on error

# Helper: Print usage message
usage() {
  echo "Usage: $0 <Tailscale Auth Key>"
  echo
  echo "Example: $0 tskey-auth-<YOUR_KEY>"
  exit 1
}

# Step 1: Check that the auth key is provided
if [ -z "$1" ]; then
  echo "❌ ERROR: No authentication key provided."
  usage
fi
AUTH_KEY="$1"

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

# Step 6: Log in using the provided auth key
echo "🚀 Connecting to Tailscale using the specified auth key..."
sudo tailscale up --authkey="$AUTH_KEY" --reset

echo "🎉 Tailscale setup complete via userspace mode."
