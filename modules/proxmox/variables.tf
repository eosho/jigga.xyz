variable "vm_os_template" {
  description = "ID of the template VM to clone"
  type        = number
}

variable "ssh_public_key" {
  description = "Path to the public SSH key file for accessing the VMs"
  type        = string
}

variable "public_bridge" {
  description = "Proxmox network bridge for the public/LAN network"
  type        = string
}

variable "private_bridge" {
  description = "Proxmox network bridge for the private/cluster network"
  type        = string
}

variable "public_gateway" {
  description = "Gateway IP for the public/LAN network"
  type        = string
}

variable "k3s_nodes" {
  description = "Map defining K3s cluster nodes"
  type = map(object({
    target_node    = string
    template_id    = optional(number) # Per-VM template override
    cores          = number
    sockets        = number
    memory         = number
    disk_size      = number
    public_ip      = string
    private_ip     = string
    public_gateway = string
    is_control     = bool
  }))
}

variable "k3s_server_name" {
  description = "Name of the VM that will serve as the k3s control plane"
  type        = string
}

variable "vm_user" {
  description = "Default username for the VMs created via cloud-init"
  type        = string
}

variable "k3s_token" {
  description = "Secret token for k3s cluster registration"
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  description = "K3s version to install (e.g., v1.31.3+k3s1). Empty string = latest stable."
  type        = string
  default     = ""
}

variable "template_node" {
  description = "Proxmox node where the VM template is located"
  type        = string
  default     = "pve-alpha"
}

variable "ssh_private_key" {
  description = "Path to the private SSH key file for accessing the VMs"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "dns_zone" {
  description = "DNS zone for the cluster (e.g., jigga.xyz)"
  type        = string
  default     = "jigga.xyz"
}

variable "service_hostnames" {
  description = "List of service hostnames to add to /etc/hosts (without domain)"
  type        = list(string)
  default     = ["grafana", "prometheus", "traefik"]
}

variable "proxmox_nodes" {
  description = "Map of Proxmox host names to IPs for Ansible inventory"
  type        = map(string)
  default = {
    "pve-alpha" = "192.168.7.233"
    "pve-beta"  = "192.168.7.234"
    "pve-gamma" = "192.168.7.235"
  }
}

variable "extra_hosts" {
  description = "Map of additional hosts to include in Ansible inventory"
  type        = map(string)
  default     = {}
}