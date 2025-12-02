#!/usr/bin/env bash
set -euo pipefail

# 1. Update apt and install basic tools
sudo apt-get update -y
sudo apt-get install -y git rsync curl cmake sox flac libsndfile1-dev python3-venv python3-dev build-essential unzip

# Miniforge for x86_64
wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
bash Miniforge3-Linux-x86_64.sh

# suggested by Gemini to avoid conflicts with NVIDIA drivers
sudo apt install -y build-essential linux-headers-$(uname -r)
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo update-initramfs -u

# gemini suggestion: For GPUs other than NVIDIA RTX Virtual Workstations (vWS), which includes T4 and A100 for general compute workloads
curl https://raw.githubusercontent.com/GoogleCloudPlatform/compute-gpu-installation/main/linux/install_gpu_driver.py --output install_gpu_driver.py
sudo python3 install_gpu_driver.py


# Suggested by Cursor Agent to install the CUDA Toolkit to have access to nvcc
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update

# install CUDA toolkit
sudo apt-get install cuda-toolkit-12-4  # or cuda-toolkit-11-8, etc.

# Add CUDA toolkit to PATH and LD_LIBRARY_PATH
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc

# espnet conda env installation
# copy tools from latest version of repo containing the script `setup_miniforge.sh` and replace old tools dir with it
# Edited Makefile line 120
    # Replace "true" with  "false"
cd voiceID/tools
CONDA_ROOT=/home/brendanoconnor/miniforge3
./setup_miniforge.sh ${CONDA_ROOT} espnet 3.9
make TH_VERSION=2.4.1 CUDA_VERSION=12.4
conda activate espnet
# if attempting the installation again, ensure you do the following first:
conda deactivate
conda env remove -n espnet
rm *.done lightning_constraints.txt activate_python.sh