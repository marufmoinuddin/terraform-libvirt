# ---------------------------------------------------------------------------
# modules/vm/main.tf — full VM definition (volumes + cloud-init + domain)
# ---------------------------------------------------------------------------
# Uses qemu-img to create the qcow2 overlay disk (backing_store is not
# supported by the dir pool driver on this libvirt version).
# ---------------------------------------------------------------------------

locals {
  # Filesystem paths for the overlay and cloud-init ISO
  overlay_path       = "${var.pool_path}/${var.vm_name}-root.qcow2"
  cloudinit_iso_path = "${var.pool_path}/${var.vm_name}-cloudinit.iso"
}

# ── Root disk (qcow2 overlay) ─────────────────────────────────────────────
# Created via qemu-img because the libvirt dir pool doesn't support
# the backing_store API with uploaded volumes on this hypervisor.

resource "terraform_data" "create_overlay" {
  triggers_replace = [
    var.base_image_path,
    var.vm_name,
    var.disk_gb,
  ]

  provisioner "local-exec" {
    command = "sudo qemu-img create -f qcow2 -b '${var.base_image_path}' -F qcow2 '${local.overlay_path}' ${var.disk_gb}G"
  }
}

# ── Cloud-init ISO generation ─────────────────────────────────────────────

locals {
  meta_data = yamlencode({
    instance-id    = "terraform-${var.vm_name}"
    local-hostname = var.vm_name
  })
}

resource "libvirt_cloudinit_disk" "init" {
  name = "${var.vm_name}-cloudinit.iso"
  user_data = templatefile("${path.module}/../../cloud-init/user-data.tpl", {
    hostname   = var.vm_name
    ssh_key    = trimspace(var.ssh_public_key)
    domain     = var.domain_name
    ip_address = var.ip_address
    gateway    = var.gateway
    dns        = join(" ", var.dns_servers)
  })
  network_config = templatefile("${path.module}/../../cloud-init/network-config.tpl", {
    ip_address  = var.ip_address
    gateway     = var.gateway
    dns_servers = var.dns_servers
    domain      = var.domain_name
  })
  meta_data = local.meta_data
}

resource "libvirt_volume" "cloudinit_iso" {
  name = "${var.vm_name}-cloudinit.iso"
  pool = var.pool_name
  create = {
    content = {
      url = libvirt_cloudinit_disk.init.path
    }
  }
}

# ── VM domain ─────────────────────────────────────────────────────────────

resource "libvirt_domain" "vm" {
  name        = var.vm_name
  type        = "kvm"
  vcpu        = var.vcpu
  memory      = var.memory_mib
  memory_unit = "MiB"

  depends_on = [terraform_data.create_overlay]

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"

    loader          = var.ovmf_code_path
    loader_readonly = "yes"
    loader_type     = "pflash"

    nv_ram = {
      nv_ram   = "/var/lib/libvirt/qemu/nvram/${var.vm_name}_VARS.4m.fd"
      template = var.ovmf_vars_path
    }

    boot_devices = [
      { dev = "hd" }
    ]
  }

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
    apic = {}
  }

  clock = {
    offset = "utc"
    timer = [
      {
        name       = "rtc"
        tickpolicy = "catchup"
      },
      {
        name       = "pit"
        tickpolicy = "delay"
      },
      {
        name    = "hpet"
        present = "no"
      }
    ]
  }

  devices = {

    disks = [
      {
        source = {
          file = {
            file = local.overlay_path
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          name    = "qemu"
          type    = "qcow2"
          cache   = "writeback"
          io      = "threads"
          discard = "unmap"
        }
      },
      {
        source = {
          file = {
            file = libvirt_volume.cloudinit_iso.path
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
        driver = {
          name = "qemu"
          type = "raw"
        }
      }
    ]

    controllers = [
      {
        type  = "scsi"
        model = "virtio-scsi"
      }
    ]

    interfaces = [
      {
        source = {
          network = {
            network = var.network_name
          }
        }
        model = {
          type = "virtio"
        }
      }
    ]

    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]

    mem_balloon = {
      model = "virtio"
      stats = {
        period = 10
      }
    }

    watchdogs = [
      {
        model  = "i6300esb"
        action = "reset"
      }
    ]

    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    channels = var.qemu_agent_enabled ? [
      {
        type = "unix"
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ] : []

    videos = [
      {
        model = {
          type    = "vga"
          vram    = 16384
          heads   = 1
          primary = "yes"
        }
      }
    ]
  }

  pm = {
    suspend_to_disk = {
      enabled = "no"
    }
    suspend_to_mem = {
      enabled = "no"
    }
  }

  running   = true
  autostart = true
}
