variable "proxmox_api_url" {
  description = "URL for the Proxmox API (e.g., https://proxmox.example.com:8006/api2/json)"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID (e.g., user@pam!tokenid)"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "vm_os_template" {
  description = "ID of the template VM to clone"
  type        = number
}

variable "template_node" {
  description = "Proxmox node where the VM template is located"
  type        = string
  default     = "pve-alpha"
}

variable "ssh_public_key" {
  description = "Path to the public SSH key file for accessing the VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "public_bridge" {
  description = "Proxmox network bridge for the public/LAN network"
  type        = string
  default     = "vmbr0"
}

variable "private_bridge" {
  description = "Proxmox network bridge for the private/cluster network"
  type        = string
  default     = "vmbr1"
}

variable "public_gateway" {
  description = "Gateway IP for the public/LAN network"
  type        = string
  default     = "192.168.7.1"
}

variable "k3s_version" {
  description = "K3s version to install (e.g., v1.31.3+k3s1). Empty string = latest stable."
  type        = string
  default     = "" # Latest stable
}

# =============================================================================
# K3s Cluster Node Definitions
# =============================================================================
variable "k3s_nodes" {
  description = "Map defining K3s cluster nodes (control plane and workers)"
  type = map(object({
    target_node    = string           # Proxmox node to deploy to
    template_id    = optional(number) # Template VM ID (overrides vm_os_template)
    cores          = number
    sockets        = number
    memory         = number # In MiB
    disk_size      = number # In GB
    public_ip      = string # CIDR format - LAN access (192.168.7.x)
    private_ip     = string # CIDR format - Cluster internal (10.0.0.x)
    public_gateway = string # Gateway IP for LAN network
    is_control     = bool   # Whether this is a control plane node
  }))
  default = {
    "ichigo" = {
      target_node    = "pve-alpha"
      template_id    = null # Uses vm_os_template default
      cores          = 4
      sockets        = 2
      memory         = 16384
      disk_size      = 128
      public_ip      = "192.168.7.223/24"
      private_ip     = "10.0.0.10/24"
      public_gateway = "192.168.7.1"
      is_control     = true
    }
    "naruto" = {
      target_node    = "pve-beta"
      template_id    = null # Uses vm_os_template default
      cores          = 4
      sockets        = 2
      memory         = 16384
      disk_size      = 128
      public_ip      = "192.168.7.224/24"
      private_ip     = "10.0.0.11/24"
      public_gateway = "192.168.7.1"
      is_control     = false
    }
    "tanjiro" = {
      target_node    = "pve-gamma"
      template_id    = null # Uses vm_os_template default
      cores          = 4
      sockets        = 2
      memory         = 16384
      disk_size      = 128
      public_ip      = "192.168.7.225/24"
      private_ip     = "10.0.0.12/24"
      public_gateway = "192.168.7.1"
      is_control     = false
    }
  }
}

variable "k3s_server_name" {
  description = "Name of the VM that will serve as the k3s control plane"
  type        = string
  default     = "ichigo"
}

variable "k3s_server_ip" {
  description = "IP address of the K3s control plane node"
  type        = string
}

variable "vm_user" {
  description = "Default username for the VMs created via cloud-init"
  type        = string
  default     = "root"
}

variable "k3s_token" {
  description = "Secret token for k3s cluster registration"
  type        = string
  sensitive   = true
}

variable "deploy_kubernetes" {
  description = "Whether to deploy Kubernetes resources. Set to true only after cluster is ready and kubeconfig is configured."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Ceph RBD CSI Configuration
# -----------------------------------------------------------------------------
variable "ceph_cluster_id" {
  description = "Ceph cluster FSID (from: ceph mon dump | grep fsid)"
  type        = string
}

variable "ceph_monitors" {
  description = "List of Ceph monitor addresses (IP:port)"
  type        = list(string)
}

variable "ceph_admin_key" {
  description = "Ceph admin key (from: ceph auth get-key client.admin)"
  type        = string
  sensitive   = true
}

variable "ceph_pool_name" {
  description = "Ceph pool name for Kubernetes PVs"
  type        = string
  default     = "kubernetes"
}

variable "metallb_addresses" {
  description = "IP address ranges for MetalLB to use (list of CIDRs or /32s)"
  type        = list(string)
  default     = ["192.168.7.230-192.168.7.235"] # 6 IPs for LoadBalancer services
}

variable "grafana_admin_password" {
  description = "Password for the Grafana admin user"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "grafana_domain" {
  description = "Domain name for Grafana"
  type        = string
  default     = "grafana.int.jigga.xyz"
}

variable "prometheus_domain" {
  description = "Domain name for Prometheus UI"
  type        = string
  default     = "prometheus.int.jigga.xyz"
}

variable "alertmanager_domain" {
  description = "Domain name for Alertmanager UI"
  type        = string
  default     = "alertmanager.int.jigga.xyz"
}

variable "alertmanager_discord_webhook_url" {
  description = "Discord webhook URL for Alertmanager notifications"
  type        = string
  sensitive   = true
  default     = ""
}

variable "internal_domain" {
  description = "Base domain for internal services (e.g., int.jigga.xyz)"
  type        = string
  default     = "int.jigga.xyz"
}

variable "public_domain" {
  description = "Base domain for public services (e.g., jigga.xyz)"
  type        = string
  default     = "jigga.xyz"
}

variable "email_address" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
  default     = "admin@example.com"
}

variable "enable_tls" {
  description = "Whether to enable TLS for Ingress resources"
  type        = bool
  default     = false
}

# =============================================================================
# SDN Configuration (Optional - VXLAN Overlay Network)
# =============================================================================
# Enable SDN to create a VXLAN overlay network across Proxmox nodes.
# This replaces the need for manual vmbr1 bridges on each node.
# When enabled, the VNet bridge will be used for private/cluster networking.

variable "enable_sdn" {
  description = "Enable Proxmox SDN (VXLAN overlay network) for cross-node VM communication"
  type        = bool
  default     = false
}

variable "sdn_zone_id" {
  description = "SDN VXLAN zone ID (max 8 chars, alphanumeric)"
  type        = string
  default     = "k3szone"
}

variable "sdn_vnet_id" {
  description = "SDN VNet ID - this becomes the bridge name for VMs (max 8 chars)"
  type        = string
  default     = "k3svnet"
}

variable "sdn_vnet_alias" {
  description = "Human-readable alias for the SDN VNet"
  type        = string
  default     = "K3s Cluster Network"
}

variable "proxmox_node_ips" {
  description = "List of Proxmox node IP addresses for VXLAN peer communication"
  type        = list(string)
  default     = ["192.168.7.233", "192.168.7.234", "192.168.7.235"] # pve-alpha, beta, gamma
}

variable "sdn_mtu" {
  description = "MTU for VXLAN network (must be 50 bytes less than physical MTU, e.g., 1450 for 1500)"
  type        = number
  default     = 1450
}

variable "sdn_subnet_cidr" {
  description = "CIDR for the SDN private subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "sdn_subnet_gateway" {
  description = "Gateway IP for the SDN subnet"
  type        = string
  default     = "10.0.0.1"
}

# =============================================================================
# ArgoCD Configuration
# =============================================================================

variable "deploy_argocd" {
  description = "Deploy ArgoCD for GitOps continuous delivery"
  type        = bool
  default     = true
}

variable "argocd_domain" {
  description = "Domain for ArgoCD UI"
  type        = string
  default     = "argocd.int.jigga.xyz"
}

variable "argocd_admin_password" {
  description = "Admin password for ArgoCD (bcrypt hash). Generate with: htpasswd -nbBC 10 '' 'password' | tr -d ':\\n'"
  type        = string
  default     = "D@rkC10ud!" # Empty = use auto-generated password
  sensitive   = true
}

variable "argocd_git_repo_url" {
  description = "Git repository URL for ArgoCD applications (app of apps pattern)"
  type        = string
  default     = "git@github.com:eosho/jigga.xyz.git"
}

variable "argocd_git_ssh_private_key" {
  description = "SSH private key for ArgoCD to access Git repositories"
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_target_revision" {
  description = "Git branch/tag/commit for ArgoCD to track"
  type        = string
  default     = "main"
}

variable "sops_age_key" {
  description = "AGE private key for SOPS secret decryption (full key file contents including the comment line)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "letsencrypt_environment" {
  description = "Let's Encrypt environment: 'prod' or 'staging'"
  type        = string
  default     = "prod"
}

# =============================================================================
# Cloudflare DNS-01 Configuration
# =============================================================================
variable "enable_cloudflare_dns01" {
  description = "Enable DNS-01 challenge using Cloudflare for internal services TLS"
  type        = bool
  default     = false
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit permissions"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for DNS record management"
  type        = string
  default     = ""
}

variable "dns_zone" {
  description = "DNS zone for Cloudflare (e.g., jigga.xyz)"
  type        = string
  default     = "jigga.xyz"
}

variable "internal_domain_suffix" {
  description = "Suffix for internal services (e.g., int.jigga.xyz)"
  type        = string
  default     = "int.jigga.xyz"
}

# =============================================================================
# Cloudflare Tunnel Configuration
# =============================================================================
variable "deploy_cloudflare_tunnel" {
  description = "Deploy Cloudflare Tunnel for public access to services"
  type        = bool
  default     = false
}

variable "cloudflare_tunnel_name" {
  description = "Name of the Cloudflare Tunnel"
  type        = string
  default     = "jigga-tunnel"
}

variable "cloudflare_tunnel_credentials" {
  description = "Cloudflare Tunnel credentials (from cloudflared tunnel create)"
  type = object({
    account_tag   = string
    tunnel_secret = string
    tunnel_id     = string
  })
  default = {
    account_tag   = ""
    tunnel_secret = ""
    tunnel_id     = ""
  }
  sensitive = true
}

variable "cloudflare_tunnel_ingress_rules" {
  description = "Ingress rules for Cloudflare Tunnel"
  type = list(object({
    hostname = string
    service  = string
  }))
  default = [
    {
      hostname = "jigga.xyz"
      service  = "http://homepage.svc.cluster.local:80"
    }
  ]
}

# =============================================================================
# Tailscale Configuration (OAuth - no expiry)
# =============================================================================
variable "deploy_tailscale" {
  description = "Deploy Tailscale Operator for private VPN access"
  type        = bool
  default     = false
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth Client ID (create at https://login.tailscale.com/admin/settings/oauth)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth Client Secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_tailnet" {
  description = "Tailnet name (e.g., example.org or yourdomain.github)"
  type        = string
  default     = ""
}

variable "tailscale_manage_acl" {
  description = "Whether to manage Tailscale ACLs via Terraform (auto-approve routes)"
  type        = bool
  default     = false
}

variable "tailscale_acl_admin_email" {
  description = "Admin email for ACL tag ownership (leave empty to use autogroup:admin)"
  type        = string
  default     = ""
}

variable "tailscale_auto_approve_routes" {
  description = "Whether to auto-approve subnet routes for the connector device"
  type        = bool
  default     = true
}

variable "tailscale_hostname" {
  description = "Hostname for the subnet router in your tailnet"
  type        = string
  default     = "k3s-router"
}

variable "tailscale_advertised_routes" {
  description = "CIDRs to advertise to the Tailscale network"
  type        = list(string)
  default = [
    "10.42.0.0/16",    # K3s Pod network
    "10.43.0.0/16",    # K3s Service network
    "192.168.7.224/29" # MetalLB IPs (230-235)
  ]
}

variable "tailscale_advertise_exit_node" {
  description = "Whether to advertise as a Tailscale exit node"
  type        = bool
  default     = false
}

variable "tailscale_tags" {
  description = "Tailscale ACL tags to apply (must exist in your ACL policy)"
  type        = list(string)
  default     = ["tag:k8s"]
}

# =============================================================================
# Standalone VMs Configuration
# =============================================================================
variable "standalone_vms" {
  description = "Map of standalone VMs to create (dev boxes, utility servers, etc.)"
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

variable "standalone_vm_template" {
  description = "Default template VM ID for standalone VMs (Ubuntu 25.04)"
  type        = number
  default     = 9001
}