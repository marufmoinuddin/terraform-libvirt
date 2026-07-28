# ---------------------------------------------------------------------------
# versions.tf — Terraform and provider version constraints
# ---------------------------------------------------------------------------
# This file pins the Terraform engine and the libvirt provider to versions
# known to work with this project.  Raising the minimum Terraform version
# is safe as long as you stay >= 1.6.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
    }
  }
}
