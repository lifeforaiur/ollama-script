#!/bin/bash

# 1. Verify running user
EXPECTED_USER="ubuntu-xrdp"
CURRENT_USER=$(whoami)

if [ "$CURRENT_USER" != "$EXPECTED_USER" ]; then
    echo "ERROR: This script must be run as user: $EXPECTED_USER"
    echo "Currently running as: $CURRENT_USER"
    exit 1
fi

# Exit on error, but we will handle the apt error specifically
set -e

# Prevent interactive popups
export DEBIAN_FRONTEND=noninteractive

echo "--- Starting Automated System Setup for $EXPECTED_USER ---"

# 2. Improved Swap Logic
if [ ! -f /swapfile ]; then
    echo "Creating 50G swap file..."
    sudo dd if=/dev/zero of=/swapfile bs=1M count=51200 status=progress
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile || echo "WARNING: swapon failed. Check virtualization limits."
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
fi

# 3. Pre-seed Display Manager to avoid the gdm3/lightdm popup
echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections

# 4. System Updates and Software Installation
echo "Installing software packages..."
sudo apt-get update

# We use || true here because 'atop' often exits with a non-zero code during service start
sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    net-tools tmux htop nano wget curl unzip zip unrar p7zip-full \
    openssh-server xfce4 lightdm fonts-wqy-zenhei ffmpeg nvtop \
    libgoogle-perftools4 libtcmalloc-minimal4 synaptic converseen \
    xarchiver rclone rclone-browser thunar-archive-plugin baobab \
    file-roller xfce4-goodies notepadqq geany scite gedit \
    vulkan-tools xrdp atop konsole fonts-liberation || sudo apt-get install -y -f

# 5. Configure XRDP for XFCE
echo "xfce4-session" > ~/.xsession
sudo systemctl enable xrdp
sudo systemctl restart xrdp

# 6. Install Miniconda
if [ ! -d "$HOME/miniconda3" ]; then
    echo "Installing Miniconda..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -u -p ~/miniconda3
    rm /tmp/miniconda.sh
    ~/miniconda3/bin/conda init bash
fi

# 7. Install VS Code
wget -O /tmp/vscode.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64'
sudo dpkg -i /tmp/vscode.deb || sudo apt install -y -f
rm /tmp/vscode.deb

# 8. Install uv (Python manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 9. Install Google Chrome
wget -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i /tmp/google-chrome.deb || sudo apt install -y -f
rm /tmp/google-chrome.deb

# 10. Install Docker & Nvidia Toolkit
if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com/ | sh
    sudo usermod -aG docker $USER
fi

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# 11. Install Tailscale & Ollama
curl -fsSL https://tailscale.com/install.sh | sh
curl -fsSL https://ollama.com/install.sh | sh

echo "------------------------------------------------"
echo "SETUP COMPLETE FOR $EXPECTED_USER"
echo "------------------------------------------------"
