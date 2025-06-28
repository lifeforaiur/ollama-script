#!/bin/bash
set -e  # Exit on error

# Pre-configure and use noninteractive mode
echo "gdm3 shared/default-x-display-manager select gdm3" | sudo debconf-set-selections && \
sudo DEBIAN_FRONTEND=noninteractive apt-get update && \
sudo DEBIAN_FRONTEND=noninteractive apt install -y net-tools tmux htop nano wget curl unzip zip unrar p7zip-full openssh-server xfce4 fonts-wqy-zenhei ffmpeg nvtop libgoogle-perftools4 libtcmalloc-minimal4 synaptic converseen xarchiver rclone rclone-browser thunar-archive-plugin baobab file-roller htop xfce4-goodies notepadqq geany scite nano gedit vulkan-tools xrdp konsole && \
curl -LsSf https://astral.sh/uv/install.sh | sh && \
source $HOME/.local/bin/env
