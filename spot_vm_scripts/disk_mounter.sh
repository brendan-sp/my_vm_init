#!/bin/bash

MOUNT_POINT="/mnt/data"

# Skip if already mounted
if mountpoint -q "$MOUNT_POINT"; then
    echo "Already mounted"
    exit 0
fi

# Find first non-boot persistent disk
DATA_DISK=$(ls /dev/disk/by-id/google-persistent-disk-* 2>/dev/null | grep -v "persistent-disk-0" | grep -v "part" | head -n1)

if [ -z "$DATA_DISK" ]; then
    echo "ERROR: No data disk found"
    exit 1
fi

echo "Found data disk: $DATA_DISK"

# Mount it
sudo mkdir -p "$MOUNT_POINT"
sudo mount -o discard,defaults "$DATA_DISK" "$MOUNT_POINT"

# Add to fstab if not already present (makes it persistent across reboots)
if ! grep -q "$MOUNT_POINT" /etc/fstab; then
    echo "$DATA_DISK $MOUNT_POINT ext4 discard,defaults,nofail 0 2" | sudo tee -a /etc/fstab
    echo "Added to /etc/fstab for persistence"
fi
