# =============================================================================
# Standalone VM Module - Outputs
# =============================================================================

output "vm_ids" {
  description = "Map of VM names to their Proxmox VM IDs"
  value       = { for k, v in proxmox_virtual_environment_vm.vm : k => v.vm_id }
}

output "vm_ips" {
  description = "Map of VM names to their IP addresses"
  value       = local.vm_ips
}

output "vm_details" {
  description = "Detailed information about each VM"
  value = {
    for k, v in proxmox_virtual_environment_vm.vm : k => {
      vm_id       = v.vm_id
      name        = v.name
      node        = v.node_name
      ip_address  = local.vm_ips[k]
      cores       = v.cpu[0].cores
      memory_mb   = v.memory[0].dedicated
      description = v.description
    }
  }
}

output "ansible_hosts" {
  description = "Map suitable for Ansible inventory"
  value       = local.vm_ips
}
