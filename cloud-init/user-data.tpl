#cloud-config
# ──────────────────────────────────────────────────────────────────────────
# user-data.tpl — cloud-init user data for CentOS Stream 10
# ──────────────────────────────────────────────────────────────────────────
# CentOS Stream 10 disables cloud-init network config by default, so we
# set the static IP via a bootstrap script that uses NetworkManager's nmcli.
# ──────────────────────────────────────────────────────────────────────────

hostname: ${hostname}
fqdn: ${hostname}.${domain}

# ── Users ─────────────────────────────────────────────────────────────────

users:
  - name: root
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL

# ── SSH authorized keys ───────────────────────────────────────────────────

write_files:
  - path: /root/.ssh/authorized_keys
    content: |
      ${ssh_key}
    permissions: '0600'
    owner: root:root

  # Bootstrap script to set static IP via NetworkManager
  - path: /opt/configure-network.sh
    content: |
      #!/bin/bash
      set -e
      sleep 5
      CONN=$(LANG=C nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep -v '^$' | head -1 | cut -d: -f1)
      if [ -z "$CONN" ]; then
        echo "ERROR: No active NetworkManager connection found"
        exit 1
      fi
      nmcli con mod "$CONN" ipv4.addresses "${ip_address}/24"
      nmcli con mod "$CONN" ipv4.gateway "${gateway}"
      nmcli con mod "$CONN" ipv4.dns "${dns}"
      nmcli con mod "$CONN" ipv4.method manual
      echo "Network configured: ${ip_address}/24 via ${gateway}"
    permissions: '0755'
    owner: root:root

# ── SSH daemon ────────────────────────────────────────────────────────────

ssh_pwauth: false
disable_root: false

# ── Packages to install on first boot ─────────────────────────────────────

packages:
  - qemu-guest-agent
  - cloud-utils-growpart
  - vim
  - curl
  - wget
  - git
  - net-tools
  - bind-utils
  - tmux

# ── Run commands ──────────────────────────────────────────────────────────

runcmd:
  - /opt/configure-network.sh

  # Restart sshd if the package install rotates config
  - systemctl reload sshd || true

  # Enable and start qemu-guest-agent
  - systemctl enable --now qemu-guest-agent

  # Expand the root partition and filesystem
  - growpart /dev/vda 1 || true
  - xfs_growfs / || resize2fs /dev/vda1 || true

# ── Final message ─────────────────────────────────────────────────────────

final_message: "VM ${hostname} initialized by Terraform"

# ── Power state ───────────────────────────────────────────────────────────

power_state:
  mode: reboot
  condition: true
