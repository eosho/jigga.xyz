# Root Terraform configuration file
# This file serves as the entry point to the Terraform configuration
# Provider versions are defined in versions.tf

# Configure the Proxmox Provider
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
  ssh {
    agent    = true
    username = "root" # SSH to Proxmox nodes for snippets upload
  }
}

# Configure Kubernetes Provider - uses kubeconfig file
provider "kubernetes" {
  alias = "kubernetes_provider"

  insecure = true # K3s uses self-signed certs

  config_path    = local.kubeconfig_path
  config_context = "default"
}

# Configure Helm Provider - uses kubeconfig file
provider "helm" {
  alias = "helm_provider"

  kubernetes = {
    insecure = true # K3s uses self-signed certs

    config_path    = local.kubeconfig_path
    config_context = "default"
  }
}

# Configure kubectl Provider - for CRD resources
provider "kubectl" {
  alias = "kubectl_provider"

  load_config_file = true
  config_path      = local.kubeconfig_path
  config_context   = "default"
}

# Configure Cloudflare Provider - for DNS records
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Configure Tailscale Provider - for ACL management
provider "tailscale" {
  alias = "tailscale_provider"

  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet
}

# Define local variables
locals {
  kubeconfig_path = "${path.module}/kubeconfig.yaml"
}

# =============================================================================
# Cloudflare DNS - Wildcard for Internal Services (Tailscale access)
# =============================================================================
# This allows *.int.jigga.xyz to resolve to Traefik LoadBalancer IP
# Traffic is routed via Tailscale subnet router to the cluster
resource "cloudflare_dns_record" "internal_wildcard" {
  count = var.deploy_kubernetes ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "*.int"
  content = "192.168.7.230" # Traefik LoadBalancer IP
  type    = "A"
  proxied = false # DNS-only, no Cloudflare proxy (for Tailscale routing)
  ttl     = 1     # Auto
  comment = "Wildcard for internal services via Tailscale"
}

# Create a placeholder kubeconfig file if it doesn't exist yet
resource "local_file" "placeholder_kubeconfig" {
  count    = fileexists(local.kubeconfig_path) ? 0 : 1
  filename = local.kubeconfig_path
  content  = <<-EOT
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://placeholder.local:6443
    insecure-skip-tls-verify: true
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
users:
- name: default
  user:
    token: placeholder
EOT
}

# =============================================================================
# SDN Module - VXLAN Overlay Network (Optional)
# =============================================================================
# Creates a VXLAN overlay network across Proxmox nodes for private VM communication.
# When enabled, this replaces the need for manual vmbr1 bridges on each node.
module "sdn" {
  source = "./modules/proxmox/sdn"
  count  = var.enable_sdn ? 1 : 0

  # Zone and VNet identifiers
  zone_id    = var.sdn_zone_id
  vnet_id    = var.sdn_vnet_id
  vnet_alias = var.sdn_vnet_alias

  # Proxmox node IPs for VXLAN peer communication
  proxmox_node_ips = var.proxmox_node_ips

  # Network configuration
  mtu            = var.sdn_mtu
  subnet_cidr    = var.sdn_subnet_cidr
  subnet_gateway = var.sdn_subnet_gateway
}

# Proxmox K3s VM Module - K3s cluster nodes
module "proxmox" {
  source = "./modules/proxmox"

  # Wait for SDN to be ready if enabled
  depends_on = [module.sdn]

  # Provider configuration
  vm_os_template = var.vm_os_template
  ssh_public_key = var.ssh_public_key
  template_node  = var.template_node

  # Network configuration (dual-bridge)
  # When SDN is enabled, use the VNet as the private bridge
  public_bridge  = var.public_bridge
  private_bridge = var.enable_sdn ? var.sdn_vnet_id : var.private_bridge
  public_gateway = var.public_gateway

  # K3s cluster configuration
  k3s_nodes       = var.k3s_nodes
  k3s_server_name = var.k3s_server_name
  vm_user         = var.vm_user
  k3s_token       = var.k3s_token
  k3s_version     = var.k3s_version

  # Use the internal domain suffix for /etc/hosts FQDN entries
  dns_zone = var.internal_domain_suffix

  # Include standalone VMs in Ansible inventory (use variable directly, IPs are known upfront)
  extra_hosts = { for name, vm in var.standalone_vms : name => split("/", vm.ip_address)[0] }
}

# =============================================================================
# Auto-fetch kubeconfig from control plane after VMs are created
# =============================================================================
resource "terraform_data" "fetch_kubeconfig" {
  depends_on = [module.proxmox]

  # Re-run if control plane IP changes
  triggers_replace = [local.control_plane_ip]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "for i in {1..30}; do ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 ${var.vm_user}@${local.control_plane_ip} 'test -f /etc/rancher/k3s/k3s.yaml' 2>/dev/null && break || sleep 10; done && scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${var.vm_user}@${local.control_plane_ip}:/etc/rancher/k3s/k3s.yaml ${path.module}/kubeconfig.yaml && sed -i 's/127.0.0.1/${local.control_plane_ip}/g' ${path.module}/kubeconfig.yaml"
  }
}

locals {
  # Extract control plane IP from k3s_nodes
  control_plane_ip = replace(
    [for name, vm in var.k3s_nodes : vm.public_ip if vm.is_control][0],
    "/24", ""
  )
}

# Kubernetes Infrastructure Module - Only created if deploy_kubernetes is true
module "kubernetes" {
  source = "./modules/kubernetes"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.proxmox, local_file.placeholder_kubeconfig]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }

  # Configuration
  deploy_kubernetes = var.deploy_kubernetes
  kubeconfig_path   = local.kubeconfig_path

  # MetalLB configuration
  metallb_addresses = var.metallb_addresses
}

# Ceph CSI Module - Provides persistent storage using Proxmox Ceph
module "ceph_csi" {
  source = "./modules/proxmox/ceph-csi"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.kubernetes]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }

  # Ceph configuration
  deploy_ceph_csi           = var.deploy_kubernetes
  ceph_cluster_id           = var.ceph_cluster_id
  ceph_monitors             = var.ceph_monitors
  ceph_user                 = "admin" # Or create dedicated 'kubernetes' user
  ceph_user_key             = var.ceph_admin_key
  ceph_pool                 = var.ceph_pool_name
  set_default_storage_class = true
}

# Monitoring Stack Module - Only created if deploy_kubernetes is true
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.kubernetes]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }

  # Only deploy monitoring if kubernetes is deployed
  deploy_monitoring                = var.deploy_kubernetes
  kubeconfig_path                  = local.kubeconfig_path
  grafana_admin_password           = var.grafana_admin_password
  grafana_domain                   = var.grafana_domain
  k3s_server_ip                    = var.k3s_server_ip
  alertmanager_discord_webhook_url = var.alertmanager_discord_webhook_url
}

# Ingress Module - Only created if deploy_kubernetes is true
module "ingress" {
  source = "./modules/ingress"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.kubernetes, module.monitoring, module.argocd]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
  }

  # Configuration
  kubeconfig_path     = local.kubeconfig_path
  grafana_domain      = var.grafana_domain
  prometheus_domain   = var.prometheus_domain
  alertmanager_domain = var.alertmanager_domain
  argocd_domain       = var.argocd_domain
  deploy_argocd       = var.deploy_argocd
  enable_tls          = var.enable_tls
  cluster_issuer      = "letsencrypt-dns-${var.letsencrypt_environment}"
}

# Cert-Manager Module for Let's Encrypt integration - Only created if deploy_kubernetes is true
module "cert_manager" {
  source = "./modules/cert-manager"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.kubernetes]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }

  # Configuration
  kubeconfig_path = local.kubeconfig_path
  email_address   = var.email_address
  environment     = var.letsencrypt_environment

  # DNS-01 Challenge (Cloudflare) for internal services
  enable_dns01         = var.enable_cloudflare_dns01
  cloudflare_api_token = var.cloudflare_api_token
  dns_zone             = var.dns_zone
}

# ArgoCD Module - GitOps Continuous Delivery
module "argocd" {
  source = "./modules/argocd"
  count  = var.deploy_kubernetes && var.deploy_argocd ? 1 : 0

  depends_on = [module.kubernetes]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
    kubectl    = kubectl.kubectl_provider
  }

  # Configuration
  deploy_argocd       = var.deploy_argocd
  kubeconfig_path     = local.kubeconfig_path
  argocd_domain       = var.argocd_domain
  admin_password_hash = var.argocd_admin_password

  # App of Apps - automatically deploys applications from Git
  git_repo_url        = var.argocd_git_repo_url
  git_ssh_private_key = file(pathexpand("~/.ssh/id_rsa"))
  git_target_revision = var.git_target_revision

  # SOPS/KSOPS configuration for decrypting secrets
  sops_age_key = var.sops_age_key
}

# =============================================================================
# Cloudflare Tunnel - Public access to services via Cloudflare's network
# =============================================================================
module "cloudflare_tunnel" {
  source = "./modules/cloudflare-tunnel"
  count  = var.deploy_kubernetes && var.deploy_cloudflare_tunnel ? 1 : 0

  depends_on = [module.kubernetes]

  providers = {
    kubernetes = kubernetes.kubernetes_provider
    cloudflare = cloudflare
  }

  # Configuration
  deploy_cloudflare_tunnel = var.deploy_cloudflare_tunnel
  kubeconfig_path          = local.kubeconfig_path
  tunnel_name              = var.cloudflare_tunnel_name
  tunnel_credentials       = var.cloudflare_tunnel_credentials
  ingress_rules            = var.cloudflare_tunnel_ingress_rules
  replicas                 = 2

  # DNS Configuration
  cloudflare_zone_id = var.cloudflare_zone_id
  create_dns_records = true
}

# =============================================================================
# Tailscale - Private VPN access to cluster services
# =============================================================================
module "tailscale" {
  source = "./modules/tailscale"
  count  = var.deploy_kubernetes && var.deploy_tailscale ? 1 : 0

  depends_on = [module.kubernetes]

  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
    kubectl    = kubectl.kubectl_provider
    tailscale  = tailscale.tailscale_provider
  }

  # Configuration
  deploy_tailscale    = var.deploy_tailscale
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet
  manage_acl          = var.tailscale_manage_acl
  acl_admin_email     = var.tailscale_acl_admin_email
  auto_approve_routes = var.tailscale_auto_approve_routes
  hostname            = var.tailscale_hostname
  advertised_routes   = var.tailscale_advertised_routes
  advertise_exit_node = var.tailscale_advertise_exit_node
  tags                = var.tailscale_tags
}

# =============================================================================
# Standalone VMs - Development boxes, utility servers, etc.
# =============================================================================
module "standalone_vms" {
  source = "./modules/proxmox/vm"
  count  = length(var.standalone_vms) > 0 ? 1 : 0

  vms             = var.standalone_vms
  vm_os_template  = var.standalone_vm_template
  template_node   = var.template_node
  default_storage = "ceph-pool"
  vm_user         = var.vm_user
  ssh_public_key  = var.ssh_public_key
  dns_zone        = var.internal_domain
}