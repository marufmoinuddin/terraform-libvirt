# ---------------------------------------------------------------------------
# main.tf — VM instantiation via vm module
# ---------------------------------------------------------------------------

module "vm" {
  source   = "./modules/vm"
  for_each = var.vm_config

  vm_name    = each.key
  vcpu       = each.value.vcpu
  memory_mib = each.value.memory
  disk_gb    = each.value.disk_gb
  ip_address = each.value.ip_address

  pool_name       = var.storage_pool_name
  pool_path       = var.storage_pool_path
  base_image_path = "${var.storage_pool_path}/${var.base_image_volume_name}"

  network_name   = var.network_name
  gateway        = var.gateway
  dns_servers    = var.dns_servers
  domain_name    = var.domain_name
  ssh_public_key = var.ssh_public_key

  ovmf_code_path = var.ovmf_code_path
  ovmf_vars_path = var.ovmf_vars_path

  qemu_agent_enabled = var.qemu_agent_enabled

  # Ensure the storage pool exists and the base image volume is present
  # before the module creates volumes in it.
  depends_on = [libvirt_pool.storage, terraform_data.base_image]
}
