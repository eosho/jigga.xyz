# Proxmox SDN Module
# Creates VXLAN overlay network for cross-node VM communication
# This replaces the need for manual vmbr1 bridges on each Proxmox node

# VXLAN Zone - Creates overlay network tunnel across all Proxmox nodes
# Requires UDP connectivity between peers on port 4789 (VXLAN default)
resource "proxmox_virtual_environment_sdn_zone_vxlan" "k3s_zone" {
  id    = var.zone_id
  peers = var.proxmox_node_ips
  mtu   = var.mtu # Must be 50 bytes less than physical MTU (1500 - 50 = 1450)

  # Optional DNS settings
  dns      = var.dns_server
  dns_zone = var.dns_zone

  depends_on = [proxmox_virtual_environment_sdn_applier.finalizer]
}

# Virtual Network (VNet) - Appears as a bridge on all nodes after apply
resource "proxmox_virtual_environment_sdn_vnet" "k3s_vnet" {
  id   = var.vnet_id
  zone = proxmox_virtual_environment_sdn_zone_vxlan.k3s_zone.id
  tag  = var.vxlan_tag # VXLAN Network Identifier (VNI) - required for VXLAN zones

  alias = var.vnet_alias

  depends_on = [proxmox_virtual_environment_sdn_applier.finalizer]
}

# SDN Applier - Applies all pending SDN changes to Proxmox nodes
# This is REQUIRED - without it, SDN changes remain in "pending" state
resource "proxmox_virtual_environment_sdn_applier" "apply" {
  depends_on = [
    proxmox_virtual_environment_sdn_zone_vxlan.k3s_zone,
    proxmox_virtual_environment_sdn_vnet.k3s_vnet
  ]
}

# Empty applier for dependency ordering
# Other resources depend on this to ensure proper creation order
resource "proxmox_virtual_environment_sdn_applier" "finalizer" {}
