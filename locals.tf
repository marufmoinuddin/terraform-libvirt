# ---------------------------------------------------------------------------
# locals.tf — computed values
# ---------------------------------------------------------------------------

locals {
  # SSH key snippet used in cloud-init (trimmed for safety)
  ssh_key = trimspace(var.ssh_public_key)
}
