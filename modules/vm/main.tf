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
        # Attach the cloud-init ISO as a virtio disk (vdb), NOT SATA.
        # The Debian cloud kernel has no ahci.ko driver, so a SATA-attached
        # cidata ISO is invisible to the guest -> ds-identify finds no
        # datasource -> cloud-init is disabled and hostname/IP/SSH are never
        # applied. virtio is supported by the cloud kernel (root disk is vda).
        target = {
          dev = "vdb"
          bus = "virtio"
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

    # QEMU guest agent channel.
    # NOTE: the old `type = "unix"` field is NOT part of the provider 0.9.x
    # channel schema and is silently ignored, which produced a pty channel
    # that libvirt cannot use ("unable to handle agent type: pty").
    # Setting `source.unix` makes the provider emit <channel type='unix'>
    # so libvirt can talk to the guest agent (virsh qemu-agent-command,
    # virsh domifaddr, virt-manager IP display all rely on this).
    channels = var.qemu_agent_enabled ? [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }
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
