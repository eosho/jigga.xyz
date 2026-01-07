output "vm_ips" {
  description = "Map of VM names to their public IP addresses"
  value       = { for name, vm in proxmox_virtual_environment_vm.k8s_node : name => local.node_ips[name].public_ip }
}

output "control_node_name" {
  description = "Name of the control node VM"
  value       = var.k3s_server_name
}

output "control_node_ip" {
  description = "Private IP of the control node (cluster internal)"
  value       = local.node_ips[var.k3s_server_name].private_ip
}

output "control_node_public_ip" {
  description = "Public IP of the control node (for SSH and kubectl access)"
  value       = local.node_ips[var.k3s_server_name].public_ip
}

output "vm_names" {
  description = "List of VM names created"
  value       = keys(proxmox_virtual_environment_vm.k8s_node)
}

output "k3s_master_ip" {
  description = "Private IP address of the Kubernetes master node"
  value       = local.node_ips[var.k3s_server_name].private_ip
}

output "k3s_node_token" {
  description = "The node token for joining workers to the K3s cluster"
  value       = var.k3s_token
  sensitive   = true
}

output "cloud_init_files" {
  description = "IDs of the cloud-init snippets uploaded to Proxmox"
  value       = { for k, v in proxmox_virtual_environment_file.cloud_init_user_data : k => v.id }
}

# =============================================================================
# AUTO-GENERATED FILE PATHS
# =============================================================================

output "ansible_inventory_path" {
  description = "Path to the auto-generated Ansible inventory"
  value       = local_file.ansible_inventory.filename
}

output "ansible_hosts_path" {
  description = "Path to the auto-generated /etc/hosts file for Ansible"
  value       = local_file.ansible_hosts_file.filename
}

output "ssh_config_path" {
  description = "Path to the auto-generated SSH config"
  value       = local_file.ssh_config.filename
}