# Terraform + libvirt — Create Virtual Machines with Code

Welcome! This project lets you create and destroy virtual machines (VMs) on
your own Linux server using **Terraform** and **libvirt**. It is designed for
beginners: every file is explained, every command is shown, and nothing is
assumed.

If you have never heard of Terraform or libvirt before, that is exactly the
right place to start. Read on — by the end you will understand what they are,
what this repository does, and how to run it yourself.

---

## Table of Contents

1. [What Are We Building?](#1-what-are-we-building)
2. [What is Terraform?](#2-what-is-terraform)
3. [What is libvirt?](#3-what-is-libvirt)
4. [Why Use Them Together?](#4-why-use-them-together)
5. [The Big Picture — How the Files Fit Together](#5-the-big-picture--how-the-files-fit-together)
6. [Repository Structure](#6-repository-structure)
7. [Prerequisites](#7-prerequisites)
8. [Installing the Tools](#8-installing-the-tools)
9. [Setting Up libvirt](#9-setting-up-libvirt)
10. [Downloading a Cloud Image](#10-downloading-a-cloud-image)
11. [Configuring Your VMs](#11-configuring-your-vms)
12. [Running the Project — Step by Step](#12-running-the-project--step-by-step)
13. [Common Commands and What They Do](#13-common-commands-and-what-they-do)
14. [How the VMs Get Their Settings](#14-how-the-vms-get-their-settings)
15. [Troubleshooting](#15-troubleshooting)
16. [Next Steps](#16-next-steps)
17. [Appendix: Terraform Cheatsheet](#17-appendix-terraform-cheatsheet)

---

## 1. What Are We Building?

This project creates virtual machines on your server from a **simple text
configuration**. Out of the box it can build:

| VM | Role | vCPU | RAM | Disk | IP address |
|----|------|------|-----|------|------------|
| `cp1` | Kubernetes control plane | 2 | 6 GB | 20 GB | 192.168.122.150 |
| `w1` | Kubernetes worker | 2 | 4 GB | 20 GB | 192.168.122.151 |
| `w2` | Kubernetes worker | 2 | 4 GB | 20 GB | 192.168.122.152 |
| `w3` | Kubernetes worker | 2 | 4 GB | 20 GB | 192.168.122.153 |

Or you can change the configuration to create a single small test VM, or any
mix of machines you like. The exact same workflow creates and destroys them.

**You do not need to know Kubernetes** to use this project. The VMs are just
ordinary Linux machines — you can use them for anything.

---

## 2. What is Terraform?

**Terraform** is a tool that lets you describe infrastructure (servers,
networks, disks, and more) in **code** — plain text files — and then creates,
updates, and destroys that infrastructure for you.

Think of it like a recipe for a cake:

- **Manual way:** You gather each ingredient yourself, measure by hand, and
  hope you remember every step next time.
- **Terraform way:** You write the recipe once. Then you hand it to Terraform
  and say "make it" — and it follows the recipe exactly, every single time.

### Why is that useful?

- **Repeatable** — the same configuration creates the same infrastructure
  every time.
- **Version-controlled** — your infrastructure lives in Git like code. You
  can see exactly what changed and roll back if needed.
- **Reviewable** — teammates can read your "recipe" and suggest changes in a
  pull request, just like code.
- **Destroyable** — one command tears everything down when you no longer need
  it. No forgotten leftovers.

### How Terraform thinks

Terraform works in three phases:

1. **Write** — you describe what you want in `.tf` files.
2. **Plan** — Terraform reads your files, compares them to what already
   exists, and shows you a preview of what it will create, change, or delete.
   Nothing happens yet — this is the safe "look before you leap" step.
3. **Apply** — Terraform actually makes it happen, by talking to a
   "provider" (a plugin that speaks the language of your infrastructure).

Terraform keeps a **state file** (`terraform.tfstate`) that records what it
has created. This is its memory: it compares your config files against this
state to decide what changed. **Never edit this file by hand.**

---

## 3. What is libvirt?

**libvirt** is a toolkit that manages virtual machines on Linux. It is the
glue between tools like Terraform and the actual virtualization engine
underneath (usually **KVM/QEMU**).

A useful mental model:

- **KVM** is the engine that actually runs the virtual machines.
- **libvirt** is the control panel for that engine — it lets programs (and
  humans) start, stop, configure, and inspect VMs without touching the raw
  engine internals.
- **virsh** is libvirt's command-line tool, for when you want to check things
  by hand.

This project talks to libvirt over its system connection (`qemu:///system`),
which is the standard way to manage VMs that run as system services.

---

## 4. Why Use Them Together?

Terraform alone cannot create a VM — it needs a provider that knows how to
talk to a specific platform. libvirt alone cannot create VMs from code — you
would have to run commands by hand every time.

Together they give you the best of both:

```
You write a config file
        │
        ▼
   Terraform  ──reads──►  provider: dmacvicar/libvirt
        │                        │
        │                        ▼
        └─────────────────►  libvirt API (qemu:///system)
                                     │
                                     ▼
                               KVM/QEMU creates the VM
```

Terraform is the brain, libvirt is the hands, KVM is the muscle.

---

## 5. The Big Picture — How the Files Fit Together

When you run `terraform apply`, this is the chain of events:

1. `terraform init` downloads the **libvirt provider** plugin, so Terraform
   knows how to talk to libvirt.
2. `variables.tf` declares every setting the project accepts (CPU, RAM,
   disk, IP addresses, SSH key, and more).
3. `terraform.tfvars` supplies the actual values for those settings — your
   personal choices for this machine.
4. `storage.tf` uploads your base cloud image (the QCOW2 file) into libvirt's
   storage pool. All VMs share this image as a read-only "backing file".
5. `network.tf` looks up the libvirt network (usually `default`), so VMs can
   attach to it and get IP addresses.
6. `main.tf` reads your `vm_config` list and, for **each VM** you asked for,
   calls the reusable `modules/vm` module.
7. The module creates:
   - an **overlay disk** (a small, fast file that starts empty and borrows
     the base image underneath — more on this later),
   - a **cloud-init ISO** (a tiny virtual CD that carries the VM's first-boot
     instructions: hostname, SSH key, static IP, packages),
   - the **VM itself** with the CPU, RAM, disk, and network you requested.
8. `outputs.tf` prints useful information after apply — IP addresses and SSH
   commands.

If that feels like a lot, don't worry. The next sections go through it one
piece at a time, and you will mostly interact with **one file**:
`terraform.tfvars`.

---

## 6. Repository Structure

```
terraform-libvirt/
├── main.tf                    # The orchestrator — creates one VM per entry in vm_config
├── provider.tf                # Connects Terraform to libvirt (qemu:///system)
├── variables.tf               # Declares every setting you can change
├── outputs.tf                 # Shows useful info after terraform apply
├── versions.tf                # Locks the Terraform and provider versions
├── locals.tf                  # Small helper values (e.g. trimmed SSH key)
├── storage.tf                 # Creates the shared base image volume
├── network.tf                 # Finds the libvirt network VMs attach to
├── cloudinit.tf               # (reserved — not used yet)
├── terraform.tfvars.example   # Template — copy this to terraform.tfvars
├── .gitignore                 # Tells Git to ignore state files and secrets
├── README.md                  # ← this file
│
├── modules/vm/                # Reusable "one VM" module
│   ├── main.tf                # The heart: overlay disk + cloud-init + domain
│   ├── variables.tf           # Inputs the module needs (name, CPU, RAM, IP…)
│   ├── outputs.tf             # Info the module returns (ID, MAC, IP)
│   └── versions.tf            # Provider version inside the module
│
└── cloud-init/                # First-boot templates injected into each VM
    ├── user-data.tpl          # Hostname, SSH key, packages, static IP script
    └── network-config.tpl     # Netplan static IP config (fallback)
```

### What each file does — plain English

| File | Purpose |
|------|---------|
| `main.tf` | The glue. Loops over `vm_config` and creates one VM per entry using the `modules/vm/` module. |
| `provider.tf` | Tells Terraform to use the `dmacvicar/libvirt` provider and connect to `qemu:///system`. |
| `variables.tf` | Declares all settings you can change: image path, SSH key, VM definitions, DNS, network name, etc. |
| `outputs.tf` | After apply, shows IP addresses and SSH commands. |
| `versions.tf` | Requires Terraform ≥ 1.6 and libvirt provider ~> 0.9.0. |
| `storage.tf` | Creates the base image volume from your QCOW2 file. Shared read-only by all VMs. |
| `network.tf` | Reads your existing libvirt network (e.g. `default`) so VMs can attach to it. |
| `locals.tf` | A short way to trim whitespace from your SSH public key. |
| `terraform.tfvars.example` | Example settings — copy this to `terraform.tfvars` and fill in your values. |
| `modules/vm/main.tf` | The heart of the project: overlay disk, cloud-init ISO, and the VM itself. |
| `modules/vm/variables.tf` | Declares what the module needs: VM name, IP, CPU, RAM, disk size, SSH key, etc. |
| `modules/vm/outputs.tf` | Returns the domain ID, MAC address, and IP address of each VM. |
| `cloud-init/user-data.tpl` | A template that runs on first boot: hostname, SSH key, packages, static IP, QEMU guest agent. |
| `cloud-init/network-config.tpl` | A Netplan v2 config for a static IP (used as a fallback). |
| `.gitignore` | Tells Git to ignore Terraform state files, the `.terraform/` directory, and your private `terraform.tfvars`. |

---

## 7. Prerequisites

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

## 8. Installing the Tools

### On Arch Linux / CachyOS

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

## 9. Setting Up libvirt

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

If no pool named `default` exists:

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

## 10. Downloading a Cloud Image

This project uses a **CentOS Stream 10 cloud image** as the base. A cloud
image is a pre-installed, minimal Linux that boots quickly and supports
cloud-init for first-time setup.

### Download the image

```bash
# Go to your storage location
cd /mnt/vms1

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
| `/mnt/vms1/` | Fast storage (your environment) |
| `/mnt/data/` | Large encrypted storage |

Update `base_image_path` in `terraform.tfvars` to match your location.

### Do NOT bundle the image in the ZIP

The image is large and already a standard download. The Terraform project
references its path via `base_image_path` — it expects the file to exist on
the system before running.

---

## 11. Configuring Your VMs

The only file you need to edit for day-to-day use is **`terraform.tfvars`**.

Start from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then open `terraform.tfvars` and set at least these two things:

1. **`base_image_path`** — the full path to your downloaded QCOW2 file.
2. **`ssh_public_key`** — your SSH public key, so you can log into the VMs.

Example (single test VM):

```hcl
base_image_path = "/mnt/vms1/CentOS-Stream-GenericCloud-x86_64-10-latest.x86_64.qcow2"

ssh_public_key = "ssh-ed25519 AAAA...your-key-here... user@host"

vm_config = {
  terraform-test = {
    vcpu       = 2
    memory     = 1024      # MiB (megabytes of RAM)
    disk_gb    = 10        # GiB (gigabytes of disk)
    ip_address = "192.168.122.200"
  }
}
```

Example (production 4-node cluster, as shipped):

```hcl
vm_config = {
  cp1 = { vcpu = 2, memory = 6144, disk_gb = 20, ip_address = "192.168.122.150" }
  w1  = { vcpu = 2, memory = 4096, disk_gb = 20, ip_address = "192.168.122.151" }
  w2  = { vcpu = 2, memory = 4096, disk_gb = 20, ip_address = "192.168.122.152" }
  w3  = { vcpu = 2, memory = 4096, disk_gb = 20, ip_address = "192.168.122.153" }
}
```

**Rule of thumb:** each entry in `vm_config` becomes one VM. Add or remove
entries freely.

---

## 12. Running the Project — Step by Step

This is the whole workflow, from a fresh clone to working VMs.

### Step 1 — Clone the repository

```bash
git clone https://github.com/marufmoinuddin/terraform-libvirt.git
cd terraform-libvirt
```

### Step 2 — Initialize Terraform

```bash
terraform init
```

This downloads the libvirt provider plugin. You only need to do this once
(or after changing provider versions).

### Step 3 — Configure your settings

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set base_image_path and ssh_public_key
```

### Step 4 — Preview what will be created

```bash
terraform plan
```

Read the output carefully. It shows exactly what Terraform will create. If
something looks wrong (wrong name, wrong IP, wrong size), fix your
`terraform.tfvars` and run `plan` again. **Plan makes no changes.**

### Step 5 — Create the VMs

```bash
terraform apply
```

Terraform will show the plan again and ask for confirmation. Type `yes` and
press Enter. Then watch it work — it uploads the base image, creates overlay
disks, generates cloud-init ISOs, and boots each VM. The first boot takes a
few minutes while each VM installs packages and configures its static IP.

### Step 6 — See what you got

```bash
terraform output
```

This prints the IP addresses and SSH commands for every VM.

### Step 7 — Log into a VM

```bash
ssh root@192.168.122.200    # or whichever IP terraform output showed
```

### Step 8 — Clean up when you are done

```bash
terraform destroy
```

Type `yes` when asked. Terraform will shut down and delete all the VMs it
created. Nothing is left behind.

---

## 13. Common Commands and What They Do

| Command | What it does |
|---------|--------------|
| `terraform init` | Downloads the provider plugin. Run once after cloning. |
| `terraform plan` | Shows a preview of changes. Makes no changes. |
| `terraform apply` | Creates or updates the infrastructure. |
| `terraform destroy` | Deletes all the infrastructure this config created. |
| `terraform output` | Shows the output values (IPs, SSH commands). |
| `terraform state list` | Lists everything Terraform is managing. |
| `terraform show` | Shows the current state in detail. |
| `terraform fmt` | Reformats your `.tf` files to the standard style. |
| `terraform validate` | Checks your config files for syntax errors. |
| `terraform refresh` | Updates the state to match reality (rarely needed). |

### Useful variations

```bash
# Create a single VM from the list
terraform apply -target=module.vm["terraform-test"]

# Destroy a single VM, keep the rest
terraform destroy -target=module.vm["terraform-test"]

# Rebuild one VM from scratch (dangerous — wipes its disk)
terraform apply -replace=module.vm["w1"]
```

---

## 14. How the VMs Get Their Settings

There are two clever tricks this project uses. Understanding them will save
you from a lot of confusion later.

### Trick 1: QCOW2 overlay disks (copy-on-write)

Your base image is a ~1.1 GB file. Instead of copying it four times (4 GB of
duplication), each VM gets a tiny **overlay** disk:

```
base image (read-only, shared by all)
        ▲
        │ "borrows" blocks that haven't changed
        │
overlay for cp1   overlay for w1   overlay for w2   overlay for w3
```

Each overlay starts nearly empty and grows only as the VM writes new data.
This is why 4 VMs can share one image without wasting disk space. The base
image must stay untouched — that is why it is kept read-only.

### Trick 2: cloud-init (first-boot configuration)

When a fresh VM boots, it knows nothing: no hostname, no SSH key, no IP
address. The project builds a tiny **cloud-init ISO** (a virtual CD) and
attaches it to the VM. On first boot, the VM reads this "CD" and configures
itself:

- sets its hostname,
- installs your SSH public key,
- sets its static IP address (via a bootstrap script that uses
  NetworkManager's `nmcli`),
- installs useful packages (`vim`, `curl`, `git`, `tmux`, …),
- starts the QEMU guest agent so libvirt can see inside the VM.

The templates for this live in `cloud-init/user-data.tpl` and
`cloud-init/network-config.tpl`.

---

## 15. Troubleshooting

### "Permission denied" when running terraform or virsh

Your user is not in the `libvirt` group (or the group change hasn't taken
effect):

```bash
sudo usermod -aG libvirt $(whoami)
# log out and back in, then check:
groups
```

### `terraform apply` hangs at "Still creating…"

The VM is booting for the first time. Cloud-init needs to install packages
and configure networking. Give it 2–5 minutes, then check the console:

```bash
virsh console <vm_name>
# press Enter to see the boot log; type Ctrl+] to exit
```

### VM is running but I cannot SSH to it

1. Wait a few more minutes — first boot is slow.
2. Check the VM actually got its static IP:

```bash
virsh domifaddr <vm_name>
```

3. Verify you are using the IP you set in `terraform.tfvars` and that your
   SSH key matches the one in `ssh_public_key`.
4. Check the cloud-init log inside the VM (via `virsh console`):

```bash
cat /var/log/cloud-init-output.log
```

### "No network with matching name 'default'"

The default libvirt network is not started:

```bash
sudo virsh net-start default
sudo virsh net-autostart default
```

### "Storage pool not found: no storage pool with matching name 'default'"

Create the default storage pool (see [Setting Up libvirt](#9-setting-up-libvirt)).

### `qemu-img` fails with "permission denied" on the overlay path

The storage pool directory is not writable by your user. Make sure you are
in the `libvirt` group and the pool directory exists:

```bash
sudo chmod 775 /var/lib/libvirt/images   # example — adjust to your pool path
```

### Terraform says it will destroy my existing VMs

`terraform destroy` or `apply` only touches resources it knows about through
its **state file**. If you cloned the repo into a new directory, Terraform
has no state and will not touch your existing VMs. Always run `terraform
plan` first and read the output carefully before applying.

### I deleted `terraform.tfstate` and now Terraform wants to recreate everything

The state file is Terraform's memory. Without it, Terraform cannot tell that
a VM already exists, so it plans to create everything from scratch. You can
recover by importing, but it is easier to **never delete the state file**.
If you must start over, use `terraform destroy` first.

### Disk space is filling up

```bash
# Check how much space the pool uses
virsh pool-info default

# Destroy VMs you no longer need
terraform destroy -target=module.vm["old-vm"]

# Clean up leftover volumes manually if needed
virsh vol-list --pool default
virsh vol-delete --pool default old-vm-root.qcow2
```

---

## 16. Next Steps

- **Play with the test VM first.** Create a single small VM
  (`terraform-test`) and destroy it before trying the full 4-node cluster.
- **Read the `.tf` files.** They are short and heavily commented. The best
  order is: `variables.tf` → `main.tf` → `modules/vm/main.tf`.
- **Try changing things.** Add a VM, give it more RAM, change its IP. Run
  `terraform plan` to see what changes.
- **Learn more:** the official [Terraform docs](https://developer.hashicorp.com/terraform/docs)
  and [libvirt docs](https://libvirt.org/) are excellent, beginner-friendly
  resources.

---

## 17. Appendix: Terraform Cheatsheet

| Action | Command |
|--------|---------|
| Download providers | `terraform init` |
| Preview changes | `terraform plan` |
| Create/update everything | `terraform apply` |
| Create/update one VM | `terraform apply -target=module.vm["name"]` |
| Delete everything | `terraform destroy` |
| Delete one VM | `terraform destroy -target=module.vm["name"]` |
| Show outputs | `terraform output` |
| List managed resources | `terraform state list` |
| Show state detail | `terraform show` |
| Format code | `terraform fmt` |
| Validate config | `terraform validate` |
| Rebuild one VM | `terraform apply -replace=module.vm["name"]` |

---

Happy building! The best way to learn Terraform is to create something, poke
at it, destroy it, and create it again. This project is built for exactly
that.
