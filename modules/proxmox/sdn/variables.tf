# SDN Module Variables

variable "zone_id" {
  description = "Unique identifier for the SDN VXLAN zone (max 8 chars, alphanumeric)"
  type        = string
  default     = "k3szone"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,7}$", var.zone_id))
    error_message = "Zone ID must start with a letter, be alphanumeric, and max 8 characters."
  }
}

variable "vnet_id" {
  description = "Unique identifier for the SDN VNet (max 8 chars, alphanumeric)"
  type        = string
  default     = "k3svnet"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,7}$", var.vnet_id))
    error_message = "VNet ID must start with a letter, be alphanumeric, and max 8 characters."
  }
}

variable "vnet_alias" {
  description = "Human-readable alias for the VNet"
  type        = string
  default     = "K3s Cluster Network"
}

variable "vxlan_tag" {
  description = "VXLAN Network Identifier (VNI) - unique ID for the overlay network (1-16777215)"
  type        = number
  default     = 100

  validation {
    condition     = var.vxlan_tag >= 1 && var.vxlan_tag <= 16777215
    error_message = "VXLAN tag must be between 1 and 16777215."
  }
}

variable "proxmox_node_ips" {
  description = "List of Proxmox node IP addresses for VXLAN peer communication"
  type        = list(string)

  validation {
    condition     = length(var.proxmox_node_ips) >= 2
    error_message = "At least 2 Proxmox node IPs are required for VXLAN overlay."
  }
}

variable "mtu" {
  description = "MTU for the VXLAN network (must be 50 bytes less than physical MTU)"
  type        = number
  default     = 1450 # Standard for 1500 MTU physical network
}

variable "subnet_cidr" {
  description = "CIDR for the SDN subnet (e.g., 10.0.0.0/24)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "subnet_gateway" {
  description = "Gateway IP for the SDN subnet"
  type        = string
  default     = "10.0.0.1"
}

# Optional DNS configuration
variable "dns_server" {
  description = "DNS server for the SDN zone (optional)"
  type        = string
  default     = null
}

variable "dns_zone" {
  description = "DNS zone for the SDN (optional, e.g., cluster.local)"
  type        = string
  default     = null
}

# DHCP Configuration (optional)
variable "enable_dhcp" {
  description = "Enable DHCP for the subnet (false for static K3s IPs)"
  type        = bool
  default     = false
}

variable "dhcp_start" {
  description = "DHCP range start IP (only used if enable_dhcp=true)"
  type        = string
  default     = "10.0.0.100"
}

variable "dhcp_end" {
  description = "DHCP range end IP (only used if enable_dhcp=true)"
  type        = string
  default     = "10.0.0.200"
}

variable "dhcp_dns_server" {
  description = "DNS server for DHCP clients (only used if enable_dhcp=true)"
  type        = string
  default     = "10.0.0.1"
}

variable "enable_snat" {
  description = "Enable SNAT for the subnet (allows outbound internet from private network)"
  type        = bool
  default     = false
}
