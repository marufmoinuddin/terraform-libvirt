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
  }
}

resource "libvirt_volume" "base_image" {
  name = "centos10-base.qcow2"
  pool = var.storage_pool_name
  target = {
    format = {
      type = "qcow2"
    }
  }
  create = {
    content = {
      url = var.base_image_path
    }
  }

  # Make sure the pool exists before creating a volume in it.
  depends_on = [libvirt_pool.storage]
}
