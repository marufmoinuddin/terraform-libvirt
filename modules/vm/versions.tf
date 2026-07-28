# ---------------------------------------------------------------------------
# Module-level provider configuration
# ---------------------------------------------------------------------------
# Without this block the module defaults to hashicorp/libvirt, which does
# not exist.  The directive below aliases it to the correct provider.
# ---------------------------------------------------------------------------
terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}
