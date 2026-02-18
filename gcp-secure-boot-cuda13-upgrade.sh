#!/bin/bash
# Fully Automated CUDA 13.0 for GCP Secure Boot (Version 3.0)
# Handles background apt locks and uses pre-signed modules.

set -e

# --- Function to wait for apt lock ---
wait_for_apt() {
    echo "Checking for background package manager locks..."
    while sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
        echo "Waiting for other package manager process to finish..."
        sleep 5
    done
    echo "Lock released. Proceeding..."
}

echo "--- 1. Handling Apt Locks ---"
wait_for_apt

echo "--- 2. Cleaning up failed installs ---"
sudo apt-get purge -y "*nvidia*" "*cuda*"
sudo apt-get autoremove -y

echo "--- 3. Installing Pre-signed Driver for Secure Boot ---"
# We target the 'server' driver which Ubuntu pre-signs for their kernels.
KERNEL_VER=$(uname -r)
DRIVER_VER="580"

wait_for_apt
sudo apt-get update
sudo apt-get install -y \
    linux-modules-nvidia-${DRIVER_VER}-server-${KERNEL_VER} \
    nvidia-utils-${DRIVER_VER}-server \
    nvidia-compute-utils-${DRIVER_VER}-server \
    libnvidia-compute-${DRIVER_VER}-server

echo "--- 4. Installing CUDA 13.0 Toolkit ---"
wait_for_apt
# Download keyring (using -O to overwrite previous partial downloads)
wget -O cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring.deb
sudo apt-get update

# Install ONLY the toolkit to avoid overwriting our signed driver
sudo apt-get install -y cuda-toolkit-13-0

echo "--- 5. Configuring Environment Variables ---"
# Check if already in .bashrc to prevent duplicates
if ! grep -q "/usr/local/cuda-13.0/bin" ~/.bashrc; then
    echo 'export PATH=/usr/local/cuda-13.0/bin${PATH:+:${PATH}}' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.bashrc
fi

# Export for the current session too
export PATH=/usr/local/cuda-13.0/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

echo "--------------------------------------------------------"
echo " INSTALLATION COMPLETE "
echo " System will reboot in 5 seconds... "
echo "--------------------------------------------------------"
sleep 5
sudo reboot
