sudo su - ubuntu-xrdp && \

#create 50G swap file
sudo fallocate -l 50G /swapfile && \
sudo chmod 600 /swapfile && \
sudo mkswap /swapfile && \
sudo swapon /swapfile && \
grep SwapTotal /proc/meminfo && \

# install software
sudo apt-get update && \
sudo apt install -y net-tools tmux htop nano wget curl unzip zip unrar p7zip-full openssh-server xfce4 fonts-wqy-zenhei ffmpeg nvtop libgoogle-perftools4 libtcmalloc-minimal4 synaptic converseen xarchiver rclone rclone-browser thunar-archive-plugin baobab file-roller htop xfce4-goodies notepadqq geany scite nano gedit vulkan-tools xrdp atop konsole && \

# install conda
mkdir -p ~/miniconda3 && \
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh && \
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3 && \
rm ~/miniconda3/miniconda.sh && \
echo 'export PATH="$HOME/miniconda3/bin:$PATH"' >> ~/.bashrc && \
source ~/.bashrc  && \

# install vscode
wget -O vscode.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64' && \
sudo dpkg -i vscode.deb && \
sudo apt install -f && \

# install uv
curl -LsSf https://astral.sh/uv/install.sh | sh && \


# Install Chrome
RUN apt update && apt install -y fonts-liberation && \
  wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
  dpkg -i google-chrome-stable_current_amd64.deb && \
  rm google-chrome-stable_current_amd64.deb


# install docker
curl -sSL https://get.docker.com/ | sh  && \
sudo usermod -aG docker $USER  && \

#install nvidia container and refresh
sudo apt-get update  &&\
sudo apt-get install -y nvidia-container-toolkit  && \
sudo systemctl restart docker  && \
newgrp docker  && \

# install tailscale
curl -fsSL https://tailscale.com/install.sh | sh  && \

# install Ollama
curl -fsSL https://ollama.com/install.sh | sh
