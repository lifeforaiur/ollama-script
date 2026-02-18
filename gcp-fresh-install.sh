#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "--- Starting System Setup ---"

# 1. Swap File Creation (50GB)
if [ ! -f /swapfile ]; then
    echo "Creating 50G swap file..."
    sudo fallocate -l 50G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    grep SwapTotal /proc/meminfo
else
    echo "Swapfile already exists, skipping."
fi

# 2. Update and Install Base Software
echo "Updating packages and installing software..."
sudo apt-get update
sudo apt-get install -y \
    net-tools tmux htop nano wget curl unzip zip unrar p7zip-full \
    openssh-server xfce4 fonts-wqy-zenhei ffmpeg nvtop \
    libgoogle-perftools4 libtcmalloc-minimal4 synaptic converseen \
    xarchiver rclone rclone-browser thunar-archive-plugin baobab \
    file-roller xfce4-goodies notepadqq geany scite gedit \
    vulkan-tools xrdp atop konsole fonts-liberation

# 3. Install Miniconda
if [ ! -d "$HOME/miniconda3" ]; then
    echo "Installing Miniconda..."
    mkdir -p ~/miniconda3
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
    bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
    rm ~/miniconda3/miniconda.sh
    ~/miniconda3/bin/conda init bash
else
    echo "Miniconda already installed."
fi

# 4. Install VS Code
echo "Installing VS Code..."
wget -O /tmp/vscode.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64'
sudo dpkg -i /tmp/vscode.deb || sudo apt install -y -f
rm /tmp/vscode.deb

# 5. Install uv (Python manager)
echo "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

# 6. Install Google Chrome
echo "Installing Google Chrome..."
wget -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i /tmp/google-chrome.deb || sudo apt install -y -f
rm /tmp/google-chrome.deb

# 7. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -sSL https://get.docker.com/ | sh
    sudo usermod -aG docker $USER
fi

# 8. Install NVIDIA Container Toolkit
echo "Installing NVIDIA Container Toolkit..."
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# 9. Install Tailscale
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# 10. Install Ollama
echo "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

echo "--- Setup Complete! ---"
echo "Note: Please log out and back in for Docker group changes to take effect."
