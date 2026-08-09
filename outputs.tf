# ---------------------------------------------------------------------------
# outputs.tf — useful post-apply information
# ---------------------------------------------------------------------------

output "vm_ips" {
  description = "Map of VM name → IP address"
  value = {
    for name, mod in module.vm : name => mod.ip_address
  }
}

output "vm_details" {
  description = "Map of VM name → hardware specification"
  value = {
    for name, cfg in var.vm_config : name => {
      vcpu    = cfg.vcpu
      memory  = cfg.memory
      disk_gb = cfg.disk_gb
      ip      = cfg.ip_address
    }
  }
}

output "ssh_commands" {
  description = "SSH commands to reach each VM (from the hypervisor)"
  value = {
    for name, cfg in var.vm_config : name => "ssh root@${cfg.ip_address}"
  }
}

output "check_vm" {
  description = "Virsh commands to verify VM state"
  value       = <<-EOT
    # List all running VMs
    virsh list

    # Check a specific VM (replace <name>)
    virsh dominfo <name>

    # Connect to serial console
    virsh console <name>
  EOT
}

output "host_setup" {
  description = "Host-level preparation checklist"
  value       = <<-EOT
    1. Verify libvirtd is running:
       systemctl status libvirtd

    2. Confirm the default network is active:
       virsh net-info default

    3. Place the CentOS 10 QCOW2 image at:
       ${var.base_image_path}

    4. Set your SSH public key in terraform.tfvars:
       ssh_public_key = "ssh-rsa AAAA..."
  EOT
}

output "summary" {
  description = "Deployment summary (sensitive due to SSH key reference)"
  sensitive   = true
  value       = <<-EOT
    Terraform libvirt Kubernetes cluster plan
    ─────────────────────────────────────────
    Network:  ${var.network_name}
    Gateway:  ${var.gateway}
    Domain:   ${var.domain_name}
    DNS:      ${join(", ", var.dns_servers)}

    VMs: ${length(var.vm_config)}
    ─────────────────────────────────────────
    Storage pool: ${var.storage_pool_name} → ${var.storage_pool_path}
    Base image:   ${libvirt_volume.base_image.path}

    Review terraform.tfvars before applying.
    Run: terraform plan  then  terraform apply
  EOT
}
