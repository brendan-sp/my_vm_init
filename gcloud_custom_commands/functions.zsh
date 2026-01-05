# gcloud command helpers (sourced from .zshrc)

VMTYPE_CONFIG="${HOME}/.config/vmtype/aliases"

# Look up a value from the vmtype aliases config
# Usage: _lookup_alias <key>
_lookup_alias() {
  local key="$1"
  grep "^${key}=" "$VMTYPE_CONFIG" 2>/dev/null | head -1 | cut -d'=' -f2
}

# Get zone for a VM from config, or return empty string
# Usage: _get_zone <vm-name>
_get_zone() {
  local vm="$1"
  local zone=$(_lookup_alias "$vm")
  if [[ -z "$zone" ]]; then
    echo "Error: No zone mapping found for VM '$vm'" >&2
    echo "Add a mapping to $VMTYPE_CONFIG like: $vm=us-west1-b" >&2
    return 1
  fi
  echo "$zone"
}

# Get external IP of a VM and update SSH config
# Usage: get_vm_ext_ip <vm-name>
get_vm_ext_ip() {
  local vm="$1"

  if [[ -z "$vm" ]]; then
    echo "Usage: get_vm_ext_ip <vm-name>" >&2
    return 1
  fi

  local zone=$(_get_zone "$vm") || return 1

  local ip=$(gcloud compute instances describe "$vm" \
    --zone="$zone" \
    --format='value(networkInterfaces[0].accessConfigs[0].natIP)')

  if [[ -n "$ip" ]]; then
    echo "$ip"
    
    # Update SSH config
    local ssh_config="${HOME}/.ssh/config"
    if [[ -f "$ssh_config" ]] && grep -q "^Host ${vm}$" "$ssh_config"; then
      sed -i '' "/^Host ${vm}$/,/^Host /{s/^[[:space:]]*HostName .*/    HostName ${ip}/;}" "$ssh_config"
      echo "Updated SSH config for $vm" >&2
    fi
  else
    echo "Could not fetch external IP" >&2
    return 1
  fi
}

# start_vm <vm-name>
start_vm() {
  local vm="$1"
  [[ -z "$vm" ]] && echo "Usage: start_vm <vm-name>" >&2 && return 1
  local zone=$(_get_zone "$vm") || return 1
  gcloud compute instances start "$vm" --zone="$zone"
  get_vm_ext_ip "$vm"
}

# stop_vm <vm-name>
stop_vm() {
  local vm="$1"
  [[ -z "$vm" ]] && echo "Usage: stop_vm <vm-name>" >&2 && return 1
  local zone=$(_get_zone "$vm") || return 1
  gcloud compute instances stop "$vm" --zone="$zone"
}
