# VoiceBio Training Instructions

## 1. Setup data disk

Transfer, mount and persist data disk to brens-h100-spot (see `transfer_data_disk_between_vms.md`).


Activate and SSH into brens-h100-spot.

## 2. Clone repositories and setup environment

```bash
git clone git@github.com:brendan-sp/my_vm_init.git
git clone git@github.com:snowcrash-labs/voiceID.git
cd voiceID
git fetch origin spot-instance-handling:spot-instance-handling
git switch spot-instance-handling
```

## 3. Copy augmentation data

```bash
cp -r /mnt/data/espnet_augmentations egs2/hooktheory/spk1/
mv egs2/hooktheory/spk1/espnet_augmentations/* egs2/hooktheory/spk1/
rm -r egs2/hooktheory/spk1/espnet_augmentations
```

## 4. Update dataset paths (if not already done)

Update file path references in the dataset to point to `/mnt/data/gs_imports`:

```bash
cd /mnt/data/gs_imports
time find . -type f \( -name "*.scp" -o -name "*.csv" \) -exec sed -i 's|/home/brendanoconnor/gs_imports|/mnt/data/gs_imports|g' {} +
```

Copy the pretrained checkpoint to the experiment directory (Do this whenever you want to restart training from scratch):

```bash
cp /mnt/data/model_ckpts/pretrained_12m_model_for_resumed_training_on_12m_roformered_desilenced_32khz/checkpoint.pth \
   /mnt/data/gs_imports/12m_roformered_desilenced_32khz/exp/spk_12m_roformered_32khz_6sWindow_sp/
```

## 5. Train

```bash
cd /home/brendanoconnor/my_vm_init/scripts
EXPERIMENT_DIR="/mnt/data/gs_imports/12m_roformered_desilenced_32khz/exp/spk_12m_roformered_32khz_6sWindow_sp"

# Option A: Run in detached screen (runs in background)
screen -dmS training ./train_with_preemption.sh "${EXPERIMENT_DIR}"
# Attach later with: screen -r training

# Option B: Run interactively (see output directly)
./train_with_preemption.sh "${EXPERIMENT_DIR}"
```

## 6. After VM setup and running a training script, exit and do the following to have vm run the relevant script after reboot

``` bash
gcloud compute instances add-metadata brens-a100-spot-test \
--zone=us-central1-a \
--metadata-from-file startup-script=/path/to/startup_script/on/current/device
```

## TODO: GCS bucket cleanup

Delete all directories in `gs://12m-youtube/12m_roformered_desilenced_32khz` except for `train`, `test`, and `exp`.
