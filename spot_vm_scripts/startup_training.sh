#!/bin/bash
# GCP Startup Script - Auto-resume training after Spot VM preemption
#
# Add to GCP instance metadata as 'startup-script' to enable auto-resume.
# This script runs as root on boot, so we switch to the brendanoconnor user.

LOG_DIR="/home/brendanoconnor/logs"
LOG_FILE="${LOG_DIR}/startup_$(date +%Y%m%d_%H%M%S).log"
EXPERIMENT_DIR="/mnt/data/gs_imports/12m_roformered_desilenced_32khz/exp/spk_12m_roformered_32khz_6sWindow_sp"
USER="brendanoconnor"

mkdir -p "$LOG_DIR"
chown "$USER:$USER" "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "$(date): VM startup script running..."

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

# Check if there's a checkpoint to resume from
if [ -f "${EXPERIMENT_DIR}/checkpoint.pth" ]; then
    echo "$(date): Found checkpoint at ${EXPERIMENT_DIR}/checkpoint.pth"
    echo "$(date): Starting training in screen session..."
    
    # Start training as the user in a detached screen session
    su - "$USER" -c "screen -dmS training /home/brendanoconnor/my_vm_init/scripts/train_with_preemption.sh '${EXPERIMENT_DIR}'"
    
    echo "$(date): Training started in screen session 'training'"
    echo "$(date): Attach with: screen -r training"
else
    echo "$(date): No checkpoint found at ${EXPERIMENT_DIR}"
    echo "$(date): To start initial training, run manually:"
    echo "  /home/brendanoconnor/my_vm_init/scripts/train_with_preemption.sh ${EXPERIMENT_DIR}"
fi

echo "$(date): Startup script complete"
