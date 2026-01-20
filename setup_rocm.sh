#!/bin/bash

# =================================================================
# AWS G4ad (Radeon V520) ROCm Setup Script for Ubuntu 22.04
# =================================================================

set -e # Exit immediately if a command fails

echo ">>> 1. Updating System and Installing Dependencies..."
sudo apt-get update
sudo apt-get upgrade -y
# Install build tools and the specific library that fixed the <cmath> error earlier
sudo apt-get install -y build-essential cmake wget git libstdc++-12-dev

echo ">>> 2. Installing AWS Kernel Headers..."
# Crucial for the driver to interact with the AWS kernel
sudo apt-get install -y linux-modules-extra-aws linux-headers-aws linux-modules-extra-$(uname -r)

echo ">>> 3. Cleaning up any previous failed attempts..."
# Just in case this isn't a 100% fresh run, we remove broken drivers
sudo dpkg --remove --force-all amdgpu-dkms 2>/dev/null || true
sudo rm -f /etc/modprobe.d/blacklist-amdgpu.conf
sudo rm -f /etc/modprobe.d/amdgpu-dkms.conf

echo ">>> 4. Downloading AMDGPU Installer (ROCm 5.7.1)..."
# We use 5.7.1 as it is stable for RDNA1 (gfx1011)
wget -qO amdgpu-install.deb https://repo.radeon.com/amdgpu-install/5.7.1/ubuntu/jammy/amdgpu-install_5.7.50701-1_all.deb
sudo apt-get install -y ./amdgpu-install.deb
rm amdgpu-install.deb

echo ">>> 5. Installing ROCm (Skipping DKMS)..."
# We use --no-dkms because AWS kernels have the driver built-in.
# Installing DKMS usually breaks on AWS.
sudo amdgpu-install -y --usecase=rocm,hiplibsdk,rocmdev --no-dkms

echo ">>> 6. Configuring Environment Workarounds..."
# 1. Add ROCm to PATH
if ! grep -q "/opt/rocm/bin" /etc/profile.d/rocm.sh 2>/dev/null; then
    echo 'export PATH=$PATH:/opt/rocm/bin:/opt/rocm/rocprofiler/bin:/opt/rocm/opencl/bin' | sudo tee /etc/profile.d/rocm.sh
fi

# 2. Add user to render/video groups
sudo usermod -aG render,video $USER

# 3. Apply the GFX Version Override (Crucial for V520)
# We append this to .bashrc so it persists after reboot
if ! grep -q "HSA_OVERRIDE_GFX_VERSION" ~/.bashrc; then
    echo 'export HSA_OVERRIDE_GFX_VERSION=10.1.0' >> ~/.bashrc
fi

echo "==========================================================="
echo "INSTALLATION COMPLETE"
echo "==========================================================="
echo "You MUST reboot the instance now for the permissions to apply."
echo "Command: sudo reboot"
echo "==========================================================="