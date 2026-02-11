#!/bin/bash
# GCP Startup Script - Auto-resume training after Spot VM preemption
#
# Add to GCP instance metadata as 'startup-script' to enable auto-resume.
# This script runs as root on boot, so we switch to the brendanoconnor user.

echo "========================================"
echo "STARTUP SCRIPT BEGINNING"
echo "========================================"
echo "$(date): Script started"

# Use fixed path since GCP metadata startup scripts may run from temp location
SCRIPT_DIR="/home/brendanoconnor/my_vm_init/spot_vm_scripts"
MOUNT_POINT="/mnt/data"

echo ""
echo "[Step 1/6] Checking data disk mount..."
# First make sure the disk is mounted (inline logic - can't rely on disk_mounter.sh on fresh VM)
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "  -> Data disk not mounted, searching for disk..."
    DATA_DISK=$(ls /dev/disk/by-id/google-persistent-disk-* 2>/dev/null | grep -v "persistent-disk-0" | grep -v "part" | head -n1)
    if [ -z "$DATA_DISK" ]; then
        echo "  -> ERROR: No data disk found"
        exit 1
    fi
    echo "  -> Found disk: $DATA_DISK"
    echo "  -> Creating mount point: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
    echo "  -> Mounting disk..."
    mount -o discard,defaults "$DATA_DISK" "$MOUNT_POINT" || { echo "  -> ERROR: Failed to mount data disk"; exit 1; }
    # Add to fstab if not already present
    if ! grep -q "$MOUNT_POINT" /etc/fstab; then
        echo "  -> Adding to /etc/fstab for persistence"
        echo "$DATA_DISK $MOUNT_POINT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
    fi
    echo "  -> SUCCESS: Data disk mounted at $MOUNT_POINT"
else
    echo "  -> Data disk already mounted at $MOUNT_POINT"
fi

LOG_DIR="/home/brendanoconnor/logs"
LOG_FILE="${LOG_DIR}/startup_$(date +%Y%m%d_%H%M%S).log"
EXPERIMENT_DIR="/mnt/data/gs_imports/12m_roformered_desilenced_32khz/exp/spk_12m_roformered_32khz_sp"
USER="brendanoconnor"
HOME_DIR="/home/brendanoconnor"

echo ""
echo "[Step 2/6] Setting up logging..."
mkdir -p "$LOG_DIR"
chown "$USER:$USER" "$LOG_DIR"
echo "  -> Log file: $LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "[Step 3/6] Checking repositories..."

# Clone repositories if they don't exist
if [ ! -d "${HOME_DIR}/my_vm_init" ]; then
    echo "  -> my_vm_init not found, cloning..."
    su - "$USER" -c "cd ${HOME_DIR} && git clone git@github.com:brendan-sp/my_vm_init.git"
    echo "  -> my_vm_init cloned successfully"
else
    echo "  -> my_vm_init already exists, skipping"
fi

if [ ! -d "${HOME_DIR}/voiceID" ]; then
    echo "  -> voiceID not found, cloning..."
    su - "$USER" -c "cd ${HOME_DIR} && git clone git@github.com:snowcrash-labs/voiceID.git"
    echo "  -> Switching to spot-instance-handling branch..."
    su - "$USER" -c "cd ${HOME_DIR}/voiceID && git fetch origin spot-instance-handling:spot-instance-handling && git switch spot-instance-handling"
    echo "  -> voiceID cloned and branch switched"
    
    # Copy augmentation data if data/dump directories don't exist yet
    SPK1_DIR="${HOME_DIR}/voiceID/egs2/hooktheory/spk1"
    if [ -d "/mnt/data/espnet_augmentations" ] && [ ! -d "${SPK1_DIR}/data" ] && [ ! -d "${SPK1_DIR}/dump" ]; then
        echo "  -> Copying augmentation data to ${SPK1_DIR}..."
        su - "$USER" -c "cp -r /mnt/data/espnet_augmentations ${SPK1_DIR}/"
        su - "$USER" -c "mv ${SPK1_DIR}/espnet_augmentations/* ${SPK1_DIR}/"
        su - "$USER" -c "rm -r ${SPK1_DIR}/espnet_augmentations"
        echo "  -> Augmentation data copied"
    else
        echo "  -> Skipping augmentation copy (already exists or source missing)"
    fi
else
    echo "  -> voiceID already exists, skipping"
fi

echo ""
echo "[Step 4/6] Waiting for GPU..."
MAX_WAIT=500
WAITED=0
while ! su - "$USER" -c "nvidia-smi" &>/dev/null; do
    echo "  -> GPU not ready yet, waiting... (${WAITED}s/${MAX_WAIT}s)"
    sleep 5
    WAITED=$((WAITED + 5))
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "  -> ERROR: GPU not available after ${MAX_WAIT}s"
        exit 1
    fi
done
echo "  -> GPU available and ready"

echo ""
echo "[Step 5/6] Cleaning up stale sessions..."
# Kill any stale screen sessions from previous run (preemption may leave orphans)
if su - "$USER" -c "screen -list" 2>/dev/null | grep -q "training"; then
    echo "  -> Found stale 'training' screen session, killing..."
    su - "$USER" -c "screen -S training -X quit" 2>/dev/null || true
    echo "  -> Stale session cleaned up"
else
    echo "  -> No stale screen sessions found"
fi

echo ""
echo "[Step 6/6] Checking for training checkpoint..."
echo "  -> Looking in: ${EXPERIMENT_DIR}"
# Check if there's a checkpoint to resume from
if [ -f "${EXPERIMENT_DIR}/checkpoint.pth" ]; then
    echo "  -> Found checkpoint.pth"
    echo "  -> Starting training in detached screen session..."
    
    # Start training as the user in a detached screen session
    su - "$USER" -c "screen -dmS training ${SCRIPT_DIR}/train_with_preemption.sh '${EXPERIMENT_DIR}'"
    
    echo "  -> Training started in screen session 'training'"
    echo ""
    echo "========================================"
    echo "TRAINING RESUMED SUCCESSFULLY"
    echo "========================================"
    echo "Attach to session: screen -r training"
else
    echo "  -> No checkpoint.pth found"
    echo ""
    echo "========================================"
    echo "NO CHECKPOINT - MANUAL START REQUIRED"
    echo "========================================"
    echo "To start initial training, run:"
    echo "  ${SCRIPT_DIR}/train_with_preemption.sh ${EXPERIMENT_DIR}"
fi

echo ""
echo "$(date): Startup script complete"
echo "========================================"
