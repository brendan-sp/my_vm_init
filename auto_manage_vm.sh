#!/bin/bash
# auto_manage_vm.sh - Automatically creates/restarts VM when it stops
# Usage: ./auto_manage_vm.sh [machine-type] [instance-name] [spot]
# Examples:
#   ./auto_manage_vm.sh                                    # defaults
#   ./auto_manage_vm.sh a3-highgpu-4g my-vm spot          # spot instance

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACHINE_TYPE="${1:-a3-highgpu-8g}"
INSTANCE_NAME="${2:-brens-xlarge-training}"
USE_SPOT="${3:-}"
ZONE="us-central1-a"

echo "=============================================="
echo "Auto VM Manager"
echo "=============================================="
echo "Machine Type: $MACHINE_TYPE"
echo "Instance Name: $INSTANCE_NAME"
echo "Zone: $ZONE"
echo "Spot: ${USE_SPOT:-no}"
echo "=============================================="
echo ""

cycle_count=0

while true; do
  cycle_count=$((cycle_count + 1))
  echo ""
  echo "[$(date)] ====== CYCLE $cycle_count ======"
  
  # Check if VM exists and its status
  STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --format="value(status)" 2>/dev/null)
  
  if [ -z "$STATUS" ]; then
    # VM doesn't exist - create it
    echo "[$(date)] VM does not exist. Creating..."
    "$SCRIPT_DIR/retry_create_vm.sh" "$MACHINE_TYPE" "$INSTANCE_NAME" "$USE_SPOT"
    
  elif [ "$STATUS" = "RUNNING" ]; then
    # VM is already running
    echo "[$(date)] VM is already running."
    
  elif [ "$STATUS" = "TERMINATED" ] || [ "$STATUS" = "STOPPED" ]; then
    # VM exists but is stopped - try to start it
    echo "[$(date)] VM exists but is $STATUS. Attempting to start..."
    
    while true; do
      gcloud compute instances start "$INSTANCE_NAME" --zone="$ZONE" 2>&1
      
      if [ $? -eq 0 ]; then
        echo "[$(date)] VM started successfully!"
        break
      else
        echo "[$(date)] Failed to start VM. Retrying in 300s..."
        sleep 300
      fi
    done
    
  else
    echo "[$(date)] VM status: $STATUS. Waiting..."
    sleep 60
    continue
  fi
  
  # Now monitor the VM until it stops
  echo "[$(date)] Starting VM monitor..."
  "$SCRIPT_DIR/monitor_vm.sh" "$INSTANCE_NAME" "$ZONE"
  
  echo "[$(date)] Monitor exited. VM has stopped or encountered an error."
  echo "[$(date)] Will attempt to restart in 30 seconds..."
  sleep 30
  
done
