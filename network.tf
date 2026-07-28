# ---------------------------------------------------------------------------
# network.tf — libvirt network reference
# ---------------------------------------------------------------------------
# We use the existing libvirt NAT network (default, 192.168.122.0/24).
# No data source exists for networks in dmacvicar/libvirt v0.9.x, so we
# pass the network name by string to each VM module.
# ---------------------------------------------------------------------------

# The default network is maintained outside Terraform.  If you need to
# ensure it exists, create it manually:
#
#   virsh net-define /usr/share/libvirt/networks/default.xml
#   virsh net-start default
#   virsh net-autostart default
