# Tailscale Operator Module Variables

variable "deploy_tailscale" {
  description = "Whether to deploy Tailscale Operator"
  type        = bool
  default     = false
}

# OAuth Credentials (don't expire)
variable "oauth_client_id" {
  description = "Tailscale OAuth Client ID (create at https://login.tailscale.com/admin/settings/oauth)"
  type        = string
  sensitive   = true
}

variable "oauth_client_secret" {
  description = "Tailscale OAuth Client Secret"
  type        = string
  sensitive   = true
}

variable "tailnet" {
  description = "Tailnet name (e.g., example.org or example.github)"
  type        = string
}

variable "manage_acl" {
  description = "Whether to manage Tailscale ACLs via Terraform"
  type        = bool
  default     = false
}

variable "acl_admin_email" {
  description = "Admin email for ACL tag ownership (e.g., admin@example.com)"
  type        = string
  default     = ""
}

variable "auto_approve_routes" {
  description = "Whether to auto-approve subnet routes for the connector device"
  type        = bool
  default     = true
}

variable "hostname" {
  description = "Hostname for the subnet router in your tailnet"
  type        = string
  default     = "k3s-router"
}

variable "advertised_routes" {
  description = "List of CIDRs to advertise to Tailscale network"
  type        = list(string)
  default = [
    "10.42.0.0/16",    # Pod network
    "10.43.0.0/16",    # Service network
    "192.168.7.224/29" # MetalLB IPs (230-235)
  ]
}

variable "advertise_exit_node" {
  description = "Whether to advertise as an exit node"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tailscale ACL tags to apply (e.g., tag:k8s)"
  type        = list(string)
  default     = ["tag:k8s"]
}
