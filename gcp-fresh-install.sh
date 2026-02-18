#!/bin/bash

# Exit on error
set -e

# Prevent interactive popups (like the Purple Screen)
export DEBIAN_FRONTEND=noninteractive

echo "--- Starting Automated System Setup ---"

# 1. Improved Swap Logic (Compatibility for more filesystems)
if [ ! -f /swapfile ]; then
    echo "Creating 50G swap file (this may take a minute)..."
    # Using dd for better compatibility than fallocate on some systems
    sudo dd if=/dev/zero of=/swapfile bs=1M count=51200 status=progress
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    # Attempt swapon, but don't crash if the environment (LXC/Container) forbids it
    sudo swapon /swapfile || echo "WARNING: swapon failed. Check if your VPS allows swap files."
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
else
    echo "Swapfile already exists, skipping."
fi

# 2. Pre-seed Display Manager choice to avoid manual selection
echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections

# 3. System Updates and Software Installation
echo "Installing software packages..."
sudo apt-get update
sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    net-tools tmux htop nano wget curl unzip zip unrar p7zip-full \
    openssh-server xfce4 lightdm fonts-wqy-zenhei ffmpeg nvtop \
    libgoogle-perftools4 libtcmalloc-minimal4 synaptic converseen \
    xarchiver rclone rclone-browser thunar-archive-plugin baobab \
    file-roller xfce4-goodies notepadqq geany scite gedit \
    vulkan-tools xrdp atop konsole fonts-liberation

# 4. Configure XRDP to use XFCE (Prevents the 'Black Screen' bug)
echo "Configuring XRDP for XFCE..."
echo "xfce4-session" > ~/.xsession
sudo systemctl enable xrdp
sudo systemctl restart xrdp

# 5. Install Miniconda
if [ ! -d "$HOME/miniconda3" ]; then
    echo "Installing Miniconda..."
    mkdir -p ~/miniconda3
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
    bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
    rm ~/miniconda3/miniconda.sh
    # Initialize conda for the current user
    ~/miniconda3/bin/conda init bash
else
    echo "Miniconda already installed."
fi

# 6. Install VS Code
echo "Installing VS Code..."
wget -O /tmp/vscode.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64'
sudo dpkg -i /tmp/vscode.deb || sudo apt install -y -f
rm /tmp/vscode.deb

# 7. Install uv (Python manager)
echo "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

# 8. Install Google Chrome
echo "Installing Google Chrome..."
wget -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i /tmp/google-chrome.deb || sudo apt install -y -f
rm /tmp/google-chrome.deb

# 9. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -sSL https://get.docker.com/ | sh
    sudo usermod -aG docker $USER
fi

# 10. NVIDIA Container Toolkit
echo "Installing NVIDIA Container Toolkit..."
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# 11. Tailscale & Ollama
echo "Installing Tailscale and Ollama..."
curl -fsSL https://tailscale.com/install.sh | sh
curl -fsSL https://ollama.com/install.sh | sh

echo "------------------------------------------------"
echo "SETUP COMPLETE!"
echo "1. Run 'source ~/.bashrc' to enable Conda/uv in this session."
echo "2. Log out and back in for Docker permissions to update."
echo "3. Connect via RDP using your server IP and user credentials."
echo "------------------------------------------------"
