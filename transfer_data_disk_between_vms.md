# get data disk name:
```bash
gcloud compute instances describe PREV-VM --zone=YOUR_ZONE --format='get(disks)'
```

# detach disk from prev_vm:
```bash
gcloud compute instances detach-disk PREV_VM \
  --disk=YOUR_DISK_NAME \
  --zone=YOUR_ZONE
```

# attach disk to target_vm_name:
```bash
gcloud compute instances attach-disk TARGET_VM_NAME \
  --disk=YOUR_DISK_NAME \
  --zone=YOUR_ZONE \
  --mode=rw
```

# on target vm mount the disk, find the disk device, mount it accordingly, verify its mounted
```bash
sudo mkdir -p /mnt/data
lsblk
sudo mount /dev/sdb /mnt/data
df -h /mnt/data
```

# make the mount persistent (so that it doesn't need to be mounted again when an instance is preempted or shutdown), then verify its mounted
```bash
sudo blkid /dev/sdb
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdb) /mnt/data ext4 defaults 0 2" | sudo tee -a /etc/fstab
cat /etc/fstab
```

# test the mount without rebooting: unmount, remount, verify
```bash
sudo umount /mnt/data
sudo mount -a
df -h /mnt/data
```
