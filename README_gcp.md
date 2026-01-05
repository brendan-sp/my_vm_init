# Google Cloud Computing Operations

## Copying data from another VM (B) to this VM (A)
You will need to do the following:
### 1. Have permissions to access the data
Check that you rxw permissions to the data
### 2. Note the _internal_ IP of VM B
Do this by accessing VM B locally or through GCP SSH terminal
### 3. Ssh-key pair
Generate a ssh-key pair by running the following:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/gcp_vm_to_vm -C "vm-to-vm"
cat ~/.ssh/gcp_vm_to_vm.pub
```
Copy the output and place it in the `/home/<targetuser>/.ssh/authorized_keys` file.
As you only have rxw permissions in `home/brendanoconnor` of VM B, <targetuser> should likely be `brendanoconnor`
Attempt to SSH into VM B with:
```bash
ssh -i ~/.ssh/gcp_vm_to_vm <targetuser>@<internal_ip>
```
### 4. Prepare data in VM B
In VM B, copy the target data into `home/brendanoconnor`
### 5. Use scp (not necesasrily the only appropriate protocol) to copy the data from VM B to VM A by running:
```bash
scp -i ~/.ssh/gcp_vm_to_vm -r <targetuser>@<internal_ip>:/home/brendanoconnor/path/to/data path/to/destination
```
For example: `scp -i ~/.ssh/gcp_vm_to_vm -r brendanoconnor@10.128.15.194:exp/spk_train_rawnet3_raw_sp spk1/`
### 6. Presuming this works, add the following to ~/.ssh/config:
```bash
Host <ssh-connection-name>
    HostName <VM-B-internal_ip>
    User brendanoconnor
    IdentityFile ~/.ssh/gcp_vm_to_vm
```


## Search for a zone that provides the machine-type you want:
``` bash
for Z in us-central1-b us-central1-c us-central1-f us-west4-b us-east1-b; do
  gcloud compute instances create brens-a2-2g-${Z//-/} \
    --zone="$Z" \                   
    --machine-type=a2-highgpu-2g \
    --maintenance-policy=TERMINATE \
    --image-family=brens-golden \
    --image-project=sc-music-research \
    --boot-disk-size=500GB \
    --boot-disk-type=pd-balanced \
    --quiet &
done
wait
```