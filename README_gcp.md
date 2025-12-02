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
### 6. Presuming this works, add the following to ~/.ssh/config:
```bash
Host <ssh-connection-name>
    HostName <VM-B-internal_ip>
    User brendanoconnor
    IdentityFile ~/.ssh/gcp_vm_to_vm
```
