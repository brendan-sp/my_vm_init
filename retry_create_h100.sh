#!/bin/bash
# save as: retry_create_h100.sh
# Usage: ./retry_create_h100.sh [machine-type]
# Example: ./retry_create_h100.sh a3-highgpu-4g

INSTANCE_NAME="brens-xlarge-training"
ZONE="us-central1-a"
MACHINE_TYPE="${1:-a3-highgpu-8g}"  # First argument, defaults to a3-highgpu-8g
RETRY_INTERVAL=300  # 5 minutes between retries

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
    --restart-on-failure 2>&1
  
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