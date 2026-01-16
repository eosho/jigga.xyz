# SDN Module Outputs

output "zone_id" {
  description = "The ID of the created SDN VXLAN zone"
  value       = proxmox_virtual_environment_sdn_zone_vxlan.k3s_zone.id
}

output "vnet_id" {
  description = "The ID of the created SDN VNet (use this as bridge name for VMs)"
  value       = proxmox_virtual_environment_sdn_vnet.k3s_vnet.id
}

output "vnet_bridge" {
  description = "The bridge name to use for VM network configuration"
  value       = proxmox_virtual_environment_sdn_vnet.k3s_vnet.id
}

output "subnet_cidr" {
  description = "The CIDR of the SDN subnet"
  value       = var.subnet_cidr
}

output "subnet_gateway" {
  description = "The gateway IP of the SDN subnet"
  value       = var.subnet_gateway
}

output "sdn_ready" {
  description = "Indicates SDN has been applied and is ready for use"
  value       = true

  depends_on = [proxmox_virtual_environment_sdn_applier.apply]
}
