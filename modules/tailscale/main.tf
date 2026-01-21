# Tailscale Kubernetes Operator Module
# Uses OAuth credentials (no expiry) instead of auth keys

# =============================================================================
# Tailscale ACL Management
# =============================================================================
# Manages ACLs to auto-approve subnet routes for the k8s tag

resource "tailscale_acl" "kubernetes" {
  count = var.deploy_tailscale && var.manage_acl ? 1 : 0

  acl = jsonencode({
    // Define tag owners - autogroup:admin includes OAuth clients with admin scope
    tagOwners = {
      "tag:k8s" = var.acl_admin_email != "" ? [var.acl_admin_email] : ["autogroup:admin"]
    }

    // ACL rules - allow all tagged nodes and admins to communicate
    acls = [
      {
        action = "accept"
        src    = ["tag:k8s"]
        dst    = ["*:*"]
      },
      {
        action = "accept"
        src    = ["autogroup:member"]
        dst    = ["*:*"]
      }
    ]

    // Auto-approve subnet routes for k8s tagged devices
    autoApprovers = {
      routes = {
        for route in var.advertised_routes : route => ["tag:k8s"]
      }
      exitNode = var.advertise_exit_node ? ["tag:k8s"] : []
    }

    // SSH rules (optional)
    ssh = [
      {
        action = "check"
        src    = ["autogroup:admin"]
        dst    = ["autogroup:self"]
        users  = ["autogroup:nonroot", "root"]
      }
    ]
  })
}

# =============================================================================
# Kubernetes Resources
# =============================================================================

resource "kubernetes_namespace_v1" "tailscale" {
  count = var.deploy_tailscale ? 1 : 0

  metadata {
    name = "tailscale"
    labels = {
      "app.kubernetes.io/name"       = "tailscale-operator"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Deploy Tailscale Operator via Helm
# The Helm chart includes all necessary CRDs
resource "helm_release" "tailscale_operator" {
  count = var.deploy_tailscale ? 1 : 0

  depends_on = [tailscale_acl.kubernetes]

  name       = "tailscale-operator"
  repository = "https://pkgs.tailscale.com/helmcharts"
  chart      = "tailscale-operator"
  namespace  = kubernetes_namespace_v1.tailscale[0].metadata[0].name
  version    = "1.92.5"

  # Wait for CRDs to be established
  wait = true

  set = [
    {
      name  = "oauth.clientId"
      value = var.oauth_client_id
    },
    {
      name  = "operatorConfig.defaultTags[0]"
      value = "tag:k8s"
    }
  ]

  set_sensitive = [
    {
      name  = "oauth.clientSecret"
      value = var.oauth_client_secret
    }
  ]
}

# Subnet Router Connector - using kubectl provider for CRD support
resource "kubectl_manifest" "subnet_router" {
  count = var.deploy_tailscale ? 1 : 0

  depends_on = [helm_release.tailscale_operator]

  yaml_body = yamlencode({
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "Connector"
    metadata = {
      name = var.hostname
    }
    spec = {
      hostname = var.hostname
      subnetRouter = {
        advertiseRoutes = var.advertised_routes
      }
      exitNode = var.advertise_exit_node
      tags     = var.tags
    }
  })

  # Don't wait - the operator handles reconciliation
  wait_for_rollout = false
}

# =============================================================================
# Auto-approve Subnet Routes
# =============================================================================
# Look up the device by hostname and approve its advertised routes

data "tailscale_device" "subnet_router" {
  count = var.deploy_tailscale && var.auto_approve_routes ? 1 : 0

  # The device name in Tailscale is just the hostname (k3s-router), not the FQDN
  hostname = var.hostname
  wait_for = "120s"

  depends_on = [kubectl_manifest.subnet_router]
}

resource "tailscale_device_subnet_routes" "subnet_router" {
  count = var.deploy_tailscale && var.auto_approve_routes ? 1 : 0

  device_id = data.tailscale_device.subnet_router[0].id
  routes    = var.advertised_routes
}
