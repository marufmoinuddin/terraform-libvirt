#cloud-config
# ──────────────────────────────────────────────────────────────────────────
# user-data.tpl — cloud-init user data for Debian 12 (bookworm) genericcloud
# ──────────────────────────────────────────────────────────────────────────
# Debian cloud images honor cloud-init's network-config (netplan v2 syntax,
# rendered by cloud-init's systemd-networkd/eni renderer), so the static IP
# is applied from network-config.tpl — no bootstrap script needed.
# ──────────────────────────────────────────────────────────────────────────

hostname: ${hostname}
fqdn: ${hostname}.${domain}

# ── Users ─────────────────────────────────────────────────────────────────

users:
  - name: root
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL

# ── SSH authorized keys ───────────────────────────────────────────────────

ssh_authorized_keys:
  - ${ssh_key}

# ── SSH daemon ────────────────────────────────────────────────────────────

ssh_pwauth: false
disable_root: false

# ── Packages to install on first boot ─────────────────────────────────────

packages:
  - qemu-guest-agent
  - cloud-guest-utils
  - vim
  - curl
  - wget
  - git
  - net-tools
  - dnsutils
  - tmux

# ── Run commands ──────────────────────────────────────────────────────────

runcmd:
  # Enable and start qemu-guest-agent
  - systemctl enable --now qemu-guest-agent

  # Expand the root partition and filesystem (Debian uses ext4)
  - growpart /dev/vda 1 || true
  - resize2fs /dev/vda1 || true

# ── Final message ─────────────────────────────────────────────────────────

final_message: "VM ${hostname} initialized by Terraform"

# ── Power state ───────────────────────────────────────────────────────────

power_state:
  mode: reboot
  condition: true
