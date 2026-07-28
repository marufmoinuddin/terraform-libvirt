# ---------------------------------------------------------------------------
# storage.tf — base image volume
# ---------------------------------------------------------------------------
# The libvirt 'default' pool is auto-created by libvirtd.  The pool name
# and path are passed via variables (see variables.tf).
# ---------------------------------------------------------------------------

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
}
