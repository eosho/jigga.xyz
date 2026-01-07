# VM Outputs
output "vm_ips" {
  description = "A map of VM names to their public IP addresses"
  value       = module.proxmox.vm_ips
}

output "k3s_master_ip" {
  description = "The IP address of the Kubernetes master node"
  value       = module.proxmox.k3s_master_ip
}

output "k3s_node_token" {
  description = "The node token for joining workers to the K3s cluster"
  value       = module.proxmox.k3s_node_token
  sensitive   = true
}

output "ssh_config_path" {
  description = "Path to the generated SSH config file"
  value       = "${path.module}/ssh_config"
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = local.kubeconfig_path
}

# User Information for accessing services
output "access_instructions" {
  description = "Instructions for accessing the cluster"
  sensitive   = false
  value       = <<EOT
----- Kubernetes Cluster Access -----

1. SSH to the control node:
   $ ssh -F ssh_config ${module.proxmox.control_node_name}

2. Set up kubectl:
   $ export KUBECONFIG=${local.kubeconfig_path}
EOT
}

# =============================================================================
# SDN Outputs (only when SDN is enabled)
# =============================================================================
output "sdn_enabled" {
  description = "Whether SDN (VXLAN overlay) is enabled"
  value       = var.enable_sdn
}

output "sdn_zone_id" {
  description = "SDN VXLAN zone ID (only when SDN is enabled)"
  value       = var.enable_sdn ? module.sdn[0].zone_id : null
}

output "sdn_vnet_bridge" {
  description = "SDN VNet bridge name for VM network configuration (only when SDN is enabled)"
  value       = var.enable_sdn ? module.sdn[0].vnet_bridge : null
}

output "sdn_subnet_cidr" {
  description = "SDN subnet CIDR (only when SDN is enabled)"
  value       = var.enable_sdn ? module.sdn[0].subnet_cidr : null
}

output "private_network_bridge" {
  description = "The bridge used for private/cluster networking (SDN VNet or manual bridge)"
  value       = var.enable_sdn ? var.sdn_vnet_id : var.private_bridge
}
