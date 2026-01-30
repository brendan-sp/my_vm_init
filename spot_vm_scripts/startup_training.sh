#!/bin/bash
# GCP Startup Script - Auto-resume training after Spot VM preemption
#
# Add to GCP instance metadata as 'startup-script' to enable auto-resume.
# This script runs as root on boot, so we switch to the brendanoconnor user.

# Use fixed path since GCP metadata startup scripts may run from temp location
SCRIPT_DIR="/home/brendanoconnor/my_vm_init/spot_vm_scripts"
MOUNT_POINT="/mnt/data"

# First make sure the disk is mounted (inline logic - can't rely on disk_mounter.sh on fresh VM)
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "Mounting data disk..."
    DATA_DISK=$(ls /dev/disk/by-id/google-persistent-disk-* 2>/dev/null | grep -v "persistent-disk-0" | grep -v "part" | head -n1)
    if [ -z "$DATA_DISK" ]; then
        echo "ERROR: No data disk found"
        exit 1
    fi
    mkdir -p "$MOUNT_POINT"
    mount -o discard,defaults "$DATA_DISK" "$MOUNT_POINT" || { echo "ERROR: Failed to mount data disk"; exit 1; }
    # Add to fstab if not already present
    if ! grep -q "$MOUNT_POINT" /etc/fstab; then
        echo "$DATA_DISK $MOUNT_POINT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
    fi
    echo "Data disk mounted at $MOUNT_POINT"
else
    echo "Data disk already mounted"
fi

LOG_DIR="/home/brendanoconnor/logs"
LOG_FILE="${LOG_DIR}/startup_$(date +%Y%m%d_%H%M%S).log"
EXPERIMENT_DIR="/mnt/data/gs_imports/12m_roformered_desilenced_32khz/exp/spk_12m_roformered_32khz_6sWindow_sp"
USER="brendanoconnor"
HOME_DIR="/home/brendanoconnor"

mkdir -p "$LOG_DIR"
chown "$USER:$USER" "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "$(date): VM startup script running..."

# Clone repositories if they don't exist
if [ ! -d "${HOME_DIR}/my_vm_init" ]; then
    echo "$(date): Cloning my_vm_init repository..."
    su - "$USER" -c "cd ${HOME_DIR} && git clone git@github.com:brendan-sp/my_vm_init.git"
fi

if [ ! -d "${HOME_DIR}/voiceID" ]; then
    echo "$(date): Cloning voiceID repository..."
    su - "$USER" -c "cd ${HOME_DIR} && git clone git@github.com:snowcrash-labs/voiceID.git"
    su - "$USER" -c "cd ${HOME_DIR}/voiceID && git fetch origin spot-instance-handling:spot-instance-handling && git switch spot-instance-handling"
    
    # Copy augmentation data if data/dump directories don't exist yet
    SPK1_DIR="${HOME_DIR}/voiceID/egs2/hooktheory/spk1"
    if [ -d "/mnt/data/espnet_augmentations" ] && [ ! -d "${SPK1_DIR}/data" ] && [ ! -d "${SPK1_DIR}/dump" ]; then
        echo "$(date): Copying augmentation data..."
        su - "$USER" -c "cp -r /mnt/data/espnet_augmentations ${SPK1_DIR}/"
        su - "$USER" -c "mv ${SPK1_DIR}/espnet_augmentations/* ${SPK1_DIR}/"
        su - "$USER" -c "rm -r ${SPK1_DIR}/espnet_augmentations"
    fi
fi

# Wait for GPU to be available
echo "$(date): Waiting for GPU..."
MAX_WAIT=500
WAITED=0
while ! su - "$USER" -c "nvidia-smi" &>/dev/null; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "$(date): ERROR - GPU not available after ${MAX_WAIT}s"
        exit 1
    fi
done
echo "$(date): GPU available"

# Kill any stale screen sessions from previous run (preemption may leave orphans)
if su - "$USER" -c "screen -list" 2>/dev/null | grep -q "training"; then
    echo "$(date): Cleaning up stale 'training' screen session..."
    su - "$USER" -c "screen -S training -X quit" 2>/dev/null || true
fi

# Check if there's a checkpoint to resume from
if [ -f "${EXPERIMENT_DIR}/checkpoint.pth" ]; then
    echo "$(date): Found checkpoint at ${EXPERIMENT_DIR}/checkpoint.pth"
    echo "$(date): Starting training in screen session..."
    
    # Start training as the user in a detached screen session
    su - "$USER" -c "screen -dmS training ${SCRIPT_DIR}/train_with_preemption.sh '${EXPERIMENT_DIR}'"
    
    echo "$(date): Training started in screen session 'training'"
    echo "$(date): Attach with: screen -r training"
else
    echo "$(date): No checkpoint found at ${EXPERIMENT_DIR}"
    echo "$(date): To start initial training, run manually:"
    echo "  /home/brendanoconnor/my_vm_init/spot_vm_scripts/train_with_preemption.sh ${EXPERIMENT_DIR}"
fi

echo "$(date): Startup script complete"
