# ---------------------------------------------------------------------------
# modules/vm/variables.tf — VM module inputs
# ---------------------------------------------------------------------------

variable "vm_name" {
  description = "VM hostname"
  type        = string
}

variable "vcpu" {
  description = "Number of virtual CPUs"
  type        = number
}

variable "memory_mib" {
  description = "Memory in MiB"
  type        = number
}

variable "disk_gb" {
  description = "Root disk size in GiB"
  type        = number
}

variable "ip_address" {
  description = "Static IPv4 address"
  type        = string
}

variable "pool_name" {
  description = "Name of the libvirt storage pool"
  type        = string
}

variable "pool_path" {
  description = "Filesystem path of the storage pool directory"
  type        = string
}

variable "base_image_path" {
  description = "Path to the uploaded base image volume (used as backing store)"
  type        = string
}

variable "network_name" {
  description = "Name of the libvirt network to attach to"
  type        = string
}

variable "gateway" {
  description = "Default gateway"
  type        = string
}

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
}

variable "domain_name" {
  description = "DNS search domain"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for root access"
  type        = string
  sensitive   = true
}

variable "ovmf_code_path" {
  description = "Path to OVMF_CODE.fd"
  type        = string
}

variable "ovmf_vars_path" {
  description = "Path to OVMF_VARS.fd"
  type        = string
}

variable "qemu_agent_enabled" {
  description = "Enable QEMU guest agent channel"
  type        = bool
  default     = true
}
