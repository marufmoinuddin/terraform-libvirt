# ---------------------------------------------------------------------------
# storage.tf — storage pool + base image volume
# ---------------------------------------------------------------------------
# The libvirt 'default' pool is auto-created by libvirtd.  If you want a
# custom storage location, set storage_pool_name to a NEW pool name and
# storage_pool_path to the directory you want — Terraform creates the pool
# (and the directory) for you automatically.  No virsh commands needed.
#
# The pool is only created when the name is NOT 'default', because the
# 'default' pool already exists on every libvirt host.
# ---------------------------------------------------------------------------

resource "libvirt_pool" "storage" {
  count = var.storage_pool_name == "default" ? 0 : 1

  name = var.storage_pool_name
  type = "dir"
  target = {
    path = var.storage_pool_path
    permissions = {
      mode  = "0755"
      owner = var.storage_pool_owner
      group = var.storage_pool_group
    }
  }

  # Safety: without this, the provider's default for a dir pool is to DELETE
  # the pool directory (and everything in it) on `terraform destroy`.  Keep
  # the directory and its files intact — only undefine the pool.
  destroy = {
    delete = false
  }
}

resource "terraform_data" "base_image" {
  triggers_replace = [
    var.base_image_path,
    var.storage_pool_name,
    var.storage_pool_path,
    var.base_image_volume_name,
  ]

  # Make sure the pool exists before we check/copy the volume into it.
  depends_on = [libvirt_pool.storage]

  # Idempotent: if the volume already exists in the pool (e.g. created by
  # another Terraform cluster sharing this pool), reuse it instead of
  # failing with "storage volume ... exists already".
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      if virsh vol-info "${var.base_image_volume_name}" --pool "${var.storage_pool_name}" >/dev/null 2>&1; then
        echo "Base image volume '${var.base_image_volume_name}' already exists in pool '${var.storage_pool_name}' — skipping creation."
      else
        echo "Creating base image volume '${var.base_image_volume_name}' in pool '${var.storage_pool_name}'..."
        sudo cp --sparse=always "${var.base_image_path}" "${var.storage_pool_path}/${var.base_image_volume_name}"
        sudo chown libvirt-qemu:libvirt-qemu "${var.storage_pool_path}/${var.base_image_volume_name}"
        virsh pool-refresh "${var.storage_pool_name}"
      fi
    EOT
  }
}
