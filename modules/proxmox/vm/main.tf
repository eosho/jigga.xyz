# =============================================================================
# Standalone VM Module - Main Configuration
# =============================================================================
# Creates standalone VMs with full cloud-init support on Proxmox
# Designed for development boxes, utility servers, etc.

locals {
  # Extract IP without CIDR notation
  vm_ips = { for k, v in var.vms : k => split("/", v.ip_address)[0] }

  # Parse SSH public key
  ssh_public_key_content = file(var.ssh_public_key)
}

# =============================================================================
# Cloud-Init User Data
# =============================================================================
resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each = var.vms

  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.target_node

  source_raw {
    data = templatefile("${path.root}/templates/cloud-init-vm.tftpl", {
      hostname = each.key
      vm_user  = var.vm_user
      ssh_key  = chomp(local.ssh_public_key_content)
    })

    file_name = "user-data-${each.key}.yml"
  }
}

# =============================================================================
# VM Resources
# =============================================================================
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  depends_on = [proxmox_virtual_environment_file.cloud_init]

  node_name   = each.value.target_node
  name        = each.key
  description = coalesce(each.value.description, "Standalone VM ${each.key} managed by Terraform")
  tags        = concat(["terraform", "standalone"], each.value.tags)

  # VM Hardware Configuration
  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # Clone from template
  clone {
    vm_id        = coalesce(each.value.template_id, var.vm_os_template)
    node_name    = var.template_node
    full         = true
    datastore_id = coalesce(each.value.storage, var.default_storage)
  }

  # QEMU Guest Agent - wait for it with reasonable timeout
  agent {
    enabled = true
    timeout = "5m" # Don't wait forever if agent fails to start
  }

  boot_order = ["scsi0", "net0"]

  # Cloud-Init Configuration
  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id

    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.gateway
      }
    }

    dns {
      servers = each.value.dns_servers
    }
  }

  # Network Interface - Single bridge for standalone VMs
  network_device {
    bridge = each.value.bridge
  }

  # Disk Configuration
  disk {
    datastore_id = coalesce(each.value.storage, var.default_storage)
    interface    = "scsi0"
    size         = each.value.disk_size
    file_format  = "raw"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  # Serial console for cloud-init debugging
  serial_device {}

  on_boot = each.value.start_on_boot

  lifecycle {
    ignore_changes = [
      initialization,
      tags
    ]
  }
}

# =============================================================================
# Wait for VMs to be ready
# =============================================================================
resource "terraform_data" "wait_for_vm" {
  for_each = var.vms

  depends_on = [proxmox_virtual_environment_vm.vm]

  triggers_replace = [local.vm_ips[each.key]]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "echo 'Waiting for ${each.key} (${local.vm_ips[each.key]})...'; for i in $(seq 1 60); do ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 ${var.vm_user}@${local.vm_ips[each.key]} 'echo ready' 2>/dev/null && echo '${each.key} is ready!' && exit 0; echo \"Attempt $i/60 - waiting...\"; sleep 10; done; echo 'Timeout waiting for ${each.key}'; exit 1"
  }
}
