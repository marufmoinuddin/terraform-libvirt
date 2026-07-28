# Terraform + libvirt Kubernetes Cluster

**Your first Terraform project — a complete beginner's guide.**

This project creates virtual machines on your local Linux server (KVM/libvirt)
using Terraform. It is designed both as a **learning resource** for Terraform
and as a **production-ready deployment** for a Kubernetes cluster
(1 control-plane + 3 worker nodes running CentOS Stream 10).

---

## Table of Contents

1. [What is Terraform?](#1-what-is-terraform)
2. [Core Concepts Explained](#2-core-concepts-explained)
3. [Project Overview](#3-project-overview)
4. [What We Are Building](#4-what-we-are-building)
5. [Prerequisites](#5-prerequisites)
6. [Installing Dependencies](#6-installing-dependencies)
7. [Setting Up libvirt](#7-setting-up-libvirt)
8. [Preparing the CentOS Image](#8-preparing-the-centos-image)
9. [Project File-by-File Tour](#9-project-file-by-file-tour)
10. [Terraform Workflow — Step by Step](#10-terraform-workflow--step-by-step)
11. [Variables Explained](#11-variables-explained)
12. [Networking Explained](#12-networking-explained)
13. [How Cloud-Init Works Here](#13-how-cloud-init-works-here)
14. [QCOW2 Overlay Disks Explained](#14-qcow2-overlay-disks-explained)
15. [How the VM is Built (module/vm/main.tf tour)](#15-how-the-vm-is-built-modulevmmaintf-tour)
16. [Testing with a Small VM](#16-testing-with-a-small-vm)
17. [Production Deployment](#17-production-deployment)
18. [Troubleshooting](#18-troubleshooting)
19. [Cleanup and Destroy](#19-cleanup-and-destroy)
20. [Migrating to a Production Server](#20-migrating-to-a-production-server)
21. [Appendix: Terraform Commands Cheatsheet](#21-appendix-terraform-commands-cheatsheet)

---

## 1. What is Terraform?

Terraform is an **Infrastructure as Code (IaC)** tool. Instead of manually
running commands to create virtual machines, networks, disks, etc., you write
**config files** describing what you want. Terraform figures out how to create
it.

Think of it like this:

> **Manual way:** Log into a server, run `virt-install`, configure networking
> by hand, install packages, repeat for every VM.
>
> **Terraform way:** Write a file saying "I want 4 VMs with these specs",
> run `terraform apply`, and everything is created automatically.

### Why does it exist?
- **Repeatable** — the same config creates the same infrastructure every time
- **Version-controlled** — your infrastructure lives in Git like code
- **Auditable** — you can see exactly what changed in a pull request
- **Destroyable** — one command tears everything down

### How does it work?
Terraform has three phases:

1. **Write** — describe infrastructure in `.tf` files
2. **Plan** — Terraform reads your config and shows what it will create/change
3. **Apply** — Terraform makes it happen by talking to providers (APIs)

The **state file** (`terraform.tfstate`) tracks what was created. Terraform
compares your config against the state to decide what changed.

---

## 2. Core Concepts Explained

### Providers
A provider is a plugin that lets Terraform talk to a specific platform.
This project uses `dmacvicar/libvirt` which knows how to call KVM/libvirt's
API. Terraform downloads providers when you run `terraform init`.

### Resources
A resource is something Terraform creates: a VM, a disk, a network, a cloud-init
ISO. Resources have a **type** (like `libvirt_domain` for a VM) and a **name**
you choose (like `vm`).

```hcl
resource "libvirt_domain" "vm" {
  name   = "my-vm"
  vcpu   = 2
  memory = 1024
}
```

### Variables
Variables make your config reusable. Instead of hardcoding values, you define
variables and set them in a file:

```hcl
# variables.tf
variable "vcpu" {
  description = "Number of virtual CPUs"
  type        = number
}
```

```hcl
# terraform.tfvars
vcpu = 2
```

### Outputs
Outputs display useful information after `terraform apply`, like IP addresses
or SSH commands.

### Modules
A module is a reusable group of resources. This project has a `modules/vm/`
module — one piece of config that creates a single VM. We use it 4 times
(for cp1, w1, w2, w3) with different variables.

```hcl
module "cp1" {
  source = "./modules/vm"
  vm_name   = "cp1"
  vcpu      = 2
  memory_mib = 6144
  ...
}
```

### State
`terraform.tfstate` is a JSON file that maps your config to real-world objects.
Terraform reads it to know what exists. **Never edit it manually.**

### Plan
`terraform plan` shows you exactly what Terraform will create, modify, or
destroy. It is a safe preview — no changes happen during plan.

---

## 3. Project Overview

```
terraform-libvirt/
├── main.tf                    # Entry point — connects everything together
├── provider.tf                # Configures the libvirt provider
├── variables.tf               # All variables you can set
├── outputs.tf                 # What you see after "terraform apply"
├── versions.tf                # Required Terraform and provider versions
├── terraform.tfvars.example   # Template for your settings (copy → terraform.tfvars)
├── locals.tf                  # Small helper expressions
├── storage.tf                 # The base CentOS image volume
├── network.tf                 # Looks up your libvirt network
├── cloudinit.tf               # (reserved for future use)
├── .gitignore                 # Files Git should ignore
├── README.md                  # ← this file
│
├── modules/vm/                # Reusable VM module
│   ├── main.tf                # Defines one VM: disk, cloud-init, domain
│   ├── variables.tf           # Inputs for the module (IP, CPU, RAM, etc.)
│   ├── outputs.tf             # Info the module returns (domain_id, IP, MAC)
│   └── versions.tf            # Provider pinning inside the module
│
└── cloud-init/                # Templates for boot-time configuration
    ├── user-data.tpl          # Cloud-init script (SSH key, packages, networking)
    └── network-config.tpl     # Netplan static IP config (fallback)
```

### What each file does — plain English

| File | Purpose |
|------|---------|
| `main.tf` | The glue. It loops over `vm_config` and creates one VM per entry using the `modules/vm/` module. |
| `provider.tf` | Tells Terraform to use the `dmacvicar/libvirt` provider and connects to `qemu:///system` (your local KVM). |
| `variables.tf` | Declares all settings you can change: image path, SSH key, VM definitions, DNS, network name, etc. |
| `outputs.tf` | After apply, shows IP addresses, SSH commands, and a summary. |
| `versions.tf` | Requires Terraform ≥ 1.6 and libvirt provider ~> 0.9.0. |
| `storage.tf` | Creates the base image volume from your CentOS QCOW2 file. This volume is shared by all VMs as a read-only backing file. |
| `network.tf` | Reads your existing libvirt network (e.g. "default") so VMs can attach to it. |
| `locals.tf` | A short way to trim whitespace from your SSH public key. |
| `terraform.tfvars.example` | Example settings — copy this to `terraform.tfvars` and fill in your values. |
| `modules/vm/main.tf` | The heart of the project. Creates the overlay disk, the cloud-init ISO, and the VM itself. |
| `modules/vm/variables.tf` | Declares what the module needs: VM name, IP, CPU, RAM, disk size, SSH key, storage pool, network name, etc. |
| `modules/vm/outputs.tf` | Returns the domain ID, MAC address, and IP address of each VM. |
| `cloud-init/user-data.tpl` | A script that runs on first boot: sets hostname, injects SSH key, installs packages, configures static IP, starts QEMU guest agent. |
| `cloud-init/network-config.tpl` | A Netplan v2 config for static IP (used as fallback). |
| `.gitignore` | Tells Git to ignore Terraform state files, the `.terraform/` directory, and your private `terraform.tfvars`. |

---

## 4. What We Are Building

### Test VM (for learning & validation)
| Name | IP | vCPU | RAM | Disk | Purpose |
|------|----|------|-----|------|---------|
| `terraform-test` | 192.168.122.200 | 2 | 1 GB | 10 GB | Your practice VM |

### Production Kubernetes Cluster
| Name | Role | IP | vCPU | RAM | Disk |
|------|------|----|------|-----|------|
| **cp1** | Control Plane | 192.168.122.150 | 2 | 6 GB | 20 GB |
| **w1** | Worker | 192.168.122.151 | 2 | 4 GB | 20 GB |
| **w2** | Worker | 192.168.122.152 | 2 | 4 GB | 20 GB |
| **w3** | Worker | 192.168.122.153 | 2 | 4 GB | 20 GB |

All VMs run **CentOS Stream 10** with UEFI boot, q35 machine type,
virtio devices, and static IP addresses.

---

## 5. Prerequisites

Before you begin, your system needs:

- **Linux** with KVM support (Intel VT-x / AMD-V)
- **libvirt** and **virt-install** packages installed
- **Terraform** installed (version 1.6 or newer)
- **QEMU** with UEFI (OVMF) support
- **At least 15 GB free disk space** for the test VM
- **80 GB free disk space** for the full 4-node cluster

### Check if your system is ready

Run these commands to verify:

```bash
# Check CPU virtualization support
grep -E 'vmx|svm' /proc/cpuinfo
# You should see "vmx" (Intel) or "svm" (AMD) in the flags

# Check libvirt
systemctl status libvirtd
# Should show "active (running)"

# Check Terraform
terraform --version
# Should show Terraform v1.6.0 or newer

# Check UEFI firmware
ls /usr/share/edk2/x64/OVMF_CODE.4m.fd 2>/dev/null || \
ls /usr/share/OVMF/OVMF_CODE.fd 2>/dev/null
# Should show a file (UEFI firmware for VMs)

# Check QEMU
qemu-img --version
# Should show qemu-img version
```

If anything is missing, see the next section.

---

## 6. Installing Dependencies

### On Arch Linux (and derivatives)

```bash
# Core virtualization
sudo pacman -S virt-install virt-manager qemu-desktop libvirt dnsmasq edk2-ovmf

# Start and enable libvirt
sudo systemctl enable --now libvirtd

# Add your user to the libvirt group
sudo usermod -aG libvirt $(whoami)

# Log out and back in for the group change to take effect
```

### On Fedora

```bash
sudo dnf install @virtualization
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $(whoami)
```

### On Ubuntu / Debian

```bash
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager ovmf
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $(whoami)
```

### Installing Terraform

```bash
# Download the latest Terraform binary
wget https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip
unzip terraform_1.10.5_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform --version
```

Or use your package manager:

```bash
# Arch
sudo pacman -S terraform

# Fedora
sudo dnf install terraform

# Ubuntu/Debian (add HashiCorp repo first)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

---

## 7. Setting Up libvirt

### Start the default network

```bash
sudo virsh net-start default
sudo virsh net-autostart default
```

### Verify the default network

```bash
virsh net-info default
```

You should see:
```
Name:           default
State:          active
Bridge:         virbr0
IP:             192.168.122.1
DHCP:           yes
```

### Check your storage pool

```bash
virsh pool-list --all
```

If no pool named "default" exists:

```bash
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default
```

### Permission issues

If you see "Permission denied" errors, ensure your user is in the `libvirt`
group and you have logged out and back in:

```bash
groups          # should show "libvirt"
sudo systemctl restart libvirtd
```

---

## 8. Preparing the CentOS Image

This project uses a **CentOS Stream 10 cloud image** as the base.
The image is a pre-installed, minimal CentOS that boots quickly and supports
cloud-init for first-time setup.

### Download the image

```bash
# Go to your storage location
cd /var/lib/libvirt/images

# Download the latest CentOS Stream 10 cloud image
curl -sL -o CentOS-Stream-GenericCloud-x86_64-10-latest.x86_64.qcow2 \
  "https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-x86_64-10-latest.x86_64.qcow2"

# Verify the image
qemu-img info CentOS-Stream-GenericCloud-x86_64-10-latest.x86_64.qcow2
```

The image is about 1.1 GB. Keep it **read-only** — it serves as a shared
backing file for all VMs.

### Where to place the image

Place it anywhere you have enough space. Common locations:

| Path | Notes |
|------|-------|
| `/var/lib/libvirt/images/` | Default libvirt storage |
| `/mnt/data/` | Dedicated storage volume |

Update `base_image_path` in `terraform.tfvars` to match your location.

### Do NOT bundle the image in the ZIP

The image is large and already a standard download. The Terraform project
references its path via `base_image_path` — it expects the file to exist
on the system before running.

---

## 9. Project File-by-File Tour

### versions.tf — What version of Terraform and providers

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
    }
  }
}
```

**Key concept:** `required_version` sets the minimum Terraform version.
`required_providers` tells Terraform where to download the libvirt plugin.
The `~>` operator means "allow 0.9.x but not 1.0" (semantic versioning).

### provider.tf — How to connect to libvirt

```hcl
provider "libvirt" {
  uri = var.libvirt_uri  # typically "qemu:///system"
}
```

**Key concept:** A provider configuration is like a connection string.
`qemu:///system` connects to the system-wide libvirt daemon (needs root or
libvirt group membership). `qemu:///session` would connect to a per-user
instance.

### variables.tf — All settings in one place

This file declares every setting you can change. Key variables:

| Variable | Type | Default | What it does |
|----------|------|---------|-------------|
| `base_image_path` | `string` | — | Path to your CentOS QCOW2 file |
| `ssh_public_key` | `string` | — | Your SSH public key for root access |
| `vm_config` | `map(object)` | — | VM definitions (name → CPU, RAM, disk, IP) |
| `libvirt_uri` | `string` | `"qemu:///system"` | libvirt connection URI |
| `network_name` | `string` | `"default"` | libvirt network to attach VMs to |
| `gateway` | `string` | `"192.168.122.1"` | Default gateway |
| `dns_servers` | `list(string)` | `["192.168.122.1", "1.1.1.1", "8.8.8.8"]` | DNS servers |
| `domain_name` | `string` | `"home.local"` | DNS domain suffix |
| `storage_pool_name` | `string` | `"default"` | libvirt storage pool |
| `storage_pool_path` | `string` | `"/var/lib/libvirt/images"` | Storage pool directory |

**Key concept:** Variables with no `default` are **required** — you MUST set
them in `terraform.tfvars`.

### locals.tf — Small helpers

```hcl
locals {
  ssh_public_key_trimmed = trimspace(var.ssh_public_key)
}
```

**Key concept:** `locals` are intermediate values computed from variables.
They keep your code DRY (Don't Repeat Yourself).

### main.tf — The orchestrator

```hcl
module "vm" {
  source   = "./modules/vm"
  for_each = var.vm_config

  vm_name   = each.key
  vcpu      = each.value.vcpu
  memory_mib = each.value.memory
  disk_gb   = each.value.disk_gb
  ip_address = each.value.ip_address
  ...
}
```

**Key concept:** `for_each` creates one VM per entry in the `vm_config` map.
`each.key` is the VM name (e.g., "cp1"), `each.value` is the config object.

### storage.tf — The base image volume

```hcl
resource "libvirt_volume" "base_image" {
  name   = "centos10-base.qcow2"
  pool   = var.storage_pool_name
  source = var.base_image_path
  format = "qcow2"
}
```

**Key concept:** This uploads your QCOW2 file into libvirt's storage pool.
Every VM's overlay disk references this as a backing file.

### network.tf — Finding your network

```hcl
data "libvirt_network" "existing" {
  name = var.network_name
}
```

**Key concept:** A **data source** reads existing infrastructure. Instead of
creating a network, this reads the existing "default" network to get its UUID,
bridge name, and other attributes.

### modules/vm/main.tf — The VM itself (heart of the project)

This file does three things:

1. **Creates a QCOW2 overlay disk** using `qemu-img`
2. **Generates a cloud-init ISO** with SSH key, hostname, network config
3. **Defines the VM** (CPU, RAM, disks, devices, UEFI boot)

See section 15 for a detailed walkthrough.

### cloud-init/user-data.tpl — First-boot automation

This is a cloud-init script that runs the first time the VM boots. It:

- Sets the hostname
- Injects your SSH public key into `/root/.ssh/authorized_keys`
- Installs packages (QEMU guest agent, vim, curl, etc.)
- Runs a script to configure the static IP via NetworkManager
- Enables the QEMU guest agent
- Expands the root filesystem
- Reboots to apply the static IP

### cloud-init/network-config.tpl — Static IP fallback

This is a Netplan v2 configuration for the first network interface.
It is provided as a fallback — the user-data script uses `nmcli` instead
because CentOS Stream 10 disables cloud-init network configuration by default.

---

## 10. Terraform Workflow — Step by Step

This is the workflow you will follow every time you use this project.

### Step 1: Copy and edit settings

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your preferred editor:

```bash
vim terraform.tfvars
```

Change at minimum:
- `base_image_path` — path to your CentOS QCOW2 file
- `ssh_public_key` — your actual SSH public key (from `cat ~/.ssh/id_ed25519.pub`)
- `vm_config` — start with the test VM (see Section 16)

### Step 2: Initialize Terraform

```bash
terraform init
```

This downloads the libvirt provider plugin (~15 MB) and sets up the working
directory. You will see:

```
Initializing the backend...
Initializing provider plugins...
- Finding dmacvicar/libvirt versions matching "~> 0.9.0"...
- Installing dmacvicar/libvirt v0.9.7...
- Installed dmacvicar/libvirt v0.9.7 (signed by key ...)

Terraform has been successfully initialized!
```

Run `terraform init` only once per project (or after adding new providers).

### Step 3: Format your code

```bash
terraform fmt -recursive
```

This formats all `.tf` files neatly. Always run this before committing.

### Step 4: Validate your config

```bash
terraform validate
```

Checks for syntax errors and invalid references. You should see:

```
Success! The configuration is valid.
```

### Step 5: See what Terraform will do

```bash
terraform plan
```

This shows a detailed plan of everything Terraform will create. Read it
carefully. Look for lines starting with `+` (create), `-` (destroy),
or `~` (modify).

Example output:
```
Terraform will perform the following actions:

  # libvirt_volume.base_image will be created
  + resource "libvirt_volume" "base_image" {
      + name = "centos10-base.qcow2"
      + pool = "default"
      ...
    }

  # module.vm["cp1"].libvirt_domain.vm will be created
  + resource "libvirt_domain" "vm" {
      + name   = "cp1"
      + vcpu   = 2
      + memory = 6144
      ...
    }

Plan: 17 to add, 0 to change, 0 to destroy.
```

**17 resources** for a 4-node cluster:
- 1 base image volume
- 4 cloud-init disks
- 4 cloud-init ISOs
- 4 overlay disks (via terraform_data)
- 4 VMs

### Step 6: Apply (create everything)

```bash
terraform apply
```

Terraform will show you the plan again and ask for confirmation.
Type `yes` and press Enter.

To skip the confirmation (for automation):

```bash
terraform apply -auto-approve
```

Terraform creates resources one by one:
```
libvirt_volume.base_image: Creating...
libvirt_volume.base_image: Creation complete after 15s
module.vm["cp1"].terraform_data.create_overlay: Creating...
module.vm["cp1"].terraform_data.create_overlay: Provisioning with 'local-exec'...
module.vm["cp1"].libvirt_domain.vm: Creating...
module.vm["cp1"].libvirt_domain.vm: Creation complete after 2s
...
Apply complete! Resources: 17 added, 0 changed, 0 destroyed.
```

### Step 7: Check the outputs

After apply, Terraform shows:

```
Outputs:

check_vm = <<EOT
  # List all running VMs
  virsh list
  ...
EOT

ssh_commands = {
  "cp1" = "ssh root@192.168.122.150"
  "w1"  = "ssh root@192.168.122.151"
  "w2"  = "ssh root@192.168.122.152"
  "w3"  = "ssh root@192.168.122.153"
}
```

### Step 8: SSH into your VMs

```bash
ssh root@192.168.122.150
```

The first boot takes 2-4 minutes (cloud-init installs packages and reboots).
If SSH fails immediately, wait a minute and try again.

### Step 9: Destroy when done

```bash
terraform destroy
```

Type `yes` when prompted. All VMs, disks, and cloud-init ISOs are deleted.

---

## 11. Variables Explained

### base_image_path

```hcl
base_image_path = "/var/lib/libvirt/images/CentOS-Stream-GenericCloud-x86_64-10-latest.x86_64.qcow2"
```

Full path to your CentOS Stream 10 QCOW2 file. This file must exist before
running `terraform apply`. It becomes the backing file for all VM overlays.

### ssh_public_key

```hcl
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILmGgaK32VYQuuJ83fZpL5mjVCWXTGmumWyPzruebmJF user@host"
```

Your SSH public key. Find it with: `cat ~/.ssh/id_ed25519.pub`
(use `id_rsa.pub` if you have an RSA key instead).

This is how you log into the VMs as root.

### vm_config

```hcl
vm_config = {
  terraform-test = {
    vcpu       = 2
    memory     = 1024
    disk_gb    = 10
    ip_address = "192.168.122.200"
  }
}
```

A map of VM definitions. Each key is the VM name, each value contains:

| Field | Type | Description |
|-------|------|-------------|
| `vcpu` | number | Virtual CPUs |
| `memory` | number | RAM in MB |
| `disk_gb` | number | Root disk size in GB |
| `ip_address` | string | Static IP address |

Add more entries to create more VMs. The `for_each` loop in `main.tf`
automatically handles any number of VMs.

### libvirt_uri

```hcl
libvirt_uri = "qemu:///system"
```

The libvirt connection URI. For most setups this stays as `qemu:///system`.
Change to `qemu+ssh://user@host/system` for remote hypervisors.

### network_name

```hcl
network_name = "default"
```

The libvirt network your VMs connect to. The default NAT network creates
a 192.168.122.0/24 subnet with DHCP at 192.168.122.1. Your VMs get static
IPs in this range.

### gateway

```hcl
gateway = "192.168.122.1"
```

The default gateway for your VMs. Usually the IP of the libvirt host on
the virbr0 bridge.

### dns_servers

```hcl
dns_servers = ["192.168.122.1", "1.1.1.1", "8.8.8.8"]
```

DNS servers the VMs use. The first entry is usually the libvirt host
(which forwards DNS), followed by public DNS servers.

### domain_name

```hcl
domain_name = "home.local"
```

The DNS domain suffix. The VM's fully qualified hostname becomes
`vm-name.home.local`.

### storage_pool_name and storage_pool_path

```hcl
storage_pool_name = "default"
storage_pool_path = "/var/lib/libvirt/images"
```

The libvirt storage pool where all VM disks live. The pool must exist
(`virsh pool-list --all`). The path is the filesystem directory backing
the pool.

---

## 12. Networking Explained

### The default libvirt network

When libvirt is installed, it creates a NAT network called "default".
It works like a home router:

```
┌─────────────┐     NAT      ┌──────────────┐
│   Your VMs  │◄───────────►│   Internet   │
│ 192.168.122 │              │              │
│   .0/24     │              │  (your LAN)  │
└──────┬──────┘              └──────────────┘
       │
       │ virbr0 bridge
       │
┌──────┴──────┐
│  Your Host  │
│   .122.1    │
└─────────────┘
```

- **VMs** get IPs in 192.168.122.0/24
- **Host** has 192.168.122.1 on the virbr0 bridge
- **Traffic** from VMs to the internet is NAT'd through the host
- **Host can SSH** into VMs directly
- **Other machines** cannot reach VMs (they're behind NAT)

### Static IPs vs DHCP

Each VM gets a **static IP** assigned by cloud-init via NetworkManager.
The static IP lives alongside DHCP — the VM first gets a DHCP lease and then
overrides it with the static configuration during its first boot.

If you need to find a VM before cloud-init finishes, check DHCP leases:

```bash
virsh net-dhcp-leases default
```

### Why static IPs?

Kubernetes requires predictable IP addresses. Each node needs to know exactly
where to find the control plane, and certificates are often tied to specific
IPs. Static IPs ensure the cluster stays stable across reboots.

### Adding more networks

If you need a second network (e.g., for storage or cluster-internal traffic),
create it in libvirt:

```bash
virsh net-define your-network.xml
virsh net-start your-network
```

Then add a second network interface to the VM module (this is an advanced
topic beyond this README).

---

## 13. How Cloud-Init Works Here

### What is cloud-init?

Cloud-init is a system that runs on first boot to configure a fresh VM.
It is standard on almost all Linux cloud images. It reads configuration
from a virtual CD-ROM (attached as the `sda` disk in our VMs).

### What our cloud-init does

The `cloud-init/user-data.tpl` template configures:

1. **Hostname** — sets the VM's hostname and FQDN
2. **SSH key** — writes your public key to `/root/.ssh/authorized_keys`
3. **Packages** — installs qemu-guest-agent, vim, curl, git, and more
4. **Static IP** — runs a script that uses `nmcli` to set the static IP
5. **QEMU guest agent** — enables `qemu-guest-agent` for host-guest communication
6. **Root partition** — expands the root filesystem to fill the disk
7. **Reboot** — applies the static IP by rebooting

### Why a script instead of network-config?

CentOS Stream 10 ships with a pre-installed file:
`/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`

This file tells cloud-init to **not manage networking** (CentOS uses
NetworkManager instead). So our `network-config.tpl` is provided as a
fallback but the actual static IP is set by a bootstrap script using
NetworkManager's `nmcli` command.

### The bootstrap script (inside user-data)

```bash
# Written to /opt/configure-network.sh by cloud-init's write_files module
CONN=$(LANG=C nmcli -t -f NAME,DEVICE con show --active | head -1 | cut -d: -f1)
nmcli con mod "$CONN" ipv4.addresses "192.168.122.200/24"
nmcli con mod "$CONN" ipv4.gateway "192.168.122.1"
nmcli con mod "$CONN" ipv4.dns "192.168.122.1 1.1.1.1 8.8.8.8"
nmcli con mod "$CONN" ipv4.method manual
```

It detects the active NetworkManager connection name (which varies between
distros and releases) and configures it statically.

### The cloud-init ISO

Terraform creates an ISO file containing three things:
- `meta-data` — instance ID and hostname
- `user-data` — the cloud-config script (sensitive)
- `network-config` — the Netplan v2 static IP config

The ISO is attached to the VM as a SATA disk (`sda`) and cloud-init
reads it automatically on first boot.

---

## 14. QCOW2 Overlay Disks Explained

### What is QCOW2?

QCOW2 is a disk image format used by QEMU/KVM. It supports:

- **Sparse files** — a 20 GB disk uses only as much space as data written
- **Snapshots** — save point-in-time states
- **Overlays** — multiple VMs can share a single base image

### Copy-on-Write (COW) overlays

Instead of copying the 1.1 GB CentOS image 4 times (4.4 GB total), we:

1. Keep the original image **read-only** (the backing file)
2. Create a tiny **overlay** file for each VM
3. Each overlay stores only the changes made by that VM

```
┌─────────────────────────────────────┐
│  /var/lib/libvirt/images/centos10   │  ← 1.1 GB (read-only base)
│           .qcow2                    │
│  (CentOS Stream 10 image)          │
└──────────┬──────────────────────────┘
           │ backing file
     ┌─────┼─────┬─────┐
     │     │     │     │
  cp1.qcow2 w1.qcow2 w2.qcow2 w3.qcow2
  (200 MB)  (200 MB) (200 MB) (200 MB)
```

The overlay starts at ~200 KB and grows as the VM writes data. Each VM
sees a full 20 GB disk but the base image is shared, saving ~3 GB per VM.

This is configured in `modules/vm/main.tf`:

```hcl
resource "terraform_data" "create_overlay" {
  provisioner "local-exec" {
    command = "sudo qemu-img create -f qcow2 -b '${var.base_image_path}' -F qcow2 '...' ${var.disk_gb}G"
  }
}
```

The `-b` flag specifies the backing file. `-F qcow2` tells qemu-img the
backing file format. The overlay path is `/var/lib/libvirt/images/<vm>-root.qcow2`.

### Why not use libvirt's backing_store?

The `dmacvicar/libvirt` v0.9.7 provider has a `backing_store` attribute for
libvirt volumes, but libvirt 10.x's directory pool driver does not support it.
The error would be:

```
Error: Can not use a backing store with this libvirt version
```

The `local-exec` approach with `qemu-img` works around this limitation.

### Disk performance settings

The root disk is configured for optimal performance:

- **cache = writeback** — faster writes with safe crash recovery
- **io = threads** — uses a thread pool for I/O
- **discard = unmap** — TRIM support, frees space when files are deleted

---

## 15. How the VM is Built (modules/vm/main.tf tour)

Let's walk through `modules/vm/main.tf` line by important line.

### Step 1: Create the overlay disk

```hcl
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
```

**What this does:** Runs `qemu-img create -b` on your machine to create a
thin-provisioned overlay. The `trigger_replace` list means Terraform
re-creates the overlay if the base image path, VM name, or disk size changes.

### Step 2: Generate the cloud-init ISO

```hcl
resource "libvirt_cloudinit_disk" "init" {
  name = "${var.vm_name}-cloudinit.iso"
  user_data = templatefile("${path.module}/../../cloud-init/user-data.tpl", {
    hostname = var.vm_name
    ssh_key  = trimspace(var.ssh_public_key)
    ip_address = var.ip_address
    gateway  = var.gateway
    dns      = join(" ", var.dns_servers)
    domain   = var.domain_name
  })
  network_config = templatefile("...network-config.tpl", { ... })
  meta_data = local.meta_data
}
```

**What this does:** Uses `templatefile` to fill in the template variables
(hostname, SSH key, IP, etc.) and tells the libvirt provider to create a
cloud-init ISO.

### Step 3: Upload the ISO to the storage pool

```hcl
resource "libvirt_volume" "cloudinit_iso" {
  name   = "${var.vm_name}-cloudinit.iso"
  pool   = var.pool_name
  create = {
    content = {
      url = libvirt_cloudinit_disk.init.path
    }
  }
}
```

**What this does:** Copies the cloud-init ISO (generated in step 2) into
libvirt's storage pool so the VM can access it.

### Step 4: Define the VM

```hcl
resource "libvirt_domain" "vm" {
  name        = var.vm_name
  type        = "kvm"
  vcpu        = var.vcpu
  memory      = var.memory_mib
  memory_unit = "MiB"
```

**What this does:** Creates the VM with the specified CPU and RAM.

#### UEFI boot (q35 + OVMF)

```hcl
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

    boot_devices = [{ dev = "hd" }]
  }
```

**What this does:** Enables UEFI boot with the q35 machine type. OVMF is the
UEFI firmware for VMs. The `nv_ram` is the UEFI variable store (like BIOS
settings).

#### CPU and features

```hcl
  cpu = { mode = "host-passthrough" }

  features = {
    acpi = true
    apic = {}
  }

  clock = {
    offset = "utc"
    timer = [
      { name = "rtc", tickpolicy = "catchup" },
      { name = "pit", tickpolicy = "delay" },
      { name = "hpet", present = "no" },
    ]
  }
```

**What this does:** Passes your host CPU features to the VM (best performance),
enables ACPI and APIC (required for modern OSes), and configures timers.

#### Devices

The `devices` block defines the VM's virtual hardware:

```hcl
  devices = {
    disks = [ ... ]          # Root disk (virtio) + cloud-init ISO (SATA)
    controllers = [ ... ]    # virtio-scsi controller
    interfaces = [ ... ]     # virtio network adapter
    rngs = [ ... ]           # Random number generator (virtio-rng)
    mem_balloon = { ... }    # Memory balloon (dynamic memory)
    watchdogs = [ ... ]      # Watchdog (i6300esb)
    consoles = [ ... ]       # Serial console
    channels = [ ... ]       # QEMU guest agent channel
    videos = [ ... ]         # VGA video (std mode)
  }
```

**Key devices explained:**

| Device | What it does |
|--------|-------------|
| **Root disk (virtio)** | Main disk, high performance |
| **Cloud-init ISO (SATA)** | First-boot configuration |
| **virtio-scsi** | SCSI controller for better disk handling |
| **virtio NIC** | Network adapter, near-native speed |
| **virtio-rng** | Provides entropy to the VM (prevents /dev/random blocking) |
| **Balloon** | Allows host to reclaim unused VM memory |
| **Watchdog** | Auto-resets if the VM freezes |
| **Serial console** | Access via `virsh console <vm>` |
| **QEMU guest agent** | Host-VM communication channel |
| **QEMU guest agent** | Enables graceful shutdown, file access, etc. |

#### Power management

```hcl
  pm = {
    suspend_to_disk = { enabled = "no" }
    suspend_to_mem  = { enabled = "no" }
  }

  running   = true
  autostart = true
```

**What this does:** Disables suspend (not useful for servers), starts the VM
immediately, and sets it to auto-start on host reboot.

---

## 16. Testing with a Small VM

Before deploying the full 4-node cluster, test with a single small VM:

### Edit terraform.tfvars

```hcl
vm_config = {
  terraform-test = {
    vcpu       = 2
    memory     = 1024
    disk_gb    = 10
    ip_address = "192.168.122.200"
  }
}
```

### Run the workflow

```bash
cd /path/to/terraform-libvirt
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your SSH key and image path
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply -auto-approve
```

### Wait for cloud-init

After `terraform apply` succeeds, wait ~2-3 minutes for cloud-init:

```bash
# Monitor with
virsh list
virsh net-dhcp-leases default

# Wait 3 minutes
# Then SSH to the static IP
ssh root@192.168.122.200
```

### Verify

Once logged in:

```bash
hostnamectl           # Should show terraform-test.home.local
ip addr show enp3s0   # Should show 192.168.122.200/24
systemctl status qemu-guest-agent  # Should be active
cat /root/.ssh/authorized_keys     # Should have your SSH key
df -h /              # Should show ~10 GB (cloud-init expanded the partition)
```

### Destroy the test VM

```bash
terraform destroy -auto-approve
```

### Switch to production config

Edit `terraform.tfvars` and replace the test VM with the 4-node cluster:

```hcl
vm_config = {
  cp1 = {
    vcpu       = 2
    memory     = 6144
    disk_gb    = 20
    ip_address = "192.168.122.150"
  }
  w1 = {
    vcpu       = 2
    memory     = 4096
    disk_gb    = 20
    ip_address = "192.168.122.151"
  }
  w2 = {
    vcpu       = 2
    memory     = 4096
    disk_gb    = 20
    ip_address = "192.168.122.152"
  }
  w3 = {
    vcpu       = 2
    memory     = 4096
    disk_gb    = 20
    ip_address = "192.168.122.153"
  }
}
```

Then run `terraform apply` again.

---

## 17. Production Deployment

### Before you start

1. **Check disk space** — 4 VMs × 20 GB = 80 GB minimum
   ```bash
   df -h /var/lib/libvirt/images
   ```

2. **Check available RAM** — cp1 uses 6 GB, each worker 4 GB = 18 GB total
   ```bash
   free -h
   ```

3. **Ensure the CentOS image is in place**
   ```bash
   ls -lh /var/lib/libvirt/images/CentOS-Stream-GenericCloud-x86_64-10-latest.x86_64.qcow2
   ```

4. **Prepare your SSH key**
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```

### Deploy

```bash
cd terraform-libvirt
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

### After VMs are created

Wait ~3-5 minutes for all VMs to complete cloud-init and reboot.

Check their status:

```bash
virsh list
# Should show cp1, w1, w2, w3 all running
```

SSH into each VM:

```bash
ssh root@192.168.122.150   # cp1
ssh root@192.168.122.151   # w1
ssh root@192.168.122.152   # w2
ssh root@192.168.122.153   # w3
```

### Next steps (Kubernetes installation)

The VMs are ready for Kubernetes. You typically:

1. Install a container runtime on all nodes
2. Initialize the control plane on cp1
3. Join workers to the cluster

This is outside the scope of this Terraform project, but the VMs have all
the prerequisites: CentOS Stream 10, static IPs, SSH access, and sufficient
resources.

---

## 18. Troubleshooting

### "Permission denied" when running `terraform apply`

**Problem:** Terraform can't connect to libvirt.

**Solutions:**
```bash
# Ensure you're in the libvirt group
groups | grep libvirt

# If not, add yourself
sudo usermod -aG libvirt $(whoami)
# Log out and back in

# Restart libvirt
sudo systemctl restart libvirtd

# Check if the socket is accessible
ls -la /var/run/libvirt/libvirt-sock
```

### "no support for 'qcow2' volume from file"

**Problem:** The provider can't import the QCOW2 file into the storage pool.

**Solutions:**
```bash
# Make sure the file exists and is readable
ls -la /path/to/your/image.qcow2

# Make sure the storage pool exists and is active
virsh pool-list --all
virsh pool-info default

# If pool is inactive, start it
virsh pool-start default
```

### VM created but SSH says "Connection refused"

**Problem:** The VM is booting and cloud-init hasn't started SSH yet.

**Solutions:**
```bash
# Wait 2-3 minutes — first boot takes time
# Check if VM is running
virsh list

# Find the DHCP IP (before cloud-init configures static IP)
virsh net-dhcp-leases default

# Try SSH to the DHCP IP
ssh root@<dhcp-ip>
```

### SSH says "Permission denied (publickey)"

**Problem:** The SSH key wasn't injected correctly.

**Solutions:**
```bash
# Check your terraform.tfvars has the correct key
cat ~/.ssh/id_ed25519.pub
# Compare with what's in terraform.tfvars

# SSH to the DHCP IP (before reboot) and check
ssh -i ~/.ssh/id_ed25519 root@<dhcp-ip>
cat /root/.ssh/authorized_keys

# Re-run terraform after fixing the key
terraform apply
```

### VM boots but has DHCP IP instead of static IP

**Problem:** Cloud-init's network-config is disabled on CentOS Stream 10,
and the nmcli script may have failed.

**Solutions:**
```bash
# SSH via DHCP IP
ssh root@<dhcp-ip>

# Check cloud-init logs
cat /var/log/cloud-init-output.log | grep -i error

# Manually set the static IP
CONN=$(nmcli -t -f NAME,DEVICE con show --active | head -1 | cut -d: -f1)
nmcli con mod "$CONN" ipv4.addresses "192.168.122.X/24"
nmcli con mod "$CONN" ipv4.gateway "192.168.122.1"
nmcli con mod "$CONN" ipv4.dns "192.168.122.1"
nmcli con mod "$CONN" ipv4.method manual
nmcli con down "$CONN"
nmcli con up "$CONN"
```

### "Provider produced inconsistent result" error

**Problem:** This is a known bug in the `dmacvicar/libvirt` v0.9.7 provider.
The VM was actually created successfully despite the error.

**Check:**
```bash
virsh list
# If the VM is listed as running, it worked.
```

### Disk space running low

```bash
# Check VM disk usage
virsh vol-list --pool default

# Delete unused stale volumes
virsh vol-delete --pool default <volume-name>

# Stop VMs to free space
terraform destroy
```

### "Failed to render final message template"

**Problem:** Minor cloud-init warning about the `final_message` template.
Not critical — the VM works fine.

---

## 19. Cleanup and Destroy

### Destroy all VMs and volumes

```bash
terraform destroy
```

Review the plan and type `yes`. This deletes:
- All 4 VMs
- All overlay disks
- All cloud-init ISOs
- The base image volume

### Manual cleanup (if something goes wrong)

If `terraform destroy` fails, clean up manually:

```bash
# List and destroy VMs
virsh list --all
virsh destroy <vm-name>
virsh undefine --nvram <vm-name>

# List and delete volumes
virsh vol-list --pool default
virsh vol-delete --pool default <volume-name>

# Clean up files
sudo rm -f /var/lib/libvirt/images/*.qcow2
sudo rm -f /var/lib/libvirt/images/*.iso
sudo rm -f /var/lib/libvirt/qemu/nvram/*
```

### What gets preserved

- The CentOS QCOW2 image at your download location stays — it is not managed by Terraform
- The `terraform.tfstate` file stays (use `rm terraform.tfstate*` if needed)
- Your SSH key and `terraform.tfvars` stay

---

## 20. Migrating from Test to Production Deployment

This project was developed and tested on a local machine with limited
resources. The production target has more resources. Here is how to
migrate.

### What stays the same

- **The Terraform code** — exactly the same files
- **The CentOS image** — same download URL
- **The VM definitions** — same module, same variables

### What changes

| Aspect | Test Environment | Production |
|--------|-----------------|------------|
| **Where Terraform runs** | Local machine | Production server |
| **Storage** | Limited local storage | Larger or dedicated storage |
| **Memory** | Limited (e.g. 8 GB) | 32 GB+ |
| **VM count** | 1 test VM | 4 cluster VMs |
| **VM memory** | 1 GB per VM | 4-6 GB per VM |

### Migration steps

1. **Copy the project to the production server:**
   ```bash
   scp terraform-libvirt.zip user@production-server:~/
   ssh user@production-server
   unzip terraform-libvirt.zip
   cd terraform-libvirt
   ```

2. **Install dependencies on the production server:**
   ```bash
   sudo dnf install libvirt virt-install qemu-kvm terraform edk2-ovmf
   sudo systemctl enable --now libvirtd
   ```

3. **Set up storage:**
   ```bash
   # Create a storage pool (if needed)
   sudo mkdir -p /var/lib/libvirt/images
   virsh pool-define-as default dir --target /var/lib/libvirt/images
   virsh pool-build default
   virsh pool-start default
   virsh pool-autostart default
   ```

4. **Download the CentOS image:**
   ```bash
   cd /var/lib/libvirt/images
   curl -sL -O https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-x86_64-10-latest.x86_64.qcow2
   ```

5. **Configure and deploy:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars  # Update paths, SSH key
   terraform init
   terraform apply
   ```

### File adjustments needed in terraform.tfvars

Only these changes are needed for any environment:

| Variable | What to change |
|----------|---------------|
| `base_image_path` | Path to CentOS image on this machine |
| `ssh_public_key` | Your actual SSH public key |
| `storage_pool_path` | Storage directory on this machine |
| `vm_config` | Keep as-is for production |

**Everything else** (module code, cloud-init templates, network config)
works without modification.

---

## 21. Appendix: Terraform Commands Cheatsheet

```bash
# Initialization
terraform init                    # Download providers, set up workspace

# Formatting and validation
terraform fmt                     # Format all .tf files
terraform fmt -recursive          # Format including subdirectories
terraform validate                # Check for syntax errors

# Planning
terraform plan                    # Show what will be created/changed
terraform plan -out plan.tfplan   # Save plan for later apply

# Applying
terraform apply                   # Apply with confirmation prompt
terraform apply -auto-approve     # Apply without confirmation
terraform apply plan.tfplan       # Apply a saved plan

# Inspection
terraform show                    # Show current state
terraform state list              # List all resources in state
terraform output                  # Show outputs
terraform output ssh_commands     # Show a specific output

# Destroying
terraform destroy                 # Destroy with confirmation
terraform destroy -auto-approve   # Destroy without confirmation

# Advanced
terraform import <resource> <id>  # Import existing infra into state
terraform taint <resource>        # Mark resource for re-creation
terraform untaint <resource>      # Unmark resource
terraform workspace list          # List workspaces
terraform workspace new staging   # Create a new workspace
```

### Terraform state commands

```bash
# State is stored in terraform.tfstate
# NEVER edit it manually — use these commands:

terraform state list              # List all resources
terraform state show <resource>   # Show resource details
terraform state rm <resource>     # Remove from state (not from infra)
terraform state mv <old> <new>    # Rename in state
```

---

## License and Credits

This project was built with:
- [Terraform](https://www.terraform.io/) by HashiCorp
- [dmacvicar/terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt)
- CentOS Stream 10 Cloud images by the CentOS Project
- KVM/libvirt by the Open Source Virtualization community
