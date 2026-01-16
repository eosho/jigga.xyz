# =============================================================================
# Standalone VM Module - Variables
# =============================================================================
# Reusable module for creating standalone VMs with cloud-init support

variable "vms" {
  description = "Map of standalone VMs to create"
  type = map(object({
    target_node   = string           # Proxmox node to deploy to
    template_id   = optional(number) # Template VM ID (overrides default)
    cores         = number
    sockets       = optional(number, 1)
    memory        = number           # In MiB
    disk_size     = number           # In GB
    storage       = optional(string) # Storage for VM disk (default: local-lvm)
    ip_address    = string           # CIDR format (e.g., 192.168.7.240/24)
    gateway       = string           # Gateway IP
    dns_servers   = optional(list(string), ["1.1.1.1", "8.8.8.8"])
    bridge        = optional(string, "vmbr0")
    tags          = optional(list(string), [])
    description   = optional(string)
    start_on_boot = optional(bool, true)
  }))
  default = {}
}

variable "vm_os_template" {
  description = "Default template VM ID to clone from"
  type        = number
  default     = 9001 # Ubuntu 25.04 template
}

variable "template_node" {
  description = "Proxmox node where the template is located"
  type        = string
  default     = "pve-alpha"
}

variable "default_storage" {
  description = "Default storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_user" {
  description = "Default username for VMs (created via cloud-init)"
  type        = string
  default     = "groot"
}

variable "ssh_public_key" {
  description = "Path to SSH public key file"
  type        = string
}

variable "dns_zone" {
  description = "DNS zone for hostname FQDN"
  type        = string
  default     = "int.jigga.xyz"
}
