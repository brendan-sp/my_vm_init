#!/bin/bash
# monitor_vm.sh - Monitors a VM and exits when it stops
# Usage: ./monitor_vm.sh [instance-name] [zone]

INSTANCE_NAME="${1:-brens-xlarge-training}"
ZONE="${2:-us-central1-a}"
CHECK_INTERVAL=60  # Check every 60 seconds

echo "[$(date)] Starting monitor for $INSTANCE_NAME in $ZONE"
echo "[$(date)] Checking every ${CHECK_INTERVAL}s..."

while true; do
  # Get VM status
  STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --format="value(status)" 2>/dev/null)
  
  if [ -z "$STATUS" ]; then
    echo "[$(date)] WARNING: Could not get status for $INSTANCE_NAME (VM may not exist)"
    exit 1
  fi
  
  if [ "$STATUS" = "RUNNING" ]; then
    # VM is running, continue monitoring
    echo "[$(date)] Status: RUNNING"
  elif [ "$STATUS" = "STAGING" ] || [ "$STATUS" = "PROVISIONING" ]; then
    # VM is starting up
    echo "[$(date)] Status: $STATUS (starting up...)"
  else
    # VM has stopped (TERMINATED, STOPPED, SUSPENDED, etc.)
    echo "[$(date)] Status: $STATUS - VM has stopped!"
    exit 0
  fi
  
  sleep $CHECK_INTERVAL
done
