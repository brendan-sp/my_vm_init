#!/bin/bash
# Wrapper script for training on GCP Spot VMs
# Starts preemption monitor and runs training with resume support
#
# Usage: ./train_with_preemption.sh <experiment_directory>
# Example: ./train_with_preemption.sh /mnt/data/gs_imports/12m_roformered_desilenced_32khz/exp/spk_12m_roformered_32khz_sp

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_DIR="/home/brendanoconnor/voiceID/egs2/hooktheory/spk1"
LOG_FILE="/home/brendanoconnor/logs/training_wrapper.log"

# Require experiment directory as argument
if [ -z "$1" ]; then
    echo "Usage: $0 <experiment_directory>"
    echo "Example: $0 /mnt/data/gs_imports/12m_roformered_desilenced_32khz/exp/spk_12m_roformered_32khz_sp"
    exit 1
fi

EXPERIMENT_DIR="$1"
mkdir -p "$EXPERIMENT_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Cleaning up..."
    # Kill preemption monitor if still running
    if [ -n "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

log "Starting training with preemption support"
log "Experiment directory: $EXPERIMENT_DIR"

# Check if resuming from existing checkpoint
if [ -f "$EXPERIMENT_DIR/checkpoint.pth" ]; then
    log "Found existing checkpoint - will resume training"
else
    log "No checkpoint found - starting fresh training"
fi

# Start preemption monitor in background
"$SCRIPT_DIR/preemption_monitor.sh" &
MONITOR_PID=$!
log "Preemption monitor started (PID: $MONITOR_PID)"

# Activate conda environment
source /home/brendanoconnor/miniforge3/etc/profile.d/conda.sh
conda activate espnet

# Detect number of available GPUs
NGPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
log "Detected $NGPU GPU(s)"

# Run training with fixed experiment directory and resume enabled
cd "$TRAINING_DIR"
log "Starting training..."

./run.sh \
    --stage 5 \
    --stop_stage 5 \
    --data_dir_prefix /mnt/data/gs_imports/12m_roformered_desilenced_32khz \
    --spk_exp "$EXPERIMENT_DIR" \
    --spk_config conf/train_rawnet3_12m_8H100s.yaml \
    --use_datetime_suffix false \
    --ngpu "$NGPU" \
    --resume true

EXIT_CODE=$?
log "Training exited with code: $EXIT_CODE"

exit $EXIT_CODE
