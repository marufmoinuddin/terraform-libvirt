# ──────────────────────────────────────────────────────────────────────────
# network-config.tpl — cloud-init network configuration (netplan v2)
# ──────────────────────────────────────────────────────────────────────────
# Configures a single static IP on the first network interface.
# Uses the netplan v2 syntax with explicit routes.
# ──────────────────────────────────────────────────────────────────────────

version: 2
ethernets:
  id0:
    match:
      name: en*
    dhcp4: false
    addresses:
      - ${ip_address}/24
    nameservers:
      addresses:
%{ for dns in dns_servers ~}
        - ${dns}
%{ endfor ~}
      search:
        - ${domain}
    routes:
      - to: 0.0.0.0/0
        via: ${gateway}
