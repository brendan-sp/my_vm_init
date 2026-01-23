#!/bin/bash
# Monitors GCP metadata for Spot VM preemption signal
# Sends SIGTERM to training process when preemption detected
#
# Usage: ./preemption_monitor.sh &
#
# GCP provides a 30-second warning before Spot VM termination.
# This script polls the metadata server every second and sends
# SIGTERM to the training process when preemption is imminent.

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/preempted"
LOG_FILE="/home/brendanoconnor/logs/preemption_monitor.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log "Preemption monitor started (PID: $$)"

while true; do
    status=$(curl -s -H "Metadata-Flavor: Google" "${METADATA_URL}" 2>/dev/null)
    
    if [ "$status" = "TRUE" ]; then
        log "PREEMPTION DETECTED - sending SIGTERM to training processes"
        
        # Send SIGTERM to ESPnet training (triggers graceful checkpoint save)
        pkill -TERM -f "espnet2.bin.spk_train"
        
        log "Shutdown signal sent. Exiting monitor."
        exit 0
    fi
    
    sleep 1
done
