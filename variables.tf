# ---------------------------------------------------------------------------
# variables.tf — all configurable inputs for the project
# ---------------------------------------------------------------------------
# Every value that might differ between environments (test vs. production)
# is surfaced here.  Copy terraform.tfvars.example → terraform.tfvars and
# override what you need.
# ---------------------------------------------------------------------------

# ── libvirt connection ────────────────────────────────────────────────────

variable "libvirt_uri" {
  description = "libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

# ── storage pool ──────────────────────────────────────────────────────────

variable "storage_pool_name" {
  description = <<-EOT
    Name of the libvirt storage pool for VM disks.

    Use "default" to keep the pool that libvirt auto-creates.  To use a
    custom storage location, pick any other name (e.g. "terraform") and set
    storage_pool_path to the directory you want — Terraform creates the pool
    (and the directory) automatically.
  EOT
  type        = string
  default     = "default"
}

variable "storage_pool_path" {
  description = <<-EOT
    Filesystem path of the storage pool directory on the host.  Used both as
    the pool target (when a custom pool is created) and as the directory
    where the VM overlay disks are created.

    Example:
      /home/you/.local/share/libvirt/terraform
  EOT
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "storage_pool_owner" {
  description = "Numeric UID that owns the custom storage pool directory (your user id)"
  type        = string
  default     = "1000"
}

variable "storage_pool_group" {
  description = "Numeric GID that owns the custom storage pool directory (your primary group id)"
  type        = string
  default     = "1000"
}

# ── base image ────────────────────────────────────────────────────────────

variable "base_image_path" {
  description = <<-EOT
    Absolute path to the Debian 12 (bookworm) genericcloud QCOW2 image on the
    host filesystem.  This file is read-only and used as a backing store for
    every VM overlay disk.

    If the image is missing, download it from:
      https://cloud.debian.org/images/cloud/bookworm/latest/

    Example:
      /var/lib/libvirt/images/debian-12-genericcloud-amd64.qcow2
  EOT
  type        = string
}

variable "base_image_volume_name" {
  description = <<-EOT
    Name of the base image volume inside the storage pool.  If a volume with
    this name already exists in the pool (e.g. created by another Terraform
    cluster sharing the same pool), it is reused instead of being re-created.
  EOT
  type        = string
  default     = "debian12-base.qcow2"
}

# ── network ───────────────────────────────────────────────────────────────

variable "network_name" {
  description = "Name of the libvirt network to attach VMs to"
  type        = string
  default     = "default"
}

variable "gateway" {
  description = "Default gateway for VM static IPs"
  type        = string
  default     = "192.168.122.1"
}

variable "dns_servers" {
  description = "List of DNS servers for VMs"
  type        = list(string)
  default     = ["192.168.122.1", "1.1.1.1", "8.8.8.8"]
}

variable "domain_name" {
  description = "DNS domain name (search domain)"
  type        = string
  default     = "home.local"
}

# ── SSH access ────────────────────────────────────────────────────────────

variable "ssh_public_key" {
  description = <<-EOT
    SSH public key to inject into every VM's /root/.ssh/authorized_keys.
    Example:
      ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...
  EOT
  type        = string
  sensitive   = true
}

# ── VM definitions ────────────────────────────────────────────────────────

variable "vm_config" {
  description = <<-EOT
    Map of VM short-name → resource specification.
    Each entry creates one VM with the given hardware and static IP.

    Example (single test VM):
      vm_config = {
        terraform-test = {
          vcpu       = 2
          memory     = 1024
          disk_gb    = 10
          ip_address = "192.168.122.200"
        }
      }

    Example (production cluster):
      vm_config = {
        cp1 = {
          vcpu       = 2
          memory     = 6144
          disk_gb    = 20
          ip_address = "192.168.122.150"
        }
        w1 = {
          vcpu       = 2
          memory     = 4096
          disk_gb    = 20
          ip_address = "192.168.122.151"
        }
        w2 = {
          vcpu       = 2
          memory     = 4096
          disk_gb    = 20
          ip_address = "192.168.122.152"
        }
        w3 = {
          vcpu       = 2
          memory     = 4096
          disk_gb    = 20
          ip_address = "192.168.122.153"
        }
      }
  EOT
  type = map(object({
    vcpu       = number
    memory     = number # MiB
    disk_gb    = number # GiB for the root volume
    ip_address = string # static IPv4 address
  }))
}

# ── firmware / UEFI paths (usually auto-detected; override for custom OVMF) ─

variable "ovmf_code_path" {
  description = "Path to OVMF_CODE.fd (UEFI firmware for q35)"
  type        = string
  default     = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
}

variable "ovmf_vars_path" {
  description = "Path to OVMF_VARS.fd (UEFI variable template)"
  type        = string
  default     = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
}

# ── QEMU guest agent ──────────────────────────────────────────────────────

variable "qemu_agent_enabled" {
  description = "Enable QEMU guest agent channel in every VM"
  type        = bool
  default     = true
}
