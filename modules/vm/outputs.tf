# ---------------------------------------------------------------------------
# modules/vm/outputs.tf — VM module outputs
# ---------------------------------------------------------------------------

output "vm_name" {
  description = "VM name"
  value       = libvirt_domain.vm.name
}

output "vm_uuid" {
  description = "VM UUID"
  value       = libvirt_domain.vm.uuid
}

output "vm_id" {
  description = "VM domain ID (runtime)"
  value       = libvirt_domain.vm.id
}

output "ip_address" {
  description = "Configured static IP address"
  value       = var.ip_address
}

output "overlay_path" {
  description = "Filesystem path to the qcow2 overlay disk"
  value       = local.overlay_path
}
