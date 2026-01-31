#!/bin/bash
# save as: retry_create_vm.sh
# Usage: ./retry_create_vm.sh [machine-type] [instance-name] [spot]
# Examples:
#   ./retry_create_vm.sh                                    # defaults: a3-highgpu-8g, brens-xlarge-training, on-demand
#   ./retry_create_vm.sh a3-highgpu-4g                      # custom machine type
#   ./retry_create_vm.sh a3-highgpu-4g my-vm-name           # custom machine type and name
#   ./retry_create_vm.sh a3-highgpu-4g my-vm-name spot      # spot instance

MACHINE_TYPE="${1:-a3-highgpu-8g}"  # First argument, defaults to a3-highgpu-8g
INSTANCE_NAME="${2:-brens-xlarge-training}"  # Second argument, defaults to brens-xlarge-training
USE_SPOT="${3:-}"  # Third argument, set to "spot" for spot instance
ZONE="us-central1-a"
RETRY_INTERVAL=300  # 5 minutes between retries

# Build spot instance flag if requested
SPOT_FLAG=""
if [ "$USE_SPOT" = "spot" ]; then
  SPOT_FLAG="--provisioning-model=SPOT --instance-termination-action=STOP"
  echo "[INFO] Using SPOT instance"
else
  echo "[INFO] Using on-demand instance"
fi

while true; do
  echo "[$(date)] Attempting to create $INSTANCE_NAME with $MACHINE_TYPE..."
  
  gcloud compute instances create "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --boot-disk-size=500GB \
    --boot-disk-type=pd-ssd \
    --source-snapshot=brens-system-snapshot \
    --disk=name=brens-data-disk-15tb,mode=rw \
    --maintenance-policy=TERMINATE \
    --restart-on-failure \
    $SPOT_FLAG 2>&1
  
  if [ $? -eq 0 ]; then
    echo "[$(date)] SUCCESS! Instance $INSTANCE_NAME created."
    # Optional: send yourself an email/notification
    # echo "H100 VM created" | mail -s "GCP VM Ready" your@email.com
    break
  else
    echo "[$(date)] Failed. Retrying in $RETRY_INTERVAL seconds..."
    sleep $RETRY_INTERVAL
  fi
done