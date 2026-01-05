# Installations

## GPU usage

#### suggested by Gemini to avoid conflicts with NVIDIA drivers
```
sudo apt install -y build-essential linux-headers-$(uname -r)
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo update-initramfs -u
```

#### gemini suggestion: For GPUs other than NVIDIA RTX Virtual Workstations (vWS), which includes T4 and A100 for general compute workloads
```
curl https://raw.githubusercontent.com/GoogleCloudPlatform/compute-gpu-installation/main/linux/install_gpu_driver.py --output install_gpu_driver.py
sudo python3 install_gpu_driver.py
```

## VoiceID

```
conda create espnet python=3.9 -y
pip install /home/brendanoconnor/my_init/cursorAltered_espnet_requirements.txt
```


```
pip install git@github.com:snowcrash-labs/voiceID.git@970d50a71b0b87c8cec6996ebd615bdd50772730
cd voiceID
```

Because this version was made 2 years ago, Python 3.11 is too new for the packages it wants to use. We therefore need to use an older one. ESPnet docs suggest 3.8. From there we can set up a venv env. 

```
conda create -n py38 python=3.8 -y
conda activate py38
./setup_venv.sh $(which python)
```

`Cython` and `numpy` need to be pinned in advance of making the rest of the venv, as the default versions pulled will be too new at this point to work with this version of ESPnet.

ctc-segmentation and pyworld also need to be pinned with the --no-build-isolation flag, as this forces pip to install the package directly into your active environment, meaning it cannot get overridden by an additional request for another version of the package after this point, therfore respecting the pinned versions.

```
pip install "Cython==0.29.36" "numpy<1.24"
pip install --no-build-isolation "ctc-segmentation==1.7.1"
pip install --no-build-isolation "pyworld==0.3.4"
```

Now, you should be able to make the rest of the environment with

```
make
```