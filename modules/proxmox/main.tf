# Proxmox VM Creation Module

# Local variables for the module
locals {
  # Extract just the IP address from CIDR notation for easier use
  node_ips = { for k, v in var.k3s_nodes : k => {
    public_ip  = split("/", v.public_ip)[0]
    private_ip = split("/", v.private_ip)[0]
  } }

  # Control plane node name and API server URL (uses private IP)
  k3s_server_url = "https://${local.node_ips[var.k3s_server_name].private_ip}:6443"

  # Parse the SSH key file content
  ssh_public_key_content = file(var.ssh_public_key)
}

# Upload cloud-init user-data to Proxmox snippets storage
# This is uploaded FIRST so it can be referenced by the VM
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  for_each = var.k3s_nodes

  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.target_node

  source_raw {
    data = templatefile("${path.root}/templates/cloud-init-k3s.tftpl", {
      hostname    = each.key
      vm_user     = var.vm_user
      ssh_key     = chomp(local.ssh_public_key_content)
      is_control  = each.value.is_control
      k3s_token   = var.k3s_token
      k3s_version = var.k3s_version
      # Use PUBLIC IP for API server - more reliable than private SDN IP
      api_server_ip = local.node_ips[var.k3s_server_name].public_ip
    })

    file_name = "user-data-${each.key}.yml"
  }
}

# VM Resources
resource "proxmox_virtual_environment_vm" "k8s_node" {
  for_each = var.k3s_nodes

  # Wait for cloud-init file to be uploaded first
  depends_on = [proxmox_virtual_environment_file.cloud_init_user_data]

  node_name   = each.value.target_node
  name        = each.key
  description = "Kubernetes node ${each.key} managed by Terraform"
  tags        = ["k8s", "terraform"]

  # VM Hardware Configuration
  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # OS Boot Configuration
  clone {
    vm_id        = coalesce(each.value.template_id, var.vm_os_template)
    node_name    = each.value.target_node
    full         = true
    datastore_id = "local-lvm"
  }

  agent {
    enabled = true
  }

  boot_order = ["scsi0", "net0"]

  # Cloud-Init Configuration - use the uploaded snippets file
  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data[each.key].id

    # Public/LAN network (eth0)
    ip_config {
      ipv4 {
        address = each.value.public_ip
        gateway = each.value.public_gateway
      }
    }

    # Private/Cluster network (eth1) - no gateway needed
    ip_config {
      ipv4 {
        address = each.value.private_ip
      }
    }
  }

  # Network Interfaces - Dual bridge setup
  network_device {
    bridge = var.public_bridge
  }

  network_device {
    bridge = var.private_bridge
  }

  # Disk Configuration
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
    file_format  = "raw"
  }

  serial_device {}

  on_boot = true

  lifecycle {
    ignore_changes = [
      initialization,
      tags
    ]
  }
}

# Create output directories
resource "terraform_data" "create_ansible_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.root}/ansible/playbooks"
  }
}

# Generate /etc/hosts file for Ansible playbook
resource "local_file" "ansible_hosts_file" {
  depends_on = [terraform_data.create_ansible_dir]

  content = templatefile("${path.root}/templates/etc_hosts.tftpl", {
    hosts = concat(
      # K3s nodes with short names
      [for name, vm in proxmox_virtual_environment_vm.k8s_node : {
        hostname = name
        ip       = local.node_ips[name].public_ip
      }],
      # K3s nodes with FQDN
      [for name, vm in proxmox_virtual_environment_vm.k8s_node : {
        hostname = "${name}.${var.dns_zone}"
        ip       = local.node_ips[name].public_ip
      }],
      # Service hostnames (via Traefik on control node)
      [for svc in var.service_hostnames : {
        hostname = "${svc}.${var.dns_zone}"
        ip       = local.node_ips[var.k3s_server_name].public_ip
      }]
    )
  })

  filename             = "${path.root}/ansible/playbooks/hosts"
  file_permission      = "0644"
  directory_permission = "0755"
}

# Generate Ansible inventory from VM outputs
resource "local_file" "ansible_inventory" {
  depends_on = [terraform_data.create_ansible_dir]

  content = templatefile("${path.root}/templates/ansible_inventory.tftpl", {
    ansible_user    = var.vm_user
    ssh_private_key = var.ssh_private_key
    control_nodes = {
      for name, vm in proxmox_virtual_environment_vm.k8s_node :
      name => local.node_ips[name].public_ip
      if var.k3s_nodes[name].is_control
    }
    worker_nodes = {
      for name, vm in proxmox_virtual_environment_vm.k8s_node :
      name => local.node_ips[name].public_ip
      if !var.k3s_nodes[name].is_control
    }
    proxmox_nodes = var.proxmox_nodes
    extra_hosts   = var.extra_hosts
  })

  filename             = "${path.root}/ansible/inventory.yaml"
  file_permission      = "0644"
  directory_permission = "0755"
}

# Generate SSH config for easy access
resource "local_file" "ssh_config" {
  content = templatefile("${path.root}/templates/ssh_config.tftpl", {
    vm_ips       = { for name, vm in proxmox_virtual_environment_vm.k8s_node : name => local.node_ips[name].public_ip }
    vm_user      = var.vm_user
    ssh_key_path = var.ssh_private_key
    k3s_nodes    = var.k3s_nodes
  })

  filename             = "${path.root}/ssh_config"
  file_permission      = "0644"
  directory_permission = "0755"
}

# Run Ansible playbook to update /etc/hosts on all nodes
resource "terraform_data" "run_ansible_hosts" {
  depends_on = [
    proxmox_virtual_environment_vm.k8s_node,
    local_file.ansible_inventory,
    local_file.ansible_hosts_file
  ]

  triggers_replace = [
    # Re-run if any VM IP changes
    jsonencode(local.node_ips),
    # Re-run if hosts file content changes
    local_file.ansible_hosts_file.content
  ]

  provisioner "local-exec" {
    working_dir = "${path.root}/ansible"
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_CONFIG            = "${path.root}/ansible/ansible.cfg"
    }
    command = "ansible-playbook -i inventory.yaml playbooks/update-hosts.yaml"
  }
}