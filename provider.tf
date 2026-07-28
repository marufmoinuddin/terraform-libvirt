# ---------------------------------------------------------------------------
# provider.tf — libvirt provider configuration
# ---------------------------------------------------------------------------
# The URI defaults to the system QEMU session (requires root / libvirt group).
# Override via the libvirt_uri variable if you need a different session
# (e.g. qemu:///session for unprivileged).
# ---------------------------------------------------------------------------

provider "libvirt" {
  uri = var.libvirt_uri
}
